//
//  ClassGenerator.swift
//  KvToPyClass
//

import KvParser
import PySwiftAST

/// One rule, one class: its property declarations, `__init__`, `__del__`,
/// the conditional methods and the event handlers, merged into the class
/// the author already wrote if there is one.
final class ClassGenerator: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    /// The class a rule describes, or nil for a selector that styles
    /// existing widgets rather than defining one.
    func pyClass(for rule: KvRule) -> KvPyClass? {
        guard let resolved = resolver.resolvedClass(for: rule) else { return nil }
        return KvPyClass(
            name: resolved.name,
            bases: resolved.bases,
            rule: rule,
            existing: context.pythonClass(named: resolved.name),
            customProperties: resolver.customProperties(for: rule, bases: resolved.bases),
            ids: ModuleAnalysis.ids(in: rule.children)
        )
    }
    
    func classDef(for pyClass: KvPyClass) throws -> Statement {
        context.enter(pyClass)
        let rule = pyClass.rule
        
        // Add initial blank line at the start of class body
        var body: [Statement] = [.blank(1)]
        
        // Properties this rule declares, so they can be bound.
        for name in pyClass.customProperties.sorted() {
            body.append(ObjectProperty.new(name: name, owner: pyClass).declaration(default: Py.none))
        }
        
        if pyClass.needsInit {
            body.append(try generators.initMethod.initMethod(for: pyClass))
            // __init__ always initialises self._bindings, so __del__ can unbind them.
            body.append(generators.delMethod.delMethod(resets: context.rule.conditionalResets))
        }
        
        // The if/else and try/expect blocks, built while __init__ was.
        body.append(contentsOf: context.rule.conditionalMethods)
        
        for handler in rule.handlers {
            if let method = try generators.handlers.ruleMethod(handler) {
                body.append(method)
            }
        }
        
        // A rule with nothing in it still has to be a valid class body. The
        // blank line above does not count as content.
        if !body.contains(where: { if case .blank = $0 { return false } else { return true } }) {
            body.append(Py.pass)
        }
        
        // Fold the generated members into the class the author wrote, rather
        // than the other way round, so everything in it survives.
        if let existing = pyClass.existing {
            body = generators.classMerger.merge(body, into: existing.classDefAST.body)
        }
        
        return Py.classDef(pyClass.name, bases: pyClass.bases, body: body)
    }
}
