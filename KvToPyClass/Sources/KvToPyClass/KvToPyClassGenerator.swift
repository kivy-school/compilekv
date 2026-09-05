import Foundation
import KivyWidgetRegistry
import KvParser
import PySwiftAST
import PySwiftCodeGen
import PyFormatters

// MARK: - Property Expression Visitor

/// Visitor to extract watched keys from property value expressions (especially f-strings)
class PropertyExpressionVisitor: ExpressionVisitor {
    typealias ExpressionResult = Void
    
    var watchedKeys: [[String]] = []
    
    func visitAttribute(_ node: Attribute) {
        // Extract obj.attr patterns like app.title, self.width
        if case .name(let name) = node.value {
            watchedKeys.append([name.id, node.attr])
        }
        // Recursively visit the value expression
        visitExpression(node.value)
    }
    
    func visitJoinedStr(_ node: JoinedStr) {
        // Visit all FormattedValue expressions in the f-string
        for value in node.values {
            visitExpression(value)
        }
    }
    
    func visitFormattedValue(_ node: FormattedValue) {
        // Visit the expression inside the formatted value
        visitExpression(node.value)
    }
    
    func visitCall(_ node: Call) {
        // Covers str(app.prop) and any other wrapping call.
        visitExpression(node.fun)
        for arg in node.args {
            visitExpression(arg)
        }
    }
    
    // MARK: - Required Protocol Methods (no-op implementations)
    
    func visitConstant(_ node: Constant) {}
    func visitList(_ node: List) {
        // Visit all elements in the list
        for element in node.elts {
            visitExpression(element)
        }
    }
    func visitTuple(_ node: Tuple) {
        // Visit all elements in the tuple
        for element in node.elts {
            visitExpression(element)
        }
    }
    func visitDict(_ node: Dict) {}
    func visitSet(_ node: Set) {}
    func visitName(_ node: Name) {}
    func visitSubscript(_ node: Subscript) {}
    func visitStarred(_ node: Starred) {}
    func visitBinOp(_ node: BinOp) {
        // Visit both operands to extract watched keys
        visitExpression(node.left)
        visitExpression(node.right)
    }
    func visitUnaryOp(_ node: UnaryOp) {
        visitExpression(node.operand)
    }
    func visitBoolOp(_ node: BoolOp) {
        for value in node.values {
            visitExpression(value)
        }
    }
    func visitCompare(_ node: Compare) {
        visitExpression(node.left)
        for comparator in node.comparators {
            visitExpression(comparator)
        }
    }
    func visitLambda(_ node: Lambda) {}
    func visitListComp(_ node: ListComp) {}
    func visitSetComp(_ node: SetComp) {}
    func visitDictComp(_ node: DictComp) {}
    func visitGeneratorExp(_ node: GeneratorExp) {}
    func visitIfExp(_ node: IfExp) {
        // Visit all branches
        visitExpression(node.test)
        visitExpression(node.body)
        visitExpression(node.orElse)
    }
    func visitNamedExpr(_ node: NamedExpr) {}
    func visitYield(_ node: Yield) {}
    func visitYieldFrom(_ node: YieldFrom) {}
    func visitAwait(_ node: Await) {}
    func visitSlice(_ node: Slice) {}
}

// MARK: - Expression Replacement Helper

/// Replace an attribute access (obj.attr) with another attribute access (replacementObj.attr) in an expression tree
private func replaceAttributeWithAttribute(_ expr: PySwiftAST.Expression, object: String, attr: String, replacementObj: String) -> PySwiftAST.Expression {
    switch expr {
    case .attribute(let attrNode):
        // Check if this is the attribute we want to replace
        if case .name(let nameNode) = attrNode.value, nameNode.id == object, attrNode.attr == attr {
            // Replace with new attribute reference
            return .attribute(Attribute(
                value: .name(Name(id: replacementObj, ctx: .load, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)),
                attr: attr,
                ctx: .load,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            ))
        }
        return expr
        
    case .joinedStr(let joinedStr):
        // Recursively process f-string values
        let newValues = joinedStr.values.map { replaceAttributeWithAttribute($0, object: object, attr: attr, replacementObj: replacementObj) }
        return .joinedStr(JoinedStr(values: newValues, lineno: joinedStr.lineno, colOffset: joinedStr.colOffset, endLineno: joinedStr.endLineno, endColOffset: joinedStr.endColOffset))
        
    case .formattedValue(let formattedValue):
        // Recursively process the value inside {}
        let newValue = replaceAttributeWithAttribute(formattedValue.value, object: object, attr: attr, replacementObj: replacementObj)
        return .formattedValue(FormattedValue(value: newValue, conversion: formattedValue.conversion, formatSpec: formattedValue.formatSpec, lineno: formattedValue.lineno, colOffset: formattedValue.colOffset, endLineno: formattedValue.endLineno, endColOffset: formattedValue.endColOffset))
        
    case .call(let call):
        // Recursively process function and arguments
        let newFun = replaceAttributeWithAttribute(call.fun, object: object, attr: attr, replacementObj: replacementObj)
        let newArgs = call.args.map { replaceAttributeWithAttribute($0, object: object, attr: attr, replacementObj: replacementObj) }
        return .call(Call(fun: newFun, args: newArgs, keywords: call.keywords, lineno: call.lineno, colOffset: call.colOffset, endLineno: call.endLineno, endColOffset: call.endColOffset))
    
    case .tuple(let tuple):
        // Recursively process tuple elements
        let newElts = tuple.elts.map { replaceAttributeWithAttribute($0, object: object, attr: attr, replacementObj: replacementObj) }
        return .tuple(Tuple(elts: newElts, ctx: tuple.ctx, lineno: tuple.lineno, colOffset: tuple.colOffset, endLineno: tuple.endLineno, endColOffset: tuple.endColOffset))
    
    case .list(let list):
        // Recursively process list elements
        let newElts = list.elts.map { replaceAttributeWithAttribute($0, object: object, attr: attr, replacementObj: replacementObj) }
        return .list(List(elts: newElts, ctx: list.ctx, lineno: list.lineno, colOffset: list.colOffset, endLineno: list.endLineno, endColOffset: list.endColOffset))
    
    case .binOp(let binOp):
        // Recursively process binary operation
        let newLeft = replaceAttributeWithAttribute(binOp.left, object: object, attr: attr, replacementObj: replacementObj)
        let newRight = replaceAttributeWithAttribute(binOp.right, object: object, attr: attr, replacementObj: replacementObj)
        return .binOp(BinOp(left: newLeft, op: binOp.op, right: newRight, lineno: binOp.lineno, colOffset: binOp.colOffset, endLineno: binOp.endLineno, endColOffset: binOp.endColOffset))
    
    case .ifExp(let ifExp):
        // Recursively process conditional expression
        let newTest = replaceAttributeWithAttribute(ifExp.test, object: object, attr: attr, replacementObj: replacementObj)
        let newBody = replaceAttributeWithAttribute(ifExp.body, object: object, attr: attr, replacementObj: replacementObj)
        let newOrElse = replaceAttributeWithAttribute(ifExp.orElse, object: object, attr: attr, replacementObj: replacementObj)
        return .ifExp(IfExp(test: newTest, body: newBody, orElse: newOrElse, lineno: ifExp.lineno, colOffset: ifExp.colOffset, endLineno: ifExp.endLineno, endColOffset: ifExp.endColOffset))
        
    default:
        // For other expression types, return as-is
        return expr
    }
}

/// Replace an attribute access (obj.attr) with a simple name reference in an expression tree
/// Used when the callback receives the value as a named parameter
private func replaceAttributeWithNameRef(_ expr: PySwiftAST.Expression, object: String, attr: String, replacement: String) -> PySwiftAST.Expression {
    switch expr {
    case .attribute(let attrNode):
        // Check if this is the attribute we want to replace
        if case .name(let nameNode) = attrNode.value, nameNode.id == object, attrNode.attr == attr {
            // Replace with simple name reference
            return .name(Name(id: replacement, ctx: .load, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
        }
        return expr
        
    case .joinedStr(let joinedStr):
        // Recursively process f-string values
        let newValues = joinedStr.values.map { replaceAttributeWithNameRef($0, object: object, attr: attr, replacement: replacement) }
        return .joinedStr(JoinedStr(values: newValues, lineno: joinedStr.lineno, colOffset: joinedStr.colOffset, endLineno: joinedStr.endLineno, endColOffset: joinedStr.endColOffset))
        
    case .formattedValue(let formattedValue):
        // Recursively process the value inside {}
        let newValue = replaceAttributeWithNameRef(formattedValue.value, object: object, attr: attr, replacement: replacement)
        return .formattedValue(FormattedValue(value: newValue, conversion: formattedValue.conversion, formatSpec: formattedValue.formatSpec, lineno: formattedValue.lineno, colOffset: formattedValue.colOffset, endLineno: formattedValue.endLineno, endColOffset: formattedValue.endColOffset))
        
    case .call(let call):
        // Recursively process function and arguments
        let newFun = replaceAttributeWithNameRef(call.fun, object: object, attr: attr, replacement: replacement)
        let newArgs = call.args.map { replaceAttributeWithNameRef($0, object: object, attr: attr, replacement: replacement) }
        return .call(Call(fun: newFun, args: newArgs, keywords: call.keywords, lineno: call.lineno, colOffset: call.colOffset, endLineno: call.endLineno, endColOffset: call.endColOffset))
        
    default:
        // For other expression types, return as-is
        return expr
    }
}

/// Rewrite `root` to `self` in an expression tree.
///
/// `root` in KV is the widget the rule applies to; in the generated __init__
/// that is the instance being built. Event handlers already did this, property
/// values did not, so `text: root.name` emitted an undefined `root`.
private func replaceRootWithSelf(_ expr: PySwiftAST.Expression) -> PySwiftAST.Expression {
    func rename(_ name: Name) -> Name {
        guard name.id == "root" else { return name }
        return Name(id: "self", ctx: name.ctx, lineno: name.lineno, colOffset: name.colOffset, endLineno: name.endLineno, endColOffset: name.endColOffset)
    }
    
    switch expr {
    case .name(let node):
        return .name(rename(node))
        
    case .attribute(let node):
        return .attribute(Attribute(
            value: replaceRootWithSelf(node.value),
            attr: node.attr,
            ctx: node.ctx,
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .joinedStr(let node):
        return .joinedStr(JoinedStr(
            values: node.values.map(replaceRootWithSelf),
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .formattedValue(let node):
        return .formattedValue(FormattedValue(
            value: replaceRootWithSelf(node.value),
            conversion: node.conversion,
            formatSpec: node.formatSpec,
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .call(let node):
        return .call(Call(
            fun: replaceRootWithSelf(node.fun),
            args: node.args.map(replaceRootWithSelf),
            keywords: node.keywords.map { Keyword(arg: $0.arg, value: replaceRootWithSelf($0.value)) },
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .tuple(let node):
        return .tuple(Tuple(elts: node.elts.map(replaceRootWithSelf), ctx: node.ctx, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .list(let node):
        return .list(List(elts: node.elts.map(replaceRootWithSelf), ctx: node.ctx, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .binOp(let node):
        return .binOp(BinOp(left: replaceRootWithSelf(node.left), op: node.op, right: replaceRootWithSelf(node.right), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .ifExp(let node):
        return .ifExp(IfExp(test: replaceRootWithSelf(node.test), body: replaceRootWithSelf(node.body), orElse: replaceRootWithSelf(node.orElse), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    default:
        return expr
    }
}

/// Replace all self.* attribute accesses with instance.* in an expression tree
/// Used for canvas bindings where the lambda should use the current instance state
private func replaceAllSelfWithInstance(_ expr: PySwiftAST.Expression) -> PySwiftAST.Expression {
    switch expr {
    case .attribute(let attrNode):
        // Check if this is a self.* attribute
        if case .name(let nameNode) = attrNode.value, nameNode.id == "self" {
            // Replace self with instance
            return .attribute(Attribute(
                value: .name(Name(id: "instance", ctx: .load, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)),
                attr: attrNode.attr,
                ctx: attrNode.ctx,
                lineno: attrNode.lineno,
                colOffset: attrNode.colOffset,
                endLineno: attrNode.endLineno,
                endColOffset: attrNode.endColOffset
            ))
        }
        return expr
        
    case .tuple(let tuple):
        let newElts = tuple.elts.map { replaceAllSelfWithInstance($0) }
        return .tuple(Tuple(elts: newElts, ctx: tuple.ctx, lineno: tuple.lineno, colOffset: tuple.colOffset, endLineno: tuple.endLineno, endColOffset: tuple.endColOffset))
    
    case .list(let list):
        let newElts = list.elts.map { replaceAllSelfWithInstance($0) }
        return .list(List(elts: newElts, ctx: list.ctx, lineno: list.lineno, colOffset: list.colOffset, endLineno: list.endLineno, endColOffset: list.endColOffset))
    
    case .binOp(let binOp):
        let newLeft = replaceAllSelfWithInstance(binOp.left)
        let newRight = replaceAllSelfWithInstance(binOp.right)
        return .binOp(BinOp(left: newLeft, op: binOp.op, right: newRight, lineno: binOp.lineno, colOffset: binOp.colOffset, endLineno: binOp.endLineno, endColOffset: binOp.endColOffset))
    
    case .call(let call):
        let newFun = replaceAllSelfWithInstance(call.fun)
        let newArgs = call.args.map { replaceAllSelfWithInstance($0) }
        return .call(Call(fun: newFun, args: newArgs, keywords: call.keywords, lineno: call.lineno, colOffset: call.colOffset, endLineno: call.endLineno, endColOffset: call.endColOffset))
    
    case .ifExp(let ifExp):
        let newTest = replaceAllSelfWithInstance(ifExp.test)
        let newBody = replaceAllSelfWithInstance(ifExp.body)
        let newOrElse = replaceAllSelfWithInstance(ifExp.orElse)
        return .ifExp(IfExp(test: newTest, body: newBody, orElse: newOrElse, lineno: ifExp.lineno, colOffset: ifExp.colOffset, endLineno: ifExp.endLineno, endColOffset: ifExp.endColOffset))
    
    default:
        return expr
    }
}

/// Supplies stable, unique suffixes for generated variable names.
///
/// Previously these came from `UUID()`, which meant every run produced a
/// different file for the same input. Numbering restarts for each class so
/// adding a widget to one rule does not renumber the rest of the file.
/// The rule currently being generated: which class, and which of its
/// properties can be bound to.
private final class RuleContext {
    var baseClasses: [String] = []
    var selfProperties = Swift.Set<String>()
}

private final class NameCounter {
    private var next = 0

    func take() -> Int {
        next += 1
        return next
    }

    func reset() {
        next = 0
    }
}

/// Generates Python class code from KV language rules
///
/// Kivy's Builder dynamically applies KV rules to widgets at runtime.
/// This generator instead creates equivalent Python class definitions that
/// produce the same widget tree structure and property bindings.
public struct KvToPyClassGenerator {
    
    private let module: KvModule
    private let pythonClasses: [PythonClassInfo]
    /// Body of the existing .py file, if one was supplied. Generated code is
    /// merged into this rather than replacing it.
    private let existingBody: [Statement]
    private let nameCounter = NameCounter()
    /// Set per rule, so the deep child helpers can answer "is self.x bindable?"
    /// without threading the rule through every signature.
    private let ruleContext = RuleContext()
    
    /// Track bindings that need to be unbound in __del__
    private struct BindingInfo {
        let sourceObj: String      // e.g., "app", "self"
        let property: String        // e.g., "title", "version"
        let callbackVar: String     // e.g., "_callback_0"
    }
    
    public init(module: KvModule, pythonClasses: [PythonClassInfo] = [], existingBody: [Statement] = []) {
        self.module = module
        self.pythonClasses = pythonClasses
        self.existingBody = existingBody
    }

    public init(module: KvModule, existing: PythonModuleInfo) {
        self.init(module: module, pythonClasses: existing.classes, existingBody: existing.body)
    }
    
    /// Generate Python code for all dynamic classes and rules
    public func generate() throws -> String {
        // Widgets Kivy ships get imported; anything else is a custom widget
        // from somewhere we cannot see, so it comes off the Factory.
        let widgetTypes = collectWidgetTypes()
        let external = widgetTypes.filter { !KivyWidgetRegistry.widgetExists($0) && !isDefinedHere($0) }
        
        var generatedClasses: [Statement] = []
        for rule in module.rules {
            generatedClasses.append(contentsOf: try generateClassForRule(rule))
        }
        
        let registrations = factoryRegistrations(for: generatedClasses)
        let needsFactory = !external.isEmpty || !registrations.isEmpty
        
        var imports = generateImports(for: widgetTypes.subtracting(external))
        if needsFactory {
            imports.append(.importFrom(ImportFrom(
                module: "kivy.factory",
                names: [Alias(name: "Factory", asName: nil)],
                level: 0,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )))
        }
        
        let aliases = external.sorted().map(factoryAlias)
        
        let statements = existingBody.isEmpty
            ? imports + aliases + generatedClasses + registrations
            : merge(
                imports: imports,
                aliases: aliases,
                classes: generatedClasses,
                registrations: registrations,
                into: existingBody
            )
        
        // Convert to Python source code
        let pyModule = Module.module(statements)
        
        // Apply Black formatter for proper blank line formatting
        let formatter = BlackFormatter()
        let formattedModule = formatter.formatDeep(pyModule)
        
        let code = try formatModule(formattedModule)
        
        return code
    }
    
    // MARK: - Factory
    
    /// Is this name a class the generated module defines, or one already in
    /// the .py we are extending?
    private func isDefinedHere(_ name: String) -> Bool {
        if pythonClasses.contains(where: { $0.name == name }) { return true }
        return module.rules.contains { resolvedClass(for: $0)?.name == name }
    }
    
    /// `MyWidget = Factory.MyWidget`
    ///
    /// A plain module constant so the name can be called: a PEP 695
    /// `type MyWidget = Factory.MyWidget` builds a TypeAliasType, which
    /// resolves lazily but is not callable, so `MyWidget(...)` would fail.
    /// The cost is that the Factory is read at import time, which means the
    /// widget has to be registered by then.
    private func factoryAlias(_ name: String) -> Statement {
        .assign(Assign(
            targets: [.name(Name(id: name, ctx: .store, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))],
            value: .attribute(Attribute(
                value: .name(makeName("Factory")),
                attr: name,
                ctx: .load,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )),
            typeComment: nil,
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        ))
    }
    
    /// `Factory.register("MyWidget", cls=MyWidget)` for each generated class,
    /// so other KV files and Builder can resolve it by name.
    private func factoryRegistrations(for classes: [Statement]) -> [Statement] {
        let registered = alreadyRegistered(in: existingBody)
        var statements: [Statement] = []
        for statement in classes {
            guard case .classDef(let classDef) = statement, !registered.contains(classDef.name) else {
                continue
            }
            statements.append(.expr(Expr(
                value: .call(Call(
                    fun: .attribute(Attribute(
                        value: .name(makeName("Factory")),
                        attr: "register",
                        ctx: .load,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )),
                    args: [.constant(makeConstant(.string(classDef.name)))],
                    keywords: [Keyword(arg: "cls", value: .name(makeName(classDef.name)))],
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )),
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )))
        }
        return statements
    }
    
    /// Names the file already passes to Factory.register, under any spelling
    /// of the first argument.
    private func alreadyRegistered(in body: [Statement]) -> Swift.Set<String> {
        var names = Swift.Set<String>()
        for statement in body {
            guard case .expr(let expr) = statement,
                  case .call(let call) = expr.value,
                  case .attribute(let callee) = call.fun,
                  callee.attr == "register",
                  case .name(let target) = callee.value,
                  target.id == "Factory",
                  let first = call.args.first,
                  case .constant(let constant) = first,
                  case .string(let name) = constant.value
            else { continue }
            names.insert(name)
        }
        return names
    }
    
    // MARK: - Merging Into An Existing File
    
    /// Fold generated imports and classes into the body of the existing .py.
    ///
    /// Imports land after the ones already there, classes replace the
    /// same-named definition in place, and everything else the file had --
    /// docstring, constants, helper functions, unrelated classes -- is left
    /// exactly where the author put it.
    private func merge(
        imports: [Statement],
        aliases: [Statement],
        classes: [Statement],
        registrations: [Statement],
        into body: [Statement]
    ) -> [Statement] {
        let alreadyBound = importedNames(in: body)
        let newImports = imports.compactMap { dropAliases(boundIn: alreadyBound, from: $0) }
        
        // A Factory alias is only needed for a name the file does not already
        // bind, whether by import, assignment or class definition.
        let boundAtModuleLevel = alreadyBound.union(assignedNames(in: body))
        let newAliases = aliases.filter { statement in
            guard case .assign(let assign) = statement,
                  case .name(let target) = assign.targets.first
            else { return true }
            return !boundAtModuleLevel.contains(target.id)
        }
        
        var generated: [String: Statement] = [:]
        for statement in classes {
            if case .classDef(let classDef) = statement {
                generated[classDef.name] = statement
            }
        }
        
        var result: [Statement] = []
        var used = Swift.Set<String>()
        for statement in body {
            if case .classDef(let classDef) = statement,
               let replacement = generated[classDef.name] {
                result.append(replacement)
                used.insert(classDef.name)
            } else {
                result.append(statement)
            }
        }
        
        // Rules with no matching class in the file are appended in KV order.
        for statement in classes {
            if case .classDef(let classDef) = statement, !used.contains(classDef.name) {
                result.append(statement)
            }
        }
        
        // Registrations name the classes, so they go last.
        result.append(contentsOf: registrations)
        
        let insertAt = importInsertionPoint(in: result)
        result.insert(contentsOf: newImports + newAliases, at: insertAt)
        return separateImportBlock(in: result, endingAt: insertAt + newImports.count + newAliases.count)
    }
    
    /// Module level names bound by a plain assignment or a class definition.
    private func assignedNames(in body: [Statement]) -> Swift.Set<String> {
        var names = Swift.Set<String>()
        for statement in body {
            switch statement {
            case .assign(let assign):
                for target in assign.targets {
                    if case .name(let name) = target { names.insert(name.id) }
                }
            case .classDef(let classDef):
                names.insert(classDef.name)
            case .functionDef(let funcDef):
                names.insert(funcDef.name)
            case .typeAlias(let alias):
                if case .name(let name) = alias.name { names.insert(name.id) }
            default:
                break
            }
        }
        return names
    }
    
    /// One blank line after the imports. BlackFormatter only spaces defs and
    /// classes, so without this a following constant butts up against them.
    private func separateImportBlock(in body: [Statement], endingAt index: Int) -> [Statement] {
        guard index > 0, index < body.count else { return body }
        switch body[index] {
        case .blank, .classDef, .functionDef, .asyncFunctionDef:
            return body
        default:
            var spaced = body
            spaced.insert(.blank(1), at: index)
            return spaced
        }
    }
    
    /// Every module level name an import statement binds, so we do not add an
    /// import for something the file already brings in (under any alias).
    private func importedNames(in body: [Statement]) -> Swift.Set<String> {
        var names = Swift.Set<String>()
        for statement in body {
            switch statement {
            case .importStmt(let node):
                for alias in node.names {
                    names.insert(alias.asName ?? alias.name.split(separator: ".").first.map(String.init) ?? alias.name)
                }
            case .importFrom(let node):
                for alias in node.names {
                    names.insert(alias.asName ?? alias.name)
                }
            default:
                break
            }
        }
        return names
    }
    
    /// Strip aliases already bound; returns nil when nothing is left to import.
    private func dropAliases(boundIn bound: Swift.Set<String>, from statement: Statement) -> Statement? {
        guard case .importFrom(let node) = statement else { return statement }
        let keep = node.names.filter { !bound.contains($0.asName ?? $0.name) }
        if keep.isEmpty { return nil }
        if keep.count == node.names.count { return statement }
        return .importFrom(ImportFrom(
            module: node.module,
            names: keep,
            level: node.level,
            lineno: node.lineno,
            colOffset: node.colOffset,
            endLineno: nil,
            endColOffset: nil
        ))
    }
    
    /// Just after the file's existing imports, or after its docstring.
    private func importInsertionPoint(in body: [Statement]) -> Int {
        var index = 0
        for (offset, statement) in body.enumerated() {
            switch statement {
            case .importStmt, .importFrom:
                index = offset + 1
            case .expr(let expr) where offset == 0:
                if case .constant(let constant) = expr.value, case .string = constant.value {
                    index = 1
                }
            case .blank:
                continue
            default:
                break
            }
        }
        return index
    }
    
    // MARK: - Helpers
    
    private func formatModule(_ module: Module) throws -> String {
        // Use PySwiftCodeGen to convert AST to Python source code
        return PySwiftCodeGen.generatePythonCode(from: module)
    }
    
    private func makeName(_ id: String) -> Name {
        Name(id: id, ctx: .load, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)
    }
    
    private func makeConstant(_ value: ConstantValue) -> Constant {
        Constant(value: value, kind: nil, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)
    }
    
    // MARK: - Import Generation
    
    /// Collect all widget types used in the module (excluding custom widgets defined in this module)
    private func collectWidgetTypes() -> Swift.Set<String> {
        var types = Swift.Set<String>()
        
        // First, collect all custom widget names defined in this module
        var customWidgets = Swift.Set<String>()
        for rule in module.rules {
            switch rule.selector {
            case .dynamicClass(let name, _):
                customWidgets.insert(name)
            case .name(let name):
                customWidgets.insert(name)
            default:
                break
            }
        }
        
        // Now collect widget types, excluding custom ones
        for rule in module.rules {
            // The resolved bases, so the implicit `Widget` fallback gets
            // imported too. Bases the existing .py already provides are
            // dropped later when the generated imports are merged into it.
            if let resolved = resolvedClass(for: rule) {
                for base in resolved.bases where !customWidgets.contains(base) {
                    types.insert(base)
                }
            }
            // Collect from children, excluding custom widgets
            collectTypesFromChildren(rule.children, into: &types, excluding: customWidgets)
        }
        
        return types
    }
    
    private func collectTypesFromChildren(_ children: [KvWidget], into types: inout Swift.Set<String>, excluding customWidgets: Swift.Set<String>) {
        for child in children {
            // Only add if it's not a custom widget
            if !customWidgets.contains(child.name) {
                types.insert(child.name)
            }
            collectTypesFromChildren(child.children, into: &types, excluding: customWidgets)
        }
    }
    
    /// Convert widget type name to appropriate kivy.uix module path
    private func kivyModuleForWidget(_ widgetName: String) -> String {
        let lowercased = widgetName.lowercased()
        return "kivy.uix.\(lowercased)"
    }
    
    private func generateImports(for widgetTypes: Swift.Set<String>) -> [Statement] {
        var imports: [Statement] = []
        var lineNum = 1
        
        // Import each widget type from its kivy.uix module
        for widgetType in widgetTypes.sorted() {
            let modulePath = kivyModuleForWidget(widgetType)
            let importStmt = ImportFrom(
                module: modulePath,
                names: [Alias(name: widgetType, asName: nil)],
                level: 0,
                lineno: lineNum,
                colOffset: 0,
                endLineno: nil,
                endColOffset: nil
            )
            imports.append(.importFrom(importStmt))
            lineNum += 1
        }
        
        // Import App if any bindings use 'app' (check both rule properties and child widgets)
        let needsApp = module.rules.contains { rule in
            rule.properties.contains { property in
                property.value.contains("app.")
            } || rule.handlers.contains { handler in
                handler.value.contains("app.")
            } || hasAppBindingsInChildren(rule.children) || hasAppBindingsInCanvas(rule)
        }
        
        if needsApp {
            let appImport = ImportFrom(
                module: "kivy.app",
                names: [Alias(name: "App", asName: nil)],
                level: 0,
                lineno: lineNum,
                colOffset: 0,
                endLineno: nil,
                endColOffset: nil
            )
            imports.append(.importFrom(appImport))
            lineNum += 1
        }
        
        // Collect property types that need to be imported
        let propertyTypes = collectPropertyTypes()
        
        if !propertyTypes.isEmpty {
            // Import specific property types from kivy.properties
            let propsImport = ImportFrom(
                module: "kivy.properties",
                names: propertyTypes.sorted().map { Alias(name: $0, asName: nil) },
                level: 0,
                lineno: lineNum,
                colOffset: 0,
                endLineno: nil,
                endColOffset: nil
            )
            imports.append(.importFrom(propsImport))
            lineNum += 1
        }
        
        // Collect graphics instruction types from canvas
        let graphicsTypes = collectGraphicsTypes()
        
        if !graphicsTypes.isEmpty {
            // Import graphics instructions from kivy.graphics
            let graphicsImport = ImportFrom(
                module: "kivy.graphics",
                names: graphicsTypes.sorted().map { Alias(name: $0, asName: nil) },
                level: 0,
                lineno: lineNum,
                colOffset: 0,
                endLineno: nil,
                endColOffset: nil
            )
            imports.append(.importFrom(graphicsImport))
        }
        
        return imports
    }
    
    private func collectPropertyTypes() -> Swift.Set<String> {
        var types = Swift.Set<String>()
        
        for rule in module.rules {
            guard let resolved = resolvedClass(for: rule) else { continue }
            
            let customProps = getCustomProperties(for: rule, baseClasses: resolved.bases)
            if !customProps.isEmpty {
                // Add ObjectProperty as default type for custom properties
                types.insert("ObjectProperty")
            }
        }
        
        return types
    }
    
    /// Collect all graphics instruction types used in canvas layers
    private func collectGraphicsTypes() -> Swift.Set<String> {
        var types = Swift.Set<String>()
        
        for rule in module.rules {
            // Check canvas.before
            if let canvasBefore = rule.canvasBefore {
                for instruction in canvasBefore.instructions {
                    types.insert(instruction.instructionType)
                }
            }
            
            // Check canvas
            if let canvas = rule.canvas {
                for instruction in canvas.instructions {
                    types.insert(instruction.instructionType)
                }
            }
            
            // Check canvas.after
            if let canvasAfter = rule.canvasAfter {
                for instruction in canvasAfter.instructions {
                    types.insert(instruction.instructionType)
                }
            }
        }
        
        return types
    }
    
    /// Check if canvas instructions contain app bindings
    private func hasAppBindingsInCanvas(_ rule: KvRule) -> Bool {
        let canvasLayers = [rule.canvasBefore, rule.canvas, rule.canvasAfter].compactMap { $0 }
        
        for layer in canvasLayers {
            for instruction in layer.instructions {
                for property in instruction.properties {
                    if property.value.contains("app.") {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    // MARK: - Class Generation
    
    /// The class a rule defines and what it inherits from.
    ///
    /// A `<Name>:` rule styles a class that already exists in Python, so its
    /// bases come from that file; `<Name@Base>:` declares them inline. Falling
    /// back to `Widget` matches what Kivy's own Builder does.
    private func resolvedClass(for rule: KvRule) -> (name: String, bases: [String])? {
        switch rule.selector {
        case .dynamicClass(let name, let bases):
            if let pythonClass = pythonClasses.first(where: { $0.name == name }),
               !pythonClass.baseClasses.isEmpty {
                return (name, pythonClass.baseClasses)
            }
            return (name, bases.isEmpty ? ["Widget"] : bases)
        case .name(let name):
            if let pythonClass = pythonClasses.first(where: { $0.name == name }),
               !pythonClass.baseClasses.isEmpty {
                return (name, pythonClass.baseClasses)
            }
            return (name, ["Widget"])
        case .className, .multiple:
            return nil
        }
    }
    
    private func generateClassForRule(_ rule: KvRule) throws -> [Statement] {
        guard let resolved = resolvedClass(for: rule) else { return [] }
        let className = resolved.name
        let baseClasses = resolved.bases
        
        // Generate class body with properties and children
        nameCounter.reset()
        ruleContext.baseClasses = baseClasses
        ruleContext.selfProperties = pythonClasses.first(where: { $0.name == className })?.kivyProperties ?? []
        // Properties this rule declares are emitted as ObjectProperty below,
        // so they are bindable too.
        ruleContext.selfProperties.formUnion(getCustomProperties(for: rule, baseClasses: baseClasses))
        var body: [Statement] = []
        
        // Add initial blank line at the start of class body
        body.append(.blank(1))
        
        // Declare custom properties that need binding
        let customProps = getCustomProperties(for: rule, baseClasses: baseClasses)
        for propName in customProps.sorted() {
            // property_name = ObjectProperty(None)
            let propDecl = Assign(
                targets: [.name(makeName(propName))],
                value: .call(
                    Call(
                        fun: .name(makeName("ObjectProperty")),
                        args: [.constant(makeConstant(.none))],
                        keywords: [],
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                ),
                typeComment: nil,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
            body.append(.assign(propDecl))
        }
        
        // Add __init__ method if there are properties, children, or canvas
        let hasCanvas = rule.canvasBefore != nil || rule.canvas != nil || rule.canvasAfter != nil
        let hasInit = !rule.properties.isEmpty || !rule.children.isEmpty || hasCanvas
        if hasInit {
            body.append(try generateInitMethod(rule, baseClasses: baseClasses, className: className))
        } else if body.isEmpty {
            // Empty class needs pass statement
            body.append(.pass(Pass(lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
        }
        
        // Add __del__ method if we have __init__ (which always initializes self._bindings)
        if hasInit {
            body.append(generateDelMethod())
        }
        
        // Add event handler methods
        for handler in rule.handlers {
            if let handlerMethod = try generateEventHandlerMethod(handler) {
                body.append(handlerMethod)
            }
        }
        
        // Add any additional methods from Python code (as AST nodes)
        //
        // Methods generated above win over same-named ones read back from the
        // existing Python file, so regenerating over previously generated
        // output carries over hand written methods without duplicating
        // `__del__` or the event handlers.
        if let pythonClass = pythonClasses.first(where: { $0.name == className }) {
            var generatedMethodNames = Swift.Set<String>()
            for statement in body {
                if case .functionDef(let funcDef) = statement {
                    generatedMethodNames.insert(funcDef.name)
                }
            }
            for method in pythonClass.methods {
                if case .functionDef(let funcDef) = method,
                   generatedMethodNames.contains(funcDef.name) {
                    continue
                }
                // Directly append the method AST nodes from the parsed Python code
                body.append(method)
            }
        }
        
        let bases: [PySwiftAST.Expression] = baseClasses.map { name in
            .name(makeName(name))
        }
        
        let classStmt = ClassDef(
            name: className,
            bases: bases,
            keywords: [],
            body: body,
            decoratorList: [],
            typeParams: [],
            lineno: 1,
            colOffset: 0,
            endLineno: nil,
            endColOffset: nil
        )
        
        return [.classDef(classStmt)]
    }
    
    private func getCustomProperties(for rule: KvRule, baseClasses: [String]) -> Swift.Set<String> {
        var customProps = Swift.Set<String>()
        
        for property in rule.properties {
            // Check if this property needs binding
            if needsBinding(property) {
                // Check if this property exists in any of the base classes
                let existsInBase = baseClasses.contains { baseClass in
                    KivyWidgetRegistry.getPropertyType(property.name, on: baseClass) != nil
                }
                
                // If it doesn't exist in base classes, it's a custom property
                if !existsInBase {
                    customProps.insert(property.name)
                }
            }
        }
        
        return customProps
    }
    
    /// Recursively check if any child widgets use app bindings
    private func hasAppBindingsInChildren(_ children: [KvWidget]) -> Bool {
        for child in children {
            // Check child's properties
            for property in child.properties {
                if property.value.contains("app.") {
                    return true
                }
            }
            // Check child's handlers
            for handler in child.handlers {
                if handler.value.contains("app.") {
                    return true
                }
            }
            // Recursively check nested children
            if hasAppBindingsInChildren(child.children) {
                return true
            }
        }
        return false
    }
    
    private func generateInitMethod(_ rule: KvRule, baseClasses: [String], className: String) throws -> Statement {
        var body: [Statement] = []
        var bindings: [BindingInfo] = []  // Track bindings for __del__
        var callbackCounter = 0
        
        // Call super().__init__(**kwargs)
        let superCall = PySwiftAST.Expression.call(
            Call(
                fun: .attribute(
                    Attribute(
                        value: .call(Call(
                            fun: .name(makeName("super")),
                            args: [],
                            keywords: [],
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )),
                        attr: "__init__",
                        ctx: .load,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                ),
                args: [],
                keywords: [Keyword(arg: nil, value: .name(makeName("kwargs")))],
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
        )
        body.append(.expr(Expr(value: superCall, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
        
        // Initialize bindings list to track for cleanup
        let initBindings = Assign(
            targets: [.attribute(
                Attribute(
                    value: .name(makeName("self")),
                    attr: "_bindings",
                    ctx: .store,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )],
            value: .list(List(elts: [], ctx: .load, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)),
            typeComment: nil,
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        body.append(.assign(initBindings))
        
        // Get app instance if needed for bindings (check properties, handlers, children, and canvas)
        let hasAppBindings = rule.properties.contains { property in
            property.value.contains("app.")
        } || rule.handlers.contains { handler in
            handler.value.contains("app.")
        } || hasAppBindingsInChildren(rule.children) || hasAppBindingsInCanvas(rule)
        
        if hasAppBindings {
            // app = App.get_running_app()
            let getAppCall = Assign(
                targets: [.name(makeName("app"))],
                value: .call(
                    Call(
                        fun: .attribute(
                            Attribute(
                                value: .name(makeName("App")),
                                attr: "get_running_app",
                                ctx: .load,
                                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                            )
                        ),
                        args: [],
                        keywords: [],
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                ),
                typeComment: nil,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
            body.append(.assign(getAppCall))
        }
        
        // Set properties (self.property = value)
        // Event handlers are in rule.handlers, not rule.properties
        for property in rule.properties {
            if needsBinding(property) {
                // Generate binding with initial value and bind call
                body.append(try generatePropertyBinding(property))
            } else {
                // Simple assignment
                let widgetName = baseClasses.first ?? "Widget"
                let assignment = Assign(
                    targets: [.attribute(
                        Attribute(
                            value: .name(makeName("self")),
                            attr: property.name,
                            ctx: .store,
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )
                    )],
                    value: try propertyValueToExpression(property, widgetName: widgetName),
                    typeComment: nil,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
                body.append(.assign(assignment))
            }
        }
        
        // Add bind() calls for reactive properties after all initialization
        for property in rule.properties {
            if needsBinding(property), let bindCall = generateBindingCall(property) {
                body.append(bindCall)
            }
        }
        
        // Add event handler bindings (on_press, on_release, etc.)
        for handler in rule.handlers {
            if let bindCall = generateEventHandlerBinding(handler) {
                body.append(bindCall)
            }
        }
        
        // Add children with proper nesting and id handling
        for child in rule.children {
            let (childStmts, childBindings) = try createAndAddChildWidget(child, parentName: "self", callbackCounter: &callbackCounter)
            body.append(contentsOf: childStmts)
            bindings.append(contentsOf: childBindings)
        }
        
        // Add canvas instructions if present
        if let canvasBefore = rule.canvasBefore, !canvasBefore.instructions.isEmpty {
            let (canvasStmts, canvasBindings) = try generateCanvasInstructions(canvasBefore.instructions, layer: "before", callbackCounter: &callbackCounter)
            body.append(contentsOf: canvasStmts)
            bindings.append(contentsOf: canvasBindings)
        }
        
        if let canvas = rule.canvas, !canvas.instructions.isEmpty {
            let (canvasStmts, canvasBindings) = try generateCanvasInstructions(canvas.instructions, layer: nil, callbackCounter: &callbackCounter)
            body.append(contentsOf: canvasStmts)
            bindings.append(contentsOf: canvasBindings)
        }
        
        if let canvasAfter = rule.canvasAfter, !canvasAfter.instructions.isEmpty {
            let (canvasStmts, canvasBindings) = try generateCanvasInstructions(canvasAfter.instructions, layer: "after", callbackCounter: &callbackCounter)
            body.append(contentsOf: canvasStmts)
            bindings.append(contentsOf: canvasBindings)
        }
        
        // Track all bindings in self._bindings for cleanup in __del__
        for binding in bindings {
            // self._bindings.append((obj, 'prop', callback))
            let tupleExpr = PySwiftAST.Expression.tuple(
                Tuple(
                    elts: [
                        .name(makeName(binding.sourceObj)),
                        .constant(makeConstant(.string(binding.property))),
                        .name(makeName(binding.callbackVar))
                    ],
                    ctx: .load,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )
            
            let appendCall = PySwiftAST.Expression.call(
                Call(
                    fun: .attribute(
                        Attribute(
                            value: .attribute(
                                Attribute(
                                    value: .name(makeName("self")),
                                    attr: "_bindings",
                                    ctx: .load,
                                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                                )
                            ),
                            attr: "append",
                            ctx: .load,
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )
                    ),
                    args: [tupleExpr],
                    keywords: [],
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )
            body.append(.expr(Expr(value: appendCall, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
        }
        
        let initFunc = FunctionDef(
            name: "__init__",
            args: Arguments(
                posonlyArgs: [],
                args: [Arg(arg: "self", annotation: nil, typeComment: nil)],
                vararg: nil,
                kwonlyArgs: [],
                kwDefaults: [],
                kwarg: Arg(arg: "kwargs", annotation: nil, typeComment: nil),
                defaults: []
            ),
            body: body,
            decoratorList: [],
            returns: nil,
            typeComment: nil,
            typeParams: [],
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        
        return .functionDef(initFunc)
    }
    
    private func generateDelMethod() -> Statement {
        // Generate __del__ method to unbind all tracked bindings
        var body: [Statement] = []
        
        // for obj, prop, callback in self._bindings:
        //     try:
        //         obj.unbind(**{prop: callback})
        //     except:
        //         pass
        
        let forLoop = For(
            target: .tuple(Tuple(
                elts: [
                    .name(makeName("obj")),
                    .name(makeName("prop")),
                    .name(makeName("callback"))
                ],
                ctx: .store,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )),
            iter: .attribute(
                Attribute(
                    value: .name(makeName("self")),
                    attr: "_bindings",
                    ctx: .load,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            ),
            body: [
                .tryStmt(Try(
                    body: [
                        .expr(Expr(
                            value: .call(
                                Call(
                                    fun: .attribute(
                                        Attribute(
                                            value: .name(makeName("obj")),
                                            attr: "unbind",
                                            ctx: .load,
                                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                                        )
                                    ),
                                    args: [],
                                    keywords: [Keyword(
                                        arg: nil,
                                        value: .dict(Dict(
                                            keys: [.name(makeName("prop"))],
                                            values: [.name(makeName("callback"))],
                                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                                        ))
                                    )],
                                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                                )
                            ),
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        ))
                    ],
                    handlers: [
                        ExceptHandler(
                            type: nil,
                            name: nil,
                            body: [.pass(Pass(lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))]
                        )
                    ],
                    orElse: [],
                    finalBody: [],
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                ))
            ],
            orElse: [],
            typeComment: nil,
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        
        body.append(.forStmt(forLoop))

        // try:
        //     self.clear_widgets()
        // except:
        //     pass
        //
        // Drops every child so the tree this class built does not outlive it.
        body.append(.tryStmt(Try(
            body: [
                .expr(Expr(
                    value: .call(
                        Call(
                            fun: .attribute(
                                Attribute(
                                    value: .name(makeName("self")),
                                    attr: "clear_widgets",
                                    ctx: .load,
                                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                                )
                            ),
                            args: [],
                            keywords: [],
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )
                    ),
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                ))
            ],
            handlers: [
                ExceptHandler(
                    type: nil,
                    name: nil,
                    body: [.pass(Pass(lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))]
                )
            ],
            orElse: [],
            finalBody: [],
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )))
        
        let delFunc = FunctionDef(
            name: "__del__",
            args: Arguments(
                posonlyArgs: [],
                args: [Arg(arg: "self", annotation: nil, typeComment: nil)],
                vararg: nil,
                kwonlyArgs: [],
                kwDefaults: [],
                kwarg: nil,
                defaults: []
            ),
            body: body,
            decoratorList: [],
            returns: nil,
            typeComment: nil,
            typeParams: [],
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        
        return .functionDef(delFunc)
    }
    
    private func propertyValueToExpression(_ property: KvProperty, widgetName: String = "Widget") throws -> PySwiftAST.Expression {
        // Use the raw value string which has the actual source representation
        var valueStr = property.value.trimmingCharacters(in: .whitespaces)
        
        // Check if this is a binding expression (contains app., self., root., etc.)
        if valueStr.contains("app.") || valueStr.contains("self.") || valueStr.contains("root.") {
            // This needs to be a binding expression, return as-is for now
            // Will be handled by generatePropertyBinding
            return .constant(makeConstant(.string(valueStr)))
        }
        
        // Strip quotes from string values if present
        if (valueStr.hasPrefix("\"") && valueStr.hasSuffix("\"")) || 
           (valueStr.hasPrefix("'") && valueStr.hasSuffix("'")) {
            valueStr = String(valueStr.dropFirst().dropLast())
        }
        
        // Check what type this property should be based on the widget registry
        let propertyType = KivyWidgetRegistry.getPropertyType(property.name, on: widgetName)
        
        // Handle list/tuple properties (ReferenceListProperty, ListProperty, VariableListProperty)
        if propertyType == .referenceListProperty || 
           propertyType == .listProperty || 
           propertyType == .variableListProperty {
            // Parse as tuple/list: "None , None" -> (None, None) or "0.5, 0.5" -> (0.5, 0.5)
            if valueStr.contains(",") {
                let parts = valueStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let exprs = parts.map { part -> PySwiftAST.Expression in
                    if part == "None" {
                        return .constant(makeConstant(.none))
                    } else if let num = Double(part) {
                        return .constant(makeConstant(.float(num)))
                    } else if part == "True" {
                        return .constant(makeConstant(.bool(true)))
                    } else if part == "False" {
                        return .constant(makeConstant(.bool(false)))
                    } else {
                        return .constant(makeConstant(.string(part)))
                    }
                }
                return .tuple(Tuple(elts: exprs, ctx: .load, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
            }
        }
        
        // Try to parse as number
        if let num = Double(valueStr) {
            return .constant(makeConstant(.float(num)))
        }
        
        // Check for booleans
        if valueStr == "True" {
            return .constant(makeConstant(.bool(true)))
        } else if valueStr == "False" {
            return .constant(makeConstant(.bool(false)))
        } else if valueStr == "None" {
            return .constant(makeConstant(.none))
        }
        
        // Check for tuples (contains comma but not inside quotes)
        if valueStr.contains(",") && !valueStr.hasPrefix("[") {
            // Parse as tuple: "0.5, 0.5" -> (0.5, 0.5)
            let parts = valueStr.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let exprs = parts.compactMap { part -> PySwiftAST.Expression? in
                if part == "None" {
                    return .constant(makeConstant(.none))
                } else if let num = Double(part) {
                    return .constant(makeConstant(.float(num)))
                } else if part == "True" {
                    return .constant(makeConstant(.bool(true)))
                } else if part == "False" {
                    return .constant(makeConstant(.bool(false)))
                }
                return nil
            }
            if !exprs.isEmpty {
                return .tuple(Tuple(elts: exprs, ctx: .load, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
            }
        }
        
        // Otherwise treat as string
        return .constant(makeConstant(.string(valueStr)))
    }
    
    private func needsBinding(_ property: KvProperty) -> Bool {
        // Use the pre-computed watchedKeys from the parser instead of manual string parsing
        if let watchedKeys = property.watchedKeys, !watchedKeys.isEmpty {
            return true
        }
        return false
    }
    
    /// Parse property value as Python expression and extract watched keys using visitor
    private func parsePropertyExpression(_ property: KvProperty) -> (PySwiftAST.Expression?, [[String]]) {
        let valueStr = property.value.trimmingCharacters(in: .whitespaces)
        
        // Try to parse as Python expression by wrapping it in an assignment
        do {
            let code = "_tmp = \(valueStr)"
            let module = try parsePython(code)
            
            // Extract the expression from the assignment
            if case .module(let statements) = module,
               let firstStmt = statements.first,
               case .assign(let assign) = firstStmt {
                let expr = replaceRootWithSelf(assign.value)
                
                // Use visitor to extract watched keys
                let visitor = PropertyExpressionVisitor()
                visitor.visitExpression(expr)
                return (expr, bindableKeys(visitor.watchedKeys))
            }
        } catch {
            // If parsing fails, fall back to the pre-computed watchedKeys
            return (nil, bindableKeys(property.watchedKeys ?? []))
        }
        
        return (nil, bindableKeys(property.watchedKeys ?? []))
    }
    
    /// Watched keys with `root` renamed to `self`, dropping the ones that are
    /// not Kivy properties.
    ///
    /// `self.x` only binds when `x` is a property -- declared in the KV rule,
    /// inherited from a base widget, or assigned in the existing .py as
    /// `x = StringProperty(...)`. A plain Python attribute raises in
    /// `bind()`, so those get the initial assignment and nothing more.
    private func bindableKeys(_ keys: [[String]]) -> [[String]] {
        var seen = Swift.Set<[String]>()
        return keys.compactMap { key -> [String]? in
            guard key.count == 2 else { return key }
            let object = key[0] == "root" ? "self" : key[0]
            if object == "self", !isBindableSelfProperty(key[1]) { return nil }
            // One expression can name the same property more than once; it
            // still only needs binding once.
            return seen.insert([object, key[1]]).inserted ? [object, key[1]] : nil
        }
    }
    
    private func isBindableSelfProperty(_ name: String) -> Bool {
        if ruleContext.selfProperties.contains(name) { return true }
        return ruleContext.baseClasses.contains { base in
            KivyWidgetRegistry.getPropertyType(name, on: base) != nil
        }
    }
    
    private func isEventHandler(_ property: KvProperty) -> Bool {
        // Event handlers in Kivy start with "on_"
        return property.name.hasPrefix("on_")
    }
    
    private func generatePropertyBinding(_ property: KvProperty, targetName: String = "self") throws -> Statement {
        let valueStr = property.value.trimmingCharacters(in: .whitespaces)
        
        // Parse the expression and extract watched keys using visitor
        let (parsedExpr, watchedKeys) = parsePropertyExpression(property)
        
        // For simple property bindings like "app.title" use direct assignment
        // For complex expressions like f-strings or str() use the parsed expression
        let isSimpleBinding = watchedKeys.count == 1 && 
                             watchedKeys[0].count == 2 && 
                             !valueStr.contains("(") && 
                             !valueStr.hasPrefix("f\"") && 
                             !valueStr.hasPrefix("f'")
        
        if isSimpleBinding, let firstKey = watchedKeys.first {
            // Simple case: app.some_prop -> self.property = app.some_prop
            let sourceObj = firstKey[0]
            let sourceProp = firstKey[1]
            
            let initialAssign = Assign(
                targets: [.attribute(
                    Attribute(
                        value: .name(makeName(targetName)),
                        attr: property.name,
                        ctx: .store,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                )],
                value: .attribute(
                    Attribute(
                        value: .name(makeName(sourceObj)),
                        attr: sourceProp,
                        ctx: .load,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                ),
                typeComment: nil,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
            
            return .assign(initialAssign)
        } else if let expr = parsedExpr {
            // Complex expression (f-string, str(), etc.): use the parsed AST expression
            let initialAssign = Assign(
                targets: [.attribute(
                    Attribute(
                        value: .name(makeName(targetName)),
                        attr: property.name,
                        ctx: .store,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                )],
                value: expr,
                typeComment: nil,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
            
            return .assign(initialAssign)
        } else {
            // Fallback to string constant if parsing failed
            let initialAssign = Assign(
                targets: [.attribute(
                    Attribute(
                        value: .name(makeName(targetName)),
                        attr: property.name,
                        ctx: .store,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                )],
                value: .constant(makeConstant(.string(valueStr))),
                typeComment: nil,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
            
            return .assign(initialAssign)
        }
    }
    
    private func generateBindingCall(_ property: KvProperty, targetName: String = "self") -> Statement? {
        let watchedKeys = bindableKeys(property.watchedKeys ?? [])
        guard !watchedKeys.isEmpty else {
            return nil
        }
        
        // For simple bindings (single watched key, direct property access)
        if watchedKeys.count == 1, watchedKeys[0].count == 2 {
            let sourceObj = watchedKeys[0][0]
            let sourceProp = watchedKeys[0][1]
            
            // Generate: app.bind(prop=self.setter('property'))
            let bindCall = PySwiftAST.Expression.call(
                Call(
                    fun: .attribute(
                        Attribute(
                            value: .name(makeName(sourceObj)),
                            attr: "bind",
                            ctx: .load,
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )
                    ),
                    args: [],
                    keywords: [Keyword(
                        arg: sourceProp,
                        value: .call(
                            Call(
                                fun: .attribute(
                                    Attribute(
                                        value: .name(makeName(targetName)),
                                        attr: "setter",
                                        ctx: .load,
                                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                                    )
                                ),
                                args: [.constant(makeConstant(.string(property.name)))],
                                keywords: [],
                                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                            )
                        )
                    )],
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )
            
            return .expr(Expr(value: bindCall, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
        }
        
        // For complex expressions (f-strings, multiple watched keys)
        // We need to bind to ALL watched properties and re-evaluate the expression
        // app.bind(title=lambda *args: setattr(self, 'text', f"{app.title}-{app.version}"))
        // app.bind(version=lambda *args: setattr(self, 'text', f"{app.title}-{app.version}"))
        
        // TODO: Generate bindings for each watched key that re-evaluates the full expression
        // For now, just bind to the first one
        if let firstKey = watchedKeys.first, firstKey.count == 2 {
            let sourceObj = firstKey[0]
            let sourceProp = firstKey[1]
            
            let bindCall = PySwiftAST.Expression.call(
                Call(
                    fun: .attribute(
                        Attribute(
                            value: .name(makeName(sourceObj)),
                            attr: "bind",
                            ctx: .load,
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )
                    ),
                    args: [],
                    keywords: [Keyword(
                        arg: sourceProp,
                        value: .call(
                            Call(
                                fun: .attribute(
                                    Attribute(
                                        value: .name(makeName(targetName)),
                                        attr: "setter",
                                        ctx: .load,
                                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                                    )
                                ),
                                args: [.constant(makeConstant(.string(property.name)))],
                                keywords: [],
                                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                            )
                        )
                    )],
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )
            
            return .expr(Expr(value: bindCall, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
        }
        
        return nil
    }
    
    /// Generate property binding for child widgets
    /// Similar to generateBindingCall but for child widget properties
    /// Returns tuple of (statements, bindings) - statements to execute and bindings to track
    private func generateChildPropertyBinding(_ property: KvProperty, widgetVarName: String, callbackCounter: inout Int) -> ([Statement], [BindingInfo]) {
        // Parse the expression to get the AST; watched keys come back with
        // `root` renamed and unbindable attributes dropped.
        let (parsedExpr, watchedKeys) = parsePropertyExpression(property)
        guard !watchedKeys.isEmpty else {
            return ([], [])
        }
        
        // Check if this is a truly simple binding: single watched key AND direct attribute access (not wrapped in function calls)
        let isSimpleBinding: Bool
        if watchedKeys.count == 1, watchedKeys[0].count == 2, let expr = parsedExpr {
            // Only consider it simple if the parsed expression is a direct Attribute access (app.title)
            // Not simple if it's wrapped in a Call (str(app.title)), JoinedStr (f-string), etc.
            switch expr {
            case .attribute:
                isSimpleBinding = true
            default:
                isSimpleBinding = false
            }
        } else {
            isSimpleBinding = false
        }
        
        // For simple bindings (single watched key, direct property access with no transformations)
        if isSimpleBinding, let expr = parsedExpr, case .attribute = expr {
            let sourceObj = watchedKeys[0][0]
            let sourceProp = watchedKeys[0][1]
            
            // Generate: app.bind(prop=widget.setter('property'))
            let bindCall = PySwiftAST.Expression.call(
                Call(
                    fun: .attribute(
                        Attribute(
                            value: .name(makeName(sourceObj)),
                            attr: "bind",
                            ctx: .load,
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )
                    ),
                    args: [],
                    keywords: [Keyword(
                        arg: sourceProp,
                        value: .call(
                            Call(
                                fun: .attribute(
                                    Attribute(
                                        value: .name(makeName(widgetVarName)),
                                        attr: "setter",
                                        ctx: .load,
                                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                                    )
                                ),
                                args: [.constant(makeConstant(.string(property.name)))],
                                keywords: [],
                                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                            )
                        )
                    )],
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )
            
            // For setter(), we don't need to track the callback since it's managed by Kivy
            return ([.expr(Expr(value: bindCall, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))], [])
        }
        
        // For complex expressions (f-strings, multiple watched keys)
        // Generate bind() for each watched key with a lambda that re-evaluates the full expression
        
        if let expr = parsedExpr, !watchedKeys.isEmpty {
            var bindStatements: [Statement] = []
            var bindingInfos: [BindingInfo] = []
            
            // Generate bind() for EACH watched key
            for watchedKey in watchedKeys {
                guard watchedKey.count == 2 else { continue }
                let sourceObj = watchedKey[0]
                let sourceProp = watchedKey[1]
                
                // Generate parameter name: app.title -> app_title
                let paramName = "\(sourceObj)_\(sourceProp)"
                
                // Generate callback variable name
                let callbackVar = "_callback_\(callbackCounter)"
                callbackCounter += 1
                
                // Replace the watched attribute (app.title) with the parameter name in the expression
                let modifiedExpr = replaceAttributeWithNameRef(expr, object: sourceObj, attr: sourceProp, replacement: paramName)
                
                // Create lambda: lambda instance, param_name: setattr(widget, 'property', expression)
                let lambdaBody = PySwiftAST.Expression.call(
                    Call(
                        fun: .name(makeName("setattr")),
                        args: [
                            .name(makeName(widgetVarName)),
                            .constant(makeConstant(.string(property.name))),
                            modifiedExpr
                        ],
                        keywords: [],
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                )
                
                let lambda = Lambda(
                    args: Arguments(
                        posonlyArgs: [],
                        args: [
                            Arg(arg: "instance", annotation: nil, typeComment: nil),
                            Arg(arg: paramName, annotation: nil, typeComment: nil)
                        ],
                        vararg: nil,
                        kwonlyArgs: [],
                        kwDefaults: [],
                        kwarg: nil,
                        defaults: []
                    ),
                    body: lambdaBody,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
                
                // Assign lambda to variable: _callback_0 = lambda ...
                let callbackAssign = Assign(
                    targets: [.name(makeName(callbackVar))],
                    value: .lambda(lambda),
                    typeComment: nil,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
                bindStatements.append(.assign(callbackAssign))
                
                // Generate bind call: app.bind(prop=_callback_0)
                let bindCall = PySwiftAST.Expression.call(
                    Call(
                        fun: .attribute(
                            Attribute(
                                value: .name(makeName(sourceObj)),
                                attr: "bind",
                                ctx: .load,
                                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                            )
                        ),
                        args: [],
                        keywords: [Keyword(arg: sourceProp, value: .name(makeName(callbackVar)))],
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                )
                
                bindStatements.append(.expr(Expr(value: bindCall, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
                
                // Track binding for cleanup
                bindingInfos.append(BindingInfo(sourceObj: sourceObj, property: sourceProp, callbackVar: callbackVar))
            }
            
            return (bindStatements, bindingInfos)
        }
        
        return ([], [])
    }
    
    /// Generate binding for event handlers (on_press, on_release, etc.)
    /// Returns: self.bind(on_press=self._on_press_handler)
    private func generateEventHandlerBinding(_ property: KvProperty) -> Statement? {
        guard isEventHandler(property) else { return nil }
        
        let handlerName = "_\(property.name)_handler"
        
        // self.bind(on_event=self._on_event_handler)
        let bindCall = Call(
            fun: .attribute(
                Attribute(
                    value: .name(makeName("self")),
                    attr: "bind",
                    ctx: .load,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            ),
            args: [],
            keywords: [Keyword(
                arg: property.name,
                value: .attribute(
                    Attribute(
                        value: .name(makeName("self")),
                        attr: handlerName,
                        ctx: .load,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                )
            )],
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        
        return .expr(Expr(value: .call(bindCall), lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    /// Generate an event handler method
    /// Returns: def _on_event_handler(self, instance): <handler code>
    private func generateEventHandlerMethod(_ property: KvProperty) throws -> Statement? {
        guard isEventHandler(property) else { return nil }
        
        let handlerName = "_\(property.name)_handler"
        
        // Parse the handler code
        let handlerCode = property.value.trimmingCharacters(in: .whitespaces)
        
        // Try to parse as Python expression/statement
        var body: [Statement] = []
        
        // For now, handle simple cases:
        // 1. Function calls like "app.handle_click()" or "print('hello')"
        // 2. Simple expressions
        
        if handlerCode.contains("(") && handlerCode.contains(")") {
            // Looks like a function call
            do {
                let expr = try parsePythonExpression(handlerCode)
                body.append(.expr(Expr(value: expr, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
            } catch {
                // If parsing fails, add a pass statement
                body.append(.pass(Pass(lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
            }
        } else {
            // Simple expression or pass
            body.append(.pass(Pass(lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
        }
        
        let functionDef = FunctionDef(
            name: handlerName,
            args: Arguments(
                posonlyArgs: [],
                args: [
                    Arg(arg: "self", annotation: nil, typeComment: nil),
                    Arg(arg: "instance", annotation: nil, typeComment: nil)
                ],
                vararg: nil,
                kwonlyArgs: [],
                kwDefaults: [],
                kwarg: nil,
                defaults: []
            ),
            body: body,
            decoratorList: [],
            returns: nil,
            typeComment: nil,
            typeParams: [],
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        
        return .functionDef(functionDef)
    }
    
    /// Parse a Python expression from string
    private func parsePythonExpression(_ code: String) throws -> PySwiftAST.Expression {
        // Handle common patterns
        
        // print("text")
        if code.hasPrefix("print(") && code.hasSuffix(")") {
            let content = String(code.dropFirst(6).dropLast(1))
            let arg: PySwiftAST.Expression
            
            // Check if it's a string literal
            if content.hasPrefix("\"") && content.hasSuffix("\"") {
                let stringContent = String(content.dropFirst(1).dropLast(1))
                arg = .constant(makeConstant(.string(stringContent)))
            } else if content.hasPrefix("'") && content.hasSuffix("'") {
                let stringContent = String(content.dropFirst(1).dropLast(1))
                arg = .constant(makeConstant(.string(stringContent)))
            } else {
                // It's an expression
                arg = try parsePythonExpression(content)
            }
            
            return .call(
                Call(
                    fun: .name(makeName("print")),
                    args: [arg],
                    keywords: [],
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )
        }
        
        // app.method(), self.method(), or root.method()
        if code.contains(".") && code.contains("(") {
            // Extract method call: "root.save_profile()" -> "root.save_profile" + "()"
            if let openParenIndex = code.firstIndex(of: "(") {
                let callPart = String(code[..<openParenIndex])
                let dotParts = callPart.components(separatedBy: ".")
                
                if dotParts.count == 2 {
                    var obj = dotParts[0].trimmingCharacters(in: .whitespaces)
                    let method = dotParts[1].trimmingCharacters(in: .whitespaces)
                    
                    // In Kv language, 'root' refers to the root widget of the current rule
                    // In generated Python code, that's 'self' (the class instance)
                    if obj == "root" {
                        obj = "self"
                    }
                    
                    return .call(
                        Call(
                            fun: .attribute(
                                Attribute(
                                    value: .name(makeName(obj)),
                                    attr: method,
                                    ctx: .load,
                                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                                )
                            ),
                            args: [],
                            keywords: [],
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )
                    )
                }
            }
        }
        
        // Fallback: return a name
        return .name(makeName(code))
    }
    
    /// Generate binding for event handlers on child widgets
    /// Returns: ([statements], [bindings]) - statements to execute and bindings to track for cleanup
    private func generateChildWidgetEventBinding(_ handler: KvProperty, widgetVarName: String, callbackCounter: inout Int) throws -> ([Statement], [BindingInfo]) {
        let handlerCode = handler.value.trimmingCharacters(in: .whitespaces)
        
        // Parse the handler expression
        let handlerExpr = try parsePythonExpression(handlerCode)
        
        // Create lambda: lambda instance: handler_expression
        let lambdaFunc = Lambda(
            args: Arguments(
                posonlyArgs: [],
                args: [Arg(arg: "instance", annotation: nil, typeComment: nil)],
                vararg: nil,
                kwonlyArgs: [],
                kwDefaults: [],
                kwarg: nil,
                defaults: []
            ),
            body: handlerExpr,
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        
        // Generate callback variable name
        let callbackVar = "_callback_\(callbackCounter)"
        callbackCounter += 1
        
        var statements: [Statement] = []
        
        // Step 1: Assign lambda to callback variable: _callback_N = lambda instance: ...
        let assignCallback = Assign(
            targets: [.name(Name(id: callbackVar, ctx: .store, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))],
            value: .lambda(lambdaFunc),
            typeComment: nil,
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        statements.append(.assign(assignCallback))
        
        // Step 2: Call widget.bind(on_event=_callback_N)
        let bindCall = Call(
            fun: .attribute(
                Attribute(
                    value: .name(makeName(widgetVarName)),
                    attr: "bind",
                    ctx: .load,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            ),
            args: [],
            keywords: [Keyword(
                arg: handler.name,
                value: .name(makeName(callbackVar))
            )],
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        statements.append(.expr(Expr(value: .call(bindCall), lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
        
        // Create binding info for cleanup
        let bindingInfo = BindingInfo(
            sourceObj: widgetVarName,
            property: handler.name,
            callbackVar: callbackVar
        )
        
        return (statements, [bindingInfo])
    }
    
    /// Create and add a child widget with proper handling of nested children and ids
    /// Returns tuple of (statements, bindings) - statements to execute and bindings to track for cleanup
    private func createAndAddChildWidget(_ widget: KvWidget, parentName: String, widgetVarName: String? = nil, callbackCounter: inout Int) throws -> ([Statement], [BindingInfo]) {
        var statements: [Statement] = []
        var bindings: [BindingInfo] = []
        
        // Get the widget id directly from the widget struct (not from properties)
        let widgetId = widget.id
        
        // Generate a variable name for this widget (use id if available, otherwise generate one)
        // Use widget type as prefix (e.g., "label_ABC123" for Label, "box_ABC123" for BoxLayout)
        let defaultVarName: String
        if let widgetId = widgetId {
            defaultVarName = widgetId
        } else {
            let widgetTypePrefix = widget.name.lowercased().replacingOccurrences(of: "layout", with: "")
            let shortPrefix = widgetTypePrefix.prefix(10) // Limit prefix length
            defaultVarName = "\(shortPrefix)_\(nameCounter.take())"
        }
        let varName = widgetVarName ?? defaultVarName
        
        // Separate properties that need binding from static ones
        var staticProperties: [KvProperty] = []
        var bindingProperties: [KvProperty] = []
        
        for property in widget.properties {
            if needsBinding(property) {
                bindingProperties.append(property)
            } else {
                staticProperties.append(property)
            }
        }
        
        // Create widget instance with only static properties
        var keywords: [Keyword] = []
        for property in staticProperties {
            let keyword = Keyword(
                arg: property.name,
                value: try propertyValueToExpression(property, widgetName: widget.name)
            )
            keywords.append(keyword)
        }
        
        let widgetCreation = Assign(
            targets: [.name(makeName(varName))],
            value: .call(
                Call(
                    fun: .name(makeName(widget.name)),
                    args: [],
                    keywords: keywords,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            ),
            typeComment: nil,
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        statements.append(.assign(widgetCreation))
        
        // Set binding properties and create bind() calls
        for property in bindingProperties {
            // Parse the expression to get the AST
            let (parsedExpr, _) = parsePropertyExpression(property)
            
            // Use parsed expression if available, otherwise fallback to simple conversion
            let valueExpr: PySwiftAST.Expression
            if let expr = parsedExpr {
                valueExpr = expr
            } else {
                valueExpr = try propertyValueToExpression(property, widgetName: widget.name)
            }
            
            // Set initial value: widget.property = expression
            let setProperty = Assign(
                targets: [.attribute(
                    Attribute(
                        value: .name(makeName(varName)),
                        attr: property.name,
                        ctx: .store,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                )],
                value: valueExpr,
                typeComment: nil,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
            statements.append(.assign(setProperty))
            
            // Create bind() calls for this property (one for each watched key)
            let (bindingStmts, bindingInfos) = generateChildPropertyBinding(property, widgetVarName: varName, callbackCounter: &callbackCounter)
            statements.append(contentsOf: bindingStmts)
            bindings.append(contentsOf: bindingInfos)
        }
        
        // If widget has an id, store it in self.ids
        if let widgetId = widgetId {
            let storeInIds = Assign(
                targets: [.attribute(
                    Attribute(
                        value: .attribute(
                            Attribute(
                                value: .name(makeName("self")),
                                attr: "ids",
                                ctx: .load,
                                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                            )
                        ),
                        attr: widgetId,
                        ctx: .store,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                )],
                value: .name(makeName(varName)),
                typeComment: nil,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
            statements.append(.assign(storeInIds))
        }
        
        // Add children to this widget recursively
        for child in widget.children {
            let (childStmts, childBindings) = try createAndAddChildWidget(child, parentName: varName, callbackCounter: &callbackCounter)
            statements.append(contentsOf: childStmts)
            bindings.append(contentsOf: childBindings)
        }
        
        // Bind event handlers for this widget
        for handler in widget.handlers {
            // Generate inline handler binding and track it for cleanup
            let (bindStmts, bindInfos) = try generateChildWidgetEventBinding(handler, widgetVarName: varName, callbackCounter: &callbackCounter)
            statements.append(contentsOf: bindStmts)
            bindings.append(contentsOf: bindInfos)
        }
        
        // Add this widget to parent
        let addToParent = PySwiftAST.Expression.call(
            Call(
                fun: .attribute(
                    Attribute(
                        value: .name(makeName(parentName)),
                        attr: "add_widget",
                        ctx: .load,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                ),
                args: [.name(makeName(varName))],
                keywords: [],
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
        )
        statements.append(.expr(Expr(value: addToParent, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
        
        return (statements, bindings)
    }
    
    private func createChildWidget(_ widget: KvWidget) throws -> PySwiftAST.Expression {
        // Create widget instance: WidgetClass(**properties)
        var keywords: [Keyword] = []
        
        for property in widget.properties {
            let keyword = Keyword(
                arg: property.name,
                value: try propertyValueToExpression(property, widgetName: widget.name)
            )
            keywords.append(keyword)
        }
        
        return .call(
            Call(
                fun: .name(makeName(widget.name)),
                args: [],
                keywords: keywords,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
        )
    }
    
    // MARK: - Canvas Generation
    
    /// Generate canvas instructions for a given layer
    /// Returns tuple of (statements, bindings)
    private func generateCanvasInstructions(_ instructions: [KvCanvasInstruction], layer: String?, callbackCounter: inout Int) throws -> ([Statement], [BindingInfo]) {
        var statements: [Statement] = []
        var bindings: [BindingInfo] = []
        
        // Determine canvas attribute (self.canvas, self.canvas.before, or self.canvas.after)
        let canvasAttr: PySwiftAST.Expression
        if let layer = layer {
            canvasAttr = .attribute(
                Attribute(
                    value: .attribute(
                        Attribute(
                            value: .name(makeName("self")),
                            attr: "canvas",
                            ctx: .load,
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )
                    ),
                    attr: layer,
                    ctx: .load,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )
        } else {
            canvasAttr = .attribute(
                Attribute(
                    value: .name(makeName("self")),
                    attr: "canvas",
                    ctx: .load,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )
        }
        
        // Process each canvas instruction
        for instruction in instructions {
            let (instrStmts, instrBindings) = try generateSingleCanvasInstruction(instruction, canvasAttr: canvasAttr, callbackCounter: &callbackCounter)
            statements.append(contentsOf: instrStmts)
            bindings.append(contentsOf: instrBindings)
        }
        
        return (statements, bindings)
    }
    
    /// Generate a single canvas instruction
    private func generateSingleCanvasInstruction(_ instruction: KvCanvasInstruction, canvasAttr: PySwiftAST.Expression, callbackCounter: inout Int) throws -> ([Statement], [BindingInfo]) {
        var statements: [Statement] = []
        var bindings: [BindingInfo] = []
        
        // Check if instruction is context-only (no properties, like PushMatrix, PopMatrix)
        let isContextOnly = instruction.properties.isEmpty
        
        if isContextOnly {
            // Context instructions like PushMatrix, PopMatrix - just add them to canvas
            // with self.canvas:
            //     PushMatrix()
            let instrCall = PySwiftAST.Expression.call(
                Call(
                    fun: .name(makeName(instruction.instructionType)),
                    args: [],
                    keywords: [],
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )
            
            let addToCanvas = PySwiftAST.Expression.call(
                Call(
                    fun: .attribute(
                        Attribute(
                            value: canvasAttr,
                            attr: "add",
                            ctx: .load,
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )
                    ),
                    args: [instrCall],
                    keywords: [],
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )
            statements.append(.expr(Expr(value: addToCanvas, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
        } else {
            // Instructions with properties - check if any need binding
            let staticProps = instruction.properties.filter { !needsBinding($0) }
            let bindingProps = instruction.properties.filter { needsBinding($0) }
            
            if bindingProps.isEmpty {
                // All properties are static - create instruction directly
                var keywords: [Keyword] = []
                for property in staticProps {
                    let keyword = Keyword(
                        arg: property.name,
                        value: try canvasPropertyValueToExpression(property)
                    )
                    keywords.append(keyword)
                }
                
                let instrCall = PySwiftAST.Expression.call(
                    Call(
                        fun: .name(makeName(instruction.instructionType)),
                        args: [],
                        keywords: keywords,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                )
                
                let addToCanvas = PySwiftAST.Expression.call(
                    Call(
                        fun: .attribute(
                            Attribute(
                                value: canvasAttr,
                                attr: "add",
                                ctx: .load,
                                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                            )
                        ),
                        args: [instrCall],
                        keywords: [],
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                )
                statements.append(.expr(Expr(value: addToCanvas, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
            } else {
                // Some properties need binding - store instruction reference and create update method
                let instrAttrName = "_canvas_\(instruction.instructionType.lowercased())_\(nameCounter.take())"
                
                // Create instruction with static properties only
                var keywords: [Keyword] = []
                for property in staticProps {
                    let keyword = Keyword(
                        arg: property.name,
                        value: try canvasPropertyValueToExpression(property)
                    )
                    keywords.append(keyword)
                }
                
                // Assign to variable: self._canvas_rect_ABC123 = Rectangle(...)
                let instrCreation = Assign(
                    targets: [.attribute(
                        Attribute(
                            value: .name(makeName("self")),
                            attr: instrAttrName,
                            ctx: .store,
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )
                    )],
                    value: .call(
                        Call(
                            fun: .name(makeName(instruction.instructionType)),
                            args: [],
                            keywords: keywords,
                            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                        )
                    ),
                    typeComment: nil,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
                statements.append(.assign(instrCreation))
                
                // Add to canvas
                let addToCanvas = PySwiftAST.Expression.call(
                    Call(
                        fun: .attribute(
                            Attribute(
                                value: canvasAttr,
                                attr: "add",
                                ctx: .load,
                                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                            )
                        ),
                        args: [.attribute(
                            Attribute(
                                value: .name(makeName("self")),
                                attr: instrAttrName,
                                ctx: .load,
                                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                            )
                        )],
                        keywords: [],
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                )
                statements.append(.expr(Expr(value: addToCanvas, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
                
                // Set binding properties and create bind() calls
                for property in bindingProps {
                    // Parse the expression to get the AST
                    let (parsedExpr, _) = parsePropertyExpression(property)
                    
                    let valueExpr: PySwiftAST.Expression
                    if let expr = parsedExpr {
                        valueExpr = expr
                    } else {
                        valueExpr = try canvasPropertyValueToExpression(property)
                    }
                    
                    // Set initial value: self._canvas_rect.pos = self.pos
                    let setProperty = Assign(
                        targets: [.attribute(
                            Attribute(
                                value: .attribute(
                                    Attribute(
                                        value: .name(makeName("self")),
                                        attr: instrAttrName,
                                        ctx: .load,
                                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                                    )
                                ),
                                attr: property.name,
                                ctx: .store,
                                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                            )
                        )],
                        value: valueExpr,
                        typeComment: nil,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                    statements.append(.assign(setProperty))
                    
                    // Create bind() calls for this property (one for each watched key)
                    let (bindingStmts, bindingInfos) = generateCanvasPropertyBinding(property, instrVarName: "self.\(instrAttrName)", callbackCounter: &callbackCounter)
                    statements.append(contentsOf: bindingStmts)
                    bindings.append(contentsOf: bindingInfos)
                }
            }
        }
        
        return (statements, bindings)
    }
    
    /// Generate binding for a canvas instruction property (e.g., pos: self.pos)
    private func generateCanvasPropertyBinding(_ property: KvProperty, instrVarName: String, callbackCounter: inout Int) -> ([Statement], [BindingInfo]) {
        var statements: [Statement] = []
        var bindings: [BindingInfo] = []
        
        // Extract watched keys from the expression
        let visitor = PropertyExpressionVisitor()
        let (expr, _) = parsePropertyExpression(property)
        if let parsedExpr = expr {
            visitor.visitExpression(parsedExpr)
        }
        
        // Generate a bind() call for each watched key
        for watchedKey in visitor.watchedKeys {
            callbackCounter += 1
            let callbackVar = "_callback_\(callbackCounter)"
            
            // Determine source object (self or app)
            let sourceObj = watchedKey[0]  // e.g., "self" or "app"
            let watchedProp = watchedKey[1]   // e.g., "pos" or "title"
            
            // Parse the full property expression
            let (parsedExpr, _) = parsePropertyExpression(property)
            let valueExpr: PySwiftAST.Expression
            if let expr = parsedExpr {
                // Check if the expression is simply the watched attribute (e.g., self.pos)
                // In that case, we can just use 'value' directly for efficiency
                let isSimpleAttribute: Bool
                if case .attribute(let attr) = expr,
                   case .name(let nameNode) = attr.value,
                   nameNode.id == sourceObj && attr.attr == watchedProp {
                    isSimpleAttribute = true
                } else {
                    isSimpleAttribute = false
                }
                
                if isSimpleAttribute {
                    // For simple attribute access, use the new value directly
                    valueExpr = .name(makeName("value"))
                } else {
                    // For complex expressions, replace ALL self.* references with instance.*
                    valueExpr = replaceAllSelfWithInstance(expr)
                }
            } else {
                // Fallback - shouldn't happen if parsing worked
                valueExpr = .name(makeName("value"))
            }
            
            // Create lambda: lambda instance, value: setattr(instr, 'prop', expression)
            let lambdaBody: PySwiftAST.Expression = .call(
                Call(
                    fun: .name(makeName("setattr")),
                    args: [
                        // Parse the instruction variable name (e.g., "self._canvas_rect")
                        instrVarName.contains(".") ?
                            .attribute(
                                Attribute(
                                    value: .name(makeName(String(instrVarName.split(separator: ".")[0]))),
                                    attr: String(instrVarName.split(separator: ".")[1]),
                                    ctx: .load,
                                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                                )
                            ) : .name(makeName(instrVarName)),
                        .constant(makeConstant(.string(property.name))),
                        valueExpr
                    ],
                    keywords: [],
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )
            )
            
            let lambdaFunc = Lambda(
                args: Arguments(
                    posonlyArgs: [],
                    args: [
                        Arg(arg: "instance", annotation: nil, typeComment: nil),
                        Arg(arg: "value", annotation: nil, typeComment: nil)
                    ],
                    vararg: nil,
                    kwonlyArgs: [],
                    kwDefaults: [],
                    kwarg: nil,
                    defaults: []
                ),
                body: lambdaBody,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
            
            // Step 1: Assign lambda to callback variable
            let assignCallback = Assign(
                targets: [.name(Name(id: callbackVar, ctx: .store, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))],
                value: .lambda(lambdaFunc),
                typeComment: nil,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
            statements.append(.assign(assignCallback))
            
            // Step 2: Call source.bind(property=_callback_N)
            let bindCall = Call(
                fun: .attribute(
                    Attribute(
                        value: .name(makeName(sourceObj)),
                        attr: "bind",
                        ctx: .load,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )
                ),
                args: [],
                keywords: [Keyword(
                    arg: watchedProp,
                    value: .name(makeName(callbackVar))
                )],
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )
            statements.append(.expr(Expr(value: .call(bindCall), lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
            
            // Create binding info for cleanup
            let bindingInfo = BindingInfo(
                sourceObj: sourceObj,
                property: watchedProp,
                callbackVar: callbackVar
            )
            bindings.append(bindingInfo)
        }
        
        return (statements, bindings)
    }
    
    /// Convert canvas property value to Python expression
    private func canvasPropertyValueToExpression(_ property: KvProperty) throws -> PySwiftAST.Expression {
        // Canvas properties are similar to widget properties
        return try propertyValueToExpression(property, widgetName: "Canvas")
    }
}
