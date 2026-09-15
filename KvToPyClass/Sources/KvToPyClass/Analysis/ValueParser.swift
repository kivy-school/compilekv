//
//  ValueParser.swift
//  KvToPyClass
//

import Foundation
import KvParser
import PySwiftAST

/// Turns the text of a KV property value into a Python expression, with
/// `root`/`self` resolved, `#:set` names substituted and the keys it
/// watches worked out.
final class ValueParser {
    private let context: GenerationContext
    private let resolver: PropertyResolver
    
    init(context: GenerationContext, resolver: PropertyResolver) {
        self.context = context
        self.resolver = resolver
    }
    
    private var constants: [String: String] { context.directives.constants }
    
    /// Does the value track something, so it has to be bound as well as set?
    static func needsBinding(_ property: KvProperty) -> Bool {
        if let watchedKeys = property.watchedKeys, !watchedKeys.isEmpty {
            return true
        }
        return false
    }
    
    /// A KV property value is a Python expression: `text: whatever` means
    /// `widget.text = whatever`. Parse it and use it.
    func expression(for property: KvProperty) throws -> Expression {
        if property.isBlock { return valueBlockCall(property) }
        let valueStr = property.value.trimmingCharacters(in: .whitespaces)
        
        if let expr = parseValue(valueStr, assignedTo: property.name) {
            return expr
        }
        
        // Did not parse. Quote it, minus any quotes it already had.
        var literal = valueStr
        if literal.count >= 2,
           (literal.hasPrefix("\"") && literal.hasSuffix("\"")) || (literal.hasPrefix("'") && literal.hasSuffix("'")) {
            literal = String(literal.dropFirst().dropLast())
        }
        return Py.string(literal)
    }
    
    /// `_value_N()` -- what a block-valued property is assigned.
    func valueBlockCall(_ property: KvProperty) -> Expression {
        Py.call(context.rule.valueBlockName(property, counter: context.names))
    }
    
    /// The value as a Python expression, or nil to fall back to a string.
    ///
    /// A bare name is the awkward case. `orientation: vertical` is a sloppy
    /// literal far more often than a module global, so it stays a string --
    /// unless it is a `#:set` constant, which is substituted, or the property
    /// it is being assigned to cannot hold a string, in which case a string
    /// would be wrong no matter what.
    func parseValue(_ valueStr: String, assignedTo propertyName: String? = nil) -> Expression? {
        guard let assign = parseAssignedExpression(valueStr) else { return nil }
        
        if case .name(let name) = assign {
            if let constant = constants[name.id] {
                return parseValue(constant, assignedTo: propertyName)
            }
            guard let propertyName, !resolver.holdsString(propertyName) else { return nil }
        }
        
        let expr = substitutingConstants(in: resolveKvObjects(assign, selfName: context.selfScope.name))
        recordMetrics(in: expr)
        return expr
    }
    
    /// Parse a KV property value as a Python expression.
    ///
    /// Two repairs are tried, and only after the value has failed to parse as
    /// written, so text that means something -- a backslash or a trailing dot
    /// inside a string literal -- is left alone whenever it can be.
    func parseAssignedExpression(_ valueStr: String) -> Expression? {
        guard !valueStr.isEmpty else { return nil }
        
        if let expr = Self.parseAssigned(valueStr) { return expr }
        
        // A value spread over several lines arrives with its continuation
        // backslashes still in it, joined onto one line.
        let joined = valueStr.contains("\\")
            ? valueStr.replacingOccurrences(of: "\\", with: " ")
            : valueStr
        if joined != valueStr, let expr = Self.parseAssigned(joined) { return expr }
        
        // `2.` is a float to Python but not to the parser we use.
        let padded = paddingBareFloats(in: joined)
        if padded != joined, let expr = Self.parseAssigned(padded) { return expr }
        
        return nil
    }
    
    /// The right-hand side of `_tmp = source`, or nil if it does not parse.
    private static func parseAssigned(_ source: String) -> Expression? {
        guard let module = try? parsePython("_tmp = \(source)"),
              case .module(let statements) = module,
              case .assign(let assign) = statements.first
        else { return nil }
        return assign.value
    }
    
    /// Turn `2.` into `2.0`, leaving `2.5` and `self.x` alone.
    private func paddingBareFloats(in source: String) -> String {
        let characters = Array(source)
        var result = ""
        for (index, character) in characters.enumerated() {
            result.append(character)
            let followsDigit = index > 0 && characters[index - 1].isNumber
            let precedesDigit = index + 1 < characters.count && characters[index + 1].isNumber
            if character == "." && followsDigit && !precedesDigit {
                result.append("0")
            }
        }
        return result
    }
    
    /// The parsed value of a `#:set` constant, or nil if `name` is not one.
    func constantExpression(named name: String) -> Expression? {
        guard let value = constants[name] else { return nil }
        return Self.parseAssigned(value)
    }
    
    /// Replace `#:set` names anywhere in an expression, so `plex_16 + 4` works
    /// as well as a bare `plex_16`.
    func substitutingConstants(in expr: Expression) -> Expression {
        guard !constants.isEmpty else { return expr }
        return mapNames(in: expr) { name in constantExpression(named: name.id) }
    }
    
    /// Note any name the expression reads, so generate() can import the
    /// kivy.metrics helpers and `#:import` aliases it uses.
    func recordMetrics(in expr: Expression) {
        context.metrics.record(namesUsed(in: expr))
    }
    
    func recordMetrics(inStatement statement: Statement) {
        forEachExpression(in: statement) { recordMetrics(in: $0) }
    }
    
    /// The resolved expression and the keys it watches. A value that does
    /// not parse still has the keys the KV parser worked out.
    func parsePropertyExpression(_ property: KvProperty) -> (expression: Expression?, keys: [BindableKey]) {
        // A block is called; its watched keys came from the KV compiler.
        if property.isBlock {
            return (valueBlockCall(property), resolver.bindableKeys(property.watchedKeys ?? []))
        }
        guard let parsed = parseAssignedExpression(property.value.trimmingCharacters(in: .whitespaces)) else {
            return (nil, resolver.bindableKeys(property.watchedKeys ?? []))
        }
        
        // Watched keys come off the unresolved tree so they still say
        // `root` / `self`; bindableKeys needs to know which is which before
        // they become variable names.
        let visitor = WatchedKeyVisitor()
        visitor.visitExpression(parsed)
        
        let expr = substitutingConstants(in: resolveKvObjects(parsed, selfName: context.selfScope.name))
        recordMetrics(in: expr)
        return (expr, resolver.bindableKeys(visitor.watchedKeys))
    }
    
    /// The names a property value reads.
    func referencedNames(_ property: KvProperty) throws -> Swift.Set<String> {
        if let expr = parsePropertyExpression(property).expression {
            return namesUsed(in: expr)
        }
        return namesUsed(in: try expression(for: property))
    }
}
