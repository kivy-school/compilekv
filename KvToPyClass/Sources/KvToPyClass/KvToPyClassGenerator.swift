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
    func visitSubscript(_ node: Subscript) {
        // self.texture_size[1] still watches texture_size
        visitExpression(node.value)
        visitExpression(node.slice)
    }
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

/// Walk an expression tree, replacing Name nodes the transform answers for.
private func mapNames(in expr: PySwiftAST.Expression, _ transform: (Name) -> PySwiftAST.Expression?) -> PySwiftAST.Expression {
    switch expr {
    case .name(let node):
        return transform(node) ?? expr
        
    case .attribute(let node):
        return .attribute(Attribute(
            value: mapNames(in: node.value, transform),
            attr: node.attr,
            ctx: node.ctx,
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .joinedStr(let node):
        return .joinedStr(JoinedStr(
            values: node.values.map { mapNames(in: $0, transform) },
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .formattedValue(let node):
        return .formattedValue(FormattedValue(
            value: mapNames(in: node.value, transform),
            conversion: node.conversion,
            formatSpec: node.formatSpec,
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .call(let node):
        return .call(Call(
            fun: mapNames(in: node.fun, transform),
            args: node.args.map { mapNames(in: $0, transform) },
            keywords: node.keywords.map { Keyword(arg: $0.arg, value: mapNames(in: $0.value, transform)) },
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .subscriptExpr(let node):
        return .subscriptExpr(Subscript(
            value: mapNames(in: node.value, transform),
            slice: mapNames(in: node.slice, transform),
            ctx: node.ctx,
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .unaryOp(let node):
        return .unaryOp(UnaryOp(op: node.op, operand: mapNames(in: node.operand, transform), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .boolOp(let node):
        return .boolOp(BoolOp(op: node.op, values: node.values.map { mapNames(in: $0, transform) }, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .compare(let node):
        return .compare(Compare(
            left: mapNames(in: node.left, transform),
            ops: node.ops,
            comparators: node.comparators.map { mapNames(in: $0, transform) },
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .dict(let node):
        return .dict(Dict(
            keys: node.keys.map { $0.map { mapNames(in: $0, transform) } },
            values: node.values.map { mapNames(in: $0, transform) },
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .tuple(let node):
        return .tuple(Tuple(elts: node.elts.map { mapNames(in: $0, transform) }, ctx: node.ctx, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .list(let node):
        return .list(List(elts: node.elts.map { mapNames(in: $0, transform) }, ctx: node.ctx, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .binOp(let node):
        return .binOp(BinOp(left: mapNames(in: node.left, transform), op: node.op, right: mapNames(in: node.right, transform), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .ifExp(let node):
        return .ifExp(IfExp(test: mapNames(in: node.test, transform), body: mapNames(in: node.body, transform), orElse: mapNames(in: node.orElse, transform), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    default:
        return expr
    }
}


/// Resolve KV's two implicit objects in an expression tree.
///
/// `root` is the widget the rule applies to, which is `self` in the generated
/// __init__. `self` is the widget whose block the value was written in, which
/// is the rule root at the top level but a child's variable inside a child
/// block -- `height: self.texture_size[1]` under a Label means that Label.
///
/// Both are mapped in one pass so a `root` rewritten to `self` is not then
/// rewritten again into the child's variable.
private func resolveKvObjects(_ expr: PySwiftAST.Expression, selfName: String) -> PySwiftAST.Expression {
    mapNames(in: expr) { name in
        let resolved: String
        switch name.id {
        case "root": resolved = "self"
        case "self": resolved = selfName
        default: return nil
        }
        return .name(Name(id: resolved, ctx: name.ctx, lineno: name.lineno, colOffset: name.colOffset, endLineno: name.endLineno, endColOffset: name.endColOffset))
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
/// Names of kivy.metrics helpers seen in property values, so they can be
/// imported. KV gets these for free from Builder's environment; generated
/// Python has to import them.
private final class MetricsCollector {
    static let functions: Swift.Set<String> = ["dp", "sp", "pt", "mm", "cm", "inch"]
    /// Every name any generated value reads, so `#:import` aliases that are
    /// actually used can be imported and the rest left out.
    var names = Swift.Set<String>()
    var used: Swift.Set<String> { names.intersection(Self.functions) }
}

/// What KV's `self` refers to right now: the rule root by default, or the
/// child widget whose block is being generated.
private final class SelfContext {
    var name = "self"
    var widgetType: String?
}

/// The rule currently being generated: which class, and which of its
/// properties can be bound to.
private final class RuleContext {
    var className = ""
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
    private let selfContext = SelfContext()
    private let metrics = MetricsCollector()
    
    /// Track bindings that need to be unbound in __del__
    private struct BindingInfo {
        let sourceObj: String      // e.g., "app", "self"
        let property: String        // e.g., "title", "version"
        let callbackVar: String     // e.g., "_callback_0"
    }
    
    /// `#:set name value` directives, which KV treats as globals. Kivy's
    /// Builder substitutes them at load time; generated Python has no Builder,
    /// so they are substituted here.
    private let constants: [String: String]
    /// `#:import alias package.path`, which KV resolves into its own namespace.
    /// Generated Python needs a real import for each one it uses.
    private let importDirectives: [String: String]

    public init(
        module: KvModule,
        pythonClasses: [PythonClassInfo] = [],
        existingBody: [Statement] = [],
        sharedDirectives: [KvDirective] = []
    ) {
        self.module = module
        self.pythonClasses = pythonClasses
        self.existingBody = existingBody
        
        // Shared first, so a `#:set` in this file overrides the same name from
        // another one.
        var constants: [String: String] = [:]
        var imports: [String: String] = [:]
        for directive in sharedDirectives + module.directives {
            switch directive {
            case .set(let name, let value, _):
                constants[name] = value
            case .import(let alias, let package, _):
                imports[alias] = package
            default:
                break
            }
        }
        self.constants = constants
        self.importDirectives = imports
    }

    public init(module: KvModule, existing: PythonModuleInfo, sharedDirectives: [KvDirective] = []) {
        self.init(
            module: module,
            pythonClasses: existing.classes,
            existingBody: existing.body,
            sharedDirectives: sharedDirectives
        )
    }
    
    /// Generate Python code for all dynamic classes and rules
    public func generate() throws -> String {
        // Three kinds of widget name: one this module defines, which needs
        // nothing; one Kivy ships, which gets imported; and anything else,
        // which is a custom widget from somewhere we cannot see and so comes
        // off the Factory.
        let referenced = collectWidgetTypes().filter { !isDefinedHere($0) }
        let external = referenced.filter { !KivyWidgetRegistry.widgetExists($0) }
        
        var generatedClasses: [Statement] = []
        for rule in module.rules {
            generatedClasses.append(contentsOf: try generateClassForRule(rule))
        }
        
        let registrations = factoryRegistrations(for: generatedClasses)
        let needsFactory = !external.isEmpty || !registrations.isEmpty
        
        var imports = generateImports(for: referenced.subtracting(external))
        
        imports.append(contentsOf: directiveImports())
        
        // Populated while the classes above were generated.
        if !metrics.used.isEmpty {
            imports.append(.importFrom(ImportFrom(
                module: "kivy.metrics",
                names: metrics.used.sorted().map { Alias(name: $0, asName: nil) },
                level: 0,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )))
        }
        
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
    
    /// An import for each `#:import` alias the generated code actually reads.
    ///
    /// `#:import get_font_name carbonkivy.utils.get_font_name` becomes
    /// `from carbonkivy.utils import get_font_name`. The last segment may name
    /// a module or an attribute of one; `from parent import last` covers both.
    private func directiveImports() -> [Statement] {
        var statements: [Statement] = []
        for alias in importDirectives.keys.sorted() where metrics.names.contains(alias) {
            guard let package = importDirectives[alias] else { continue }
            
            let parts = package.split(separator: ".").map(String.init)
            guard let last = parts.last else { continue }
            
            if parts.count == 1 {
                statements.append(.importStmt(Import(
                    names: [Alias(name: package, asName: alias == package ? nil : alias)],
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )))
            } else {
                statements.append(.importFrom(ImportFrom(
                    module: parts.dropLast().joined(separator: "."),
                    names: [Alias(name: last, asName: alias == last ? nil : alias)],
                    level: 0,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )))
            }
        }
        return statements
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
    
    /// Names bound by a plain assignment, annotation, def or class.
    private func boundNames(in body: [Statement]) -> Swift.Set<String> {
        var names = assignedNames(in: body)
        for statement in body {
            if case .annAssign(let annotated) = statement, case .name(let target) = annotated.target {
                names.insert(target.id)
            }
        }
        return names
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
    
    /// Where a widget actually lives. Most are `kivy.uix.<lowercase>`, but
    /// plenty share a module with a sibling, and guessing invents a module
    /// that does not exist.
    private static let widgetModules: [String: String] = {
        var modules: [String: String] = [:]
        func put(_ module: String, _ names: [String]) {
            for name in names { modules[name] = module }
        }
        put("kivy.uix.behaviors", [
            "ButtonBehavior", "ToggleButtonBehavior", "DragBehavior", "FocusBehavior",
            "CompoundSelectionBehavior", "CodeNavigationBehavior", "EmacsBehavior",
            "CoverBehavior", "TouchRippleBehavior", "TouchRippleButtonBehavior",
            "MotionCollideBehavior", "MotionBlockBehavior",
        ])
        put("kivy.uix.screenmanager", [
            "Screen", "TransitionBase", "NoTransition", "SlideTransition",
            "CardTransition", "FadeTransition", "FallOutTransition",
            "RiseInTransition", "ShaderTransition", "WipeTransition",
        ])
        put("kivy.uix.actionbar", [
            "ActionButton", "ActionGroup", "ActionItem", "ActionOverflow",
            "ActionPrevious", "ActionSeparator", "ActionToggleButton", "ActionView",
        ])
        put("kivy.uix.settings", [
            "Settings", "SettingsPanel", "SettingItem", "SettingBoolean", "SettingColor",
            "SettingOptions", "SettingPath", "SettingSidebarLabel", "SettingString",
            "SettingTitle", "InterfaceWithSidebar", "InterfaceWithSpinner",
            "InterfaceWithTabbedPanel", "MenuSidebar", "MenuSpinner", "ContentPanel",
        ])
        put("kivy.uix.effectwidget", [
            "EffectBase", "AdvancedEffectBase", "ChannelMixEffect",
            "HorizontalBlurEffect", "VerticalBlurEffect", "PixelateEffect",
        ])
        put("kivy.uix.tabbedpanel", ["TabbedPanelHeader", "TabbedPanelStrip", "StripLayout"])
        put("kivy.uix.videoplayer", [
            "VideoPlayerAnnotation", "VideoPlayerPlayPause", "VideoPlayerPreview",
            "VideoPlayerProgressBar", "VideoPlayerStop", "VideoPlayerVolume",
        ])
        put("kivy.uix.rst", [
            "RstBlockQuote", "RstDefinition", "RstDefinitionList", "RstDefinitionSpace",
            "RstDocument", "RstFieldName", "RstFootName", "RstListBullet", "RstListItem",
            "RstLiteralBlock", "RstNote", "RstParagraph", "RstTerm", "RstTitle", "RstWarning",
        ])
        put("kivy.uix.filechooser", [
            "FileChooserController", "FileChooserLayout", "FileChooserProgressBase",
            "FileChooserListView", "FileChooserIconView",
        ])
        put("kivy.uix.accordion", ["AccordionItem"])
        put("kivy.uix.bubble", ["BubbleContent", "BubbleButton"])
        put("kivy.uix.colorpicker", ["ColorWheel"])
        put("kivy.uix.gesturesurface", ["GestureContainer"])
        put("kivy.uix.treeview", ["TreeViewNode", "TreeViewLabel"])
        put("kivy.uix.textinput", ["TextInputCutCopyPaste"])
        put("kivy.uix.image", ["AsyncImage"])
        return modules
    }()
    
    private func kivyModuleForWidget(_ widgetName: String) -> String {
        Self.widgetModules[widgetName] ?? "kivy.uix.\(widgetName.lowercased())"
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
            collectGraphicsTypesFromChildren(rule.children, into: &types)
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
    
    private func collectGraphicsTypesFromChildren(_ children: [KvWidget], into types: inout Swift.Set<String>) {
        for child in children {
            for layer in [child.canvasBefore, child.canvas, child.canvasAfter].compactMap({ $0 }) {
                for instruction in layer.instructions {
                    types.insert(instruction.instructionType)
                }
            }
            collectGraphicsTypesFromChildren(child.children, into: &types)
        }
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
        selfContext.name = "self"
        selfContext.widgetType = nil
        ruleContext.className = className
        ruleContext.baseClasses = baseClasses
        ruleContext.selfProperties = Swift.Set(pythonClasses.first(where: { $0.name == className })?.kivyProperties.keys ?? [:].keys)
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
        
        // A rule with nothing in it still has to be a valid class body. The
        // blank line above does not count as content.
        if !body.contains(where: { if case .blank = $0 { return false } else { return true } }) {
            body.append(.pass(Pass(lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
        }
        
        // Fold the generated members into the class the author wrote, rather
        // than the other way round, so everything in it survives.
        if let pythonClass = pythonClasses.first(where: { $0.name == className }) {
            body = mergeClassBody(body, into: pythonClass.classDefAST.body)
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
    
    /// Merge generated members into the existing class body.
    ///
    /// The author's body is the starting point, so properties, annotations,
    /// the docstring, nested classes and anything else stay put. A generated
    /// method replaces the one it shares a name with, except `__init__`, which
    /// is appended to rather than replaced.
    private func mergeClassBody(_ generated: [Statement], into existing: [Statement]) -> [Statement] {
        var generatedFunctions: [String: FunctionDef] = [:]
        for statement in generated {
            if case .functionDef(let function) = statement {
                generatedFunctions[function.name] = function
            }
        }
        
        var result: [Statement] = []
        var replaced = Swift.Set<String>()
        for statement in existing {
            switch statement {
            case .functionDef(let existingFunction):
                guard let generatedFunction = generatedFunctions[existingFunction.name] else {
                    result.append(statement)
                    continue
                }
                replaced.insert(existingFunction.name)
                result.append(.functionDef(
                    existingFunction.name == "__init__"
                        ? mergedInit(existing: existingFunction, generated: generatedFunction)
                        : generatedFunction
                ))
            case .pass:
                // The class has real content now.
                continue
            default:
                result.append(statement)
            }
        }
        
        let bound = boundNames(in: existing)
        for statement in generated {
            switch statement {
            case .blank:
                continue
            case .functionDef(let function) where replaced.contains(function.name):
                continue
            case .assign(let assign):
                // Never shadow a property the author declared themselves.
                if case .name(let target) = assign.targets.first, bound.contains(target.id) {
                    continue
                }
            default:
                break
            }
            result.append(statement)
        }
        
        if result.isEmpty {
            return [.pass(Pass(lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))]
        }
        return separateNestedClasses(in: openWithBlankLine(result))
    }
    
    /// A class body opens with a blank line, matching what is generated when
    /// there is no existing class to merge into -- otherwise the first run and
    /// the second would differ. A docstring goes flush against the header, and
    /// BlackFormatter puts the blank after it.
    private func openWithBlankLine(_ body: [Statement]) -> [Statement] {
        switch body.first {
        case .blank:
            return body
        case .expr(let expr) where isStringConstant(expr.value):
            return body
        default:
            return [.blank(1)] + body
        }
    }
    
    private func isStringConstant(_ expr: PySwiftAST.Expression) -> Bool {
        guard case .constant(let constant) = expr, case .string = constant.value else { return false }
        return true
    }
    
    /// A blank line before a nested class. BlackFormatter spaces methods but
    /// not classes inside a class body.
    private func separateNestedClasses(in body: [Statement]) -> [Statement] {
        var spaced: [Statement] = []
        for statement in body {
            if case .classDef = statement, let previous = spaced.last {
                if case .blank = previous {} else { spaced.append(.blank(1)) }
            }
            spaced.append(statement)
        }
        return spaced
    }
    
    /// Append the generated __init__ body to the one already there.
    ///
    /// Everything from `self._bindings = []` onwards was written by a previous
    /// run -- nothing else emits that line -- so it is dropped first, which is
    /// what keeps regeneration from stacking copies of the widget tree. The
    /// author's signature and their super() call are the ones that survive.
    private func mergedInit(existing: FunctionDef, generated: FunctionDef) -> FunctionDef {
        var handWritten = existing.body
        if let marker = handWritten.firstIndex(where: isBindingsInit) {
            handWritten = Array(handWritten[..<marker])
        }
        
        return FunctionDef(
            name: existing.name,
            args: existing.args,
            body: handWritten + generated.body.filter { !isSuperInit($0) },
            decoratorList: existing.decoratorList,
            returns: existing.returns,
            typeComment: existing.typeComment,
            typeParams: existing.typeParams,
            lineno: existing.lineno, colOffset: existing.colOffset,
            endLineno: existing.endLineno, endColOffset: existing.endColOffset
        )
    }
    
    /// `self._bindings = []`
    private func isBindingsInit(_ statement: Statement) -> Bool {
        guard case .assign(let assign) = statement,
              case .attribute(let target) = assign.targets.first,
              target.attr == "_bindings",
              case .name(let object) = target.value,
              object.id == "self"
        else { return false }
        return true
    }
    
    /// `super().__init__(...)`
    private func isSuperInit(_ statement: Statement) -> Bool {
        guard case .expr(let expr) = statement,
              case .call(let call) = expr.value,
              case .attribute(let callee) = call.fun,
              callee.attr == "__init__",
              case .call(let inner) = callee.value,
              case .name(let superName) = inner.fun,
              superName.id == "super"
        else { return false }
        return true
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
    
    /// Assign the rule's own properties, then bind the reactive ones.
    private func appendProperties(
        _ properties: [KvProperty],
        to body: inout [Statement],
        bindings: inout [BindingInfo],
        callbackCounter: inout Int
    ) throws {
        for property in properties {
            if needsBinding(property) {
                body.append(try generatePropertyBinding(property))
            } else {
                body.append(.assign(Assign(
                    targets: [.attribute(Attribute(
                        value: .name(makeName("self")),
                        attr: property.name,
                        ctx: .store,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    ))],
                    value: try propertyValueToExpression(property),
                    typeComment: nil,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                )))
            }
        }
        
        // Bind calls come after the assignments, so the initial values are all
        // in place before anything can fire.
        //
        // Same binder the children use, with `self` as the target: a plain
        // `obj.prop` value becomes a setter, anything else becomes a callback
        // that recomputes the expression. Handing a setter a value it was
        // never meant to hold -- the new `variant` where a `size_hint` tuple
        // belongs -- is how this used to break.
        for property in properties where needsBinding(property) {
            let (statements, infos) = generateChildPropertyBinding(
                property, widgetVarName: "self", callbackCounter: &callbackCounter
            )
            body.append(contentsOf: statements)
            bindings.append(contentsOf: infos)
        }
    }
    
    /// Every id in the widget tree, at any depth.
    private func collectIds(in children: [KvWidget]) -> Swift.Set<String> {
        var ids = Swift.Set<String>()
        for child in children {
            if let id = child.id { ids.insert(id) }
            ids.formUnion(collectIds(in: child.children))
        }
        return ids
    }
    
    /// The names a property value reads.
    private func referencedNames(_ property: KvProperty) throws -> Swift.Set<String> {
        if let expr = parsePropertyExpression(property).0 {
            return namesUsed(in: expr)
        }
        return namesUsed(in: try propertyValueToExpression(property))
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
        
        // A rule property can name a child by id -- `width: header_box_layout.width`
        // -- and in KV the order does not matter. In Python it does: the
        // variable does not exist until the tree below has been built, so
        // those properties are held back until it has.
        let childIds = collectIds(in: rule.children)
        let dependsOnAChild = try rule.properties.map { try !referencedNames($0).isDisjoint(with: childIds) }
        let immediate = zip(rule.properties, dependsOnAChild).filter { !$0.1 }.map(\.0)
        let deferred = zip(rule.properties, dependsOnAChild).filter { $0.1 }.map(\.0)
        
        // Set properties (self.property = value)
        // Event handlers are in rule.handlers, not rule.properties
        try appendProperties(immediate, to: &body, bindings: &bindings, callbackCounter: &callbackCounter)
        
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
        
        // Now the ids they name are real variables.
        try appendProperties(deferred, to: &body, bindings: &bindings, callbackCounter: &callbackCounter)
        
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
    
    /// A KV property value is a Python expression: `text: whatever` means
    /// `widget.text = whatever`. Parse it and use it.
    private func propertyValueToExpression(_ property: KvProperty) throws -> PySwiftAST.Expression {
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
        return .constant(makeConstant(.string(literal)))
    }
    
    /// The value as a Python expression, or nil to fall back to a string.
    ///
    /// A bare name is the awkward case. `orientation: vertical` is a sloppy
    /// literal far more often than a module global, so it stays a string --
    /// unless it is a `#:set` constant, which is substituted, or the property
    /// it is being assigned to cannot hold a string, in which case a string
    /// would be wrong no matter what.
    private func parseValue(_ valueStr: String, assignedTo propertyName: String? = nil) -> PySwiftAST.Expression? {
        guard let assign = parseAssignedExpression(valueStr) else { return nil }
        
        if case .name(let name) = assign {
            if let constant = constants[name.id] {
                return parseValue(constant, assignedTo: propertyName)
            }
            guard let propertyName, holdsNonStringValue(propertyName) else { return nil }
        }
        
        let expr = substitutingConstants(in: resolveKvObjects(assign, selfName: selfContext.name))
        recordMetrics(in: expr)
        return expr
    }
    
    /// Parse a KV property value as a Python expression.
    ///
    /// Two repairs are tried, and only after the value has failed to parse as
    /// written, so text that means something -- a backslash or a trailing dot
    /// inside a string literal -- is left alone whenever it can be.
    private func parseAssignedExpression(_ valueStr: String) -> PySwiftAST.Expression? {
        guard !valueStr.isEmpty else { return nil }
        
        func parse(_ source: String) -> PySwiftAST.Expression? {
            guard let module = try? parsePython("_tmp = \(source)"),
                  case .module(let statements) = module,
                  case .assign(let assign) = statements.first
            else { return nil }
            return assign.value
        }
        
        if let expr = parse(valueStr) { return expr }
        
        // A value spread over several lines arrives with its continuation
        // backslashes still in it, joined onto one line.
        let joined = valueStr.contains("\\")
            ? valueStr.replacingOccurrences(of: "\\", with: " ")
            : valueStr
        if joined != valueStr, let expr = parse(joined) { return expr }
        
        // `2.` is a float to Python but not to the parser we use.
        let padded = paddingBareFloats(in: joined)
        if padded != joined, let expr = parse(padded) { return expr }
        
        return nil
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
    
    /// Replace `#:set` names anywhere in an expression, so `plex_16 + 4` works
    /// as well as a bare `plex_16`.
    private func substitutingConstants(in expr: PySwiftAST.Expression) -> PySwiftAST.Expression {
        guard !constants.isEmpty else { return expr }
        return mapNames(in: expr) { name in
            guard let value = constants[name.id],
                  let module = try? parsePython("_tmp = \(value)"),
                  case .module(let statements) = module,
                  case .assign(let assign) = statements.first
            else { return nil }
            return assign.value
        }
    }
    
    /// Can the property named here hold a string? A bare word assigned to a
    /// numeric or colour property is never a string literal.
    private func holdsNonStringValue(_ propertyName: String) -> Bool {
        guard let type = propertyType(of: propertyName) else { return false }
        switch type {
        case .stringProperty, .optionProperty, .objectProperty, .aliasProperty:
            return false
        default:
            return true
        }
    }
    
    /// The declared type of a property on whatever the value is being assigned
    /// to: the child widget whose block we are in, or the rule's own class.
    private func propertyType(of propertyName: String) -> KivyPropertyType? {
        if let widgetType = selfContext.widgetType {
            return propertyType(of: propertyName, on: widgetType, depth: 0)
        }
        // The rule's own class first: it may declare the property itself.
        if let type = propertyType(of: propertyName, on: ruleContext.className, depth: 0) {
            return type
        }
        for base in ruleContext.baseClasses {
            if let type = propertyType(of: propertyName, on: base, depth: 0) { return type }
        }
        return nil
    }
    
    private func propertyType(of propertyName: String, on owner: String, depth: Int) -> KivyPropertyType? {
        guard depth < 8 else { return nil }
        
        if let declared = pythonClasses.first(where: { $0.name == owner })?.kivyProperties[propertyName] {
            return KivyPropertyType(rawValue: declared)
        }
        if let type = KivyWidgetRegistry.getPropertyType(propertyName, on: owner) {
            return type
        }
        
        // Not a Kivy widget: follow whatever it inherits from.
        let bases = pythonClasses.first(where: { $0.name == owner })?.baseClasses
            ?? module.rules.first(where: { resolvedClass(for: $0)?.name == owner })
                .flatMap { resolvedClass(for: $0)?.bases }
            ?? []
        for base in bases where base != owner {
            if let type = propertyType(of: propertyName, on: base, depth: depth + 1) { return type }
        }
        return nil
    }
    
    /// Note any kivy.metrics helper the expression calls, so generate() can
    /// import it.
    private func recordMetrics(in expr: PySwiftAST.Expression) {
        metrics.names.formUnion(namesUsed(in: expr))
    }
    
    private func namesUsed(in expr: PySwiftAST.Expression) -> Swift.Set<String> {
        var names = Swift.Set<String>()
        func walk(_ expr: PySwiftAST.Expression) {
            switch expr {
            case .name(let node):
                names.insert(node.id)
            case .attribute(let node):
                walk(node.value)
            case .call(let node):
                walk(node.fun)
                node.args.forEach(walk)
                node.keywords.forEach { walk($0.value) }
            case .binOp(let node):
                walk(node.left); walk(node.right)
            case .unaryOp(let node):
                walk(node.operand)
            case .boolOp(let node):
                node.values.forEach(walk)
            case .compare(let node):
                walk(node.left); node.comparators.forEach(walk)
            case .ifExp(let node):
                walk(node.test); walk(node.body); walk(node.orElse)
            case .tuple(let node):
                node.elts.forEach(walk)
            case .list(let node):
                node.elts.forEach(walk)
            case .set(let node):
                node.elts.forEach(walk)
            case .dict(let node):
                node.keys.forEach { $0.map(walk) }
                node.values.forEach(walk)
            case .joinedStr(let node):
                node.values.forEach(walk)
            case .formattedValue(let node):
                walk(node.value)
            case .subscriptExpr(let node):
                walk(node.value); walk(node.slice)
            default:
                break
            }
        }
        walk(expr)
        return names
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
        guard let parsed = parseAssignedExpression(property.value.trimmingCharacters(in: .whitespaces)) else {
            // Fall back to the watched keys the KV parser worked out.
            return (nil, bindableKeys(property.watchedKeys ?? []))
        }
        
        // Watched keys come off the unresolved tree so they still say
        // `root` / `self`; bindableKeys needs to know which is which before
        // they become variable names.
        let visitor = PropertyExpressionVisitor()
        visitor.visitExpression(parsed)
        
        let expr = substitutingConstants(in: resolveKvObjects(parsed, selfName: selfContext.name))
        recordMetrics(in: expr)
        return (expr, bindableKeys(visitor.watchedKeys))
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
            let property = key[1]
            
            let object: String
            let bindable: Bool
            switch key[0] {
            case "root":
                object = "self"
                bindable = isBindableRuleProperty(property)
            case "self":
                object = selfContext.name
                bindable = selfContext.widgetType.map { isBindableProperty(property, on: $0) }
                    ?? isBindableRuleProperty(property)
            default:
                // app, or an id: nothing here can say what it is.
                object = key[0]
                bindable = true
            }
            guard bindable else { return nil }
            
            // One expression can name the same property more than once; it
            // still only needs binding once.
            return seen.insert([object, property]).inserted ? [object, property] : nil
        }
    }
    
    /// Is `name` a property of the class this rule generates?
    private func isBindableRuleProperty(_ name: String) -> Bool {
        if ruleContext.selfProperties.contains(name) { return true }
        return ruleContext.baseClasses.contains { base in
            KivyWidgetRegistry.getPropertyType(name, on: base) != nil
        }
    }
    
    /// Is `name` a property of `widgetType`?
    ///
    /// The registry answers for anything Kivy ships. A widget defined by
    /// another rule, or by a class in the .py, is resolved to its own
    /// declarations and bases. A widget from outside the module cannot be
    /// checked, so it is assumed bindable rather than silently dropped.
    private func isBindableProperty(_ name: String, on widgetType: String) -> Bool {
        if KivyWidgetRegistry.widgetExists(widgetType) {
            return KivyWidgetRegistry.getPropertyType(name, on: widgetType) != nil
        }
        
        if let pythonClass = pythonClasses.first(where: { $0.name == widgetType }) {
            if pythonClass.kivyProperties[name] != nil { return true }
            if pythonClass.baseClasses.contains(where: { isBindableProperty(name, on: $0) }) { return true }
            // A class we can see in full: if it does not declare the property,
            // it does not have one.
            return false
        }
        
        if let rule = module.rules.first(where: { resolvedClass(for: $0)?.name == widgetType }),
           let resolved = resolvedClass(for: rule) {
            if getCustomProperties(for: rule, baseClasses: resolved.bases).contains(name) { return true }
            return resolved.bases.contains { isBindableProperty(name, on: $0) }
        }
        
        return true
    }
    
    private func isEventHandler(_ property: KvProperty) -> Bool {
        // Event handlers in Kivy start with "on_"
        return property.name.hasPrefix("on_")
    }
    
    private func generatePropertyBinding(_ property: KvProperty, targetName: String = "self") throws -> Statement {
        let valueStr = property.value.trimmingCharacters(in: .whitespaces)
        
        // Parse the expression and extract watched keys using visitor
        let (parsedExpr, watchedKeys) = parsePropertyExpression(property)
        
        // Simple means the value is nothing but `obj.prop`. That is a question
        // about the parsed expression, not about what characters the source
        // happens to contain: `{...}[self.parent.role]` watches one key and has
        // no parentheses, but assigning `self.parent` to the property would be
        // nonsense.
        let isSimpleBinding: Bool
        if case .attribute = parsedExpr, watchedKeys.count == 1, watchedKeys[0].count == 2 {
            isSimpleBinding = true
        } else {
            isSimpleBinding = false
        }
        
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
        
        // Inside this block KV's `self` means this widget, not the rule root.
        // Restored on the way out so siblings and the enclosing block are
        // unaffected.
        let enclosingSelf = (selfContext.name, selfContext.widgetType)
        selfContext.name = varName
        selfContext.widgetType = widget.name
        defer {
            selfContext.name = enclosingSelf.0
            selfContext.widgetType = enclosingSelf.1
        }
        
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
                value: try propertyValueToExpression(property)
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
                valueExpr = try propertyValueToExpression(property)
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
        
        // An id is the local variable, and generated code refers to it that
        // way. It is also published in self.ids, because that is where hand
        // written code looks for it -- as a dict entry, which is what `x in
        // self.ids` and `self.ids.x` both read.
        if let widgetId {
            statements.append(.assign(Assign(
                targets: [.subscriptExpr(Subscript(
                    value: .attribute(Attribute(
                        value: .name(makeName("self")),
                        attr: "ids",
                        ctx: .load,
                        lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                    )),
                    slice: .constant(makeConstant(.string(widgetId))),
                    ctx: .store,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                ))],
                value: .name(makeName(varName)),
                typeComment: nil,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )))
        }
        
        // The widget's own canvas layers. `self` inside them is this widget,
        // which the scope set above already takes care of.
        for (instructions, layer) in [
            (widget.canvasBefore?.instructions, "before"),
            (widget.canvas?.instructions, nil),
            (widget.canvasAfter?.instructions, "after"),
        ] as [([KvCanvasInstruction]?, String?)] {
            guard let instructions, !instructions.isEmpty else { continue }
            let (canvasStmts, canvasBindings) = try generateCanvasInstructions(
                instructions, layer: layer, callbackCounter: &callbackCounter
            )
            statements.append(contentsOf: canvasStmts)
            bindings.append(contentsOf: canvasBindings)
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
                value: try propertyValueToExpression(property)
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
    /// A canvas layer, written the way Kivy is written by hand:
    ///
    ///     with self.canvas.before:
    ///         Color(rgba=(1, 0, 0, 1))
    ///         self.rectangle_1 = Rectangle(pos=self.pos, size=self.size)
    ///     self.bind(pos=_callback_0, size=_callback_1)
    ///
    /// An instruction whose properties track something is named, so the
    /// bindings have an object to update; the rest stay anonymous. The
    /// bindings go after the block, where the names exist.
    private func generateCanvasInstructions(_ instructions: [KvCanvasInstruction], layer: String?, callbackCounter: inout Int) throws -> ([Statement], [BindingInfo]) {
        guard !instructions.isEmpty else { return ([], []) }
        
        var body: [Statement] = []
        var updates: [Statement] = []
        var bindings: [BindingInfo] = []
        
        for instruction in instructions {
            var keywords: [Keyword] = []
            for property in instruction.properties {
                keywords.append(Keyword(arg: property.name, value: try canvasKeywordValue(property)))
            }
            
            let construction = PySwiftAST.Expression.call(Call(
                fun: .name(makeName(instruction.instructionType)),
                args: [],
                keywords: keywords,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            ))
            
            let tracked = instruction.properties.filter { needsBinding($0) }
            guard !tracked.isEmpty else {
                body.append(.expr(Expr(value: construction, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil)))
                continue
            }
            
            let attrName = "\(instruction.instructionType.lowercased())_\(nameCounter.take())"
            body.append(.assign(Assign(
                targets: [.attribute(Attribute(
                    value: .name(makeName("self")),
                    attr: attrName,
                    ctx: .store,
                    lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
                ))],
                value: construction,
                typeComment: nil,
                lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
            )))
            
            for property in tracked {
                let (statements, infos) = generateCanvasPropertyBinding(
                    property,
                    instrVarName: "self.\(attrName)",
                    callbackCounter: &callbackCounter
                )
                updates.append(contentsOf: statements)
                bindings.append(contentsOf: infos)
            }
        }
        
        let block = With(
            items: [WithItem(contextExpr: canvasTarget(layer: layer), optionalVars: nil)],
            body: body,
            typeComment: nil,
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        return ([.withStmt(block)] + updates, bindings)
    }
    
    /// `self.canvas`, `self.canvas.before`, or the same on the child widget
    /// whose block we are in.
    private func canvasTarget(layer: String?) -> PySwiftAST.Expression {
        let canvas = Attribute(
            value: .name(makeName(selfContext.name)),
            attr: "canvas",
            ctx: .load,
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        )
        guard let layer else { return .attribute(canvas) }
        return .attribute(Attribute(
            value: .attribute(canvas),
            attr: layer,
            ctx: .load,
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        ))
    }
    
    /// The instruction's constructor argument. A tracked property needs its
    /// resolved expression, not the placeholder string binding values carry.
    private func canvasKeywordValue(_ property: KvProperty) throws -> PySwiftAST.Expression {
        if needsBinding(property), let parsed = parsePropertyExpression(property).0 {
            return parsed
        }
        return try canvasPropertyValueToExpression(property)
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
        return try propertyValueToExpression(property)
    }
}
