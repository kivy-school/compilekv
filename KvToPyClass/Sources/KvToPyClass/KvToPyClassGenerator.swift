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
        // Handle str(app.prop) patterns
        if case .name(let funcName) = node.fun, funcName.id == "str" {
            // Visit arguments to extract watched keys
            for arg in node.args {
                visitExpression(arg)
            }
        }
        // Visit the function expression and arguments
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
    private let nameCounter = NameCounter()
    
    /// Track bindings that need to be unbound in __del__
    private struct BindingInfo {
        let sourceObj: String      // e.g., "app", "self"
        let property: String        // e.g., "title", "version"
        let callbackVar: String     // e.g., "_callback_0"
    }
    
    public init(module: KvModule, pythonClasses: [PythonClassInfo] = []) {
        self.module = module
        self.pythonClasses = pythonClasses
    }
    
    /// Generate Python code for all dynamic classes and rules
    public func generate() throws -> String {
        var statements: [Statement] = []
        
        // Collect all widget types that need to be imported
        let widgetTypes = collectWidgetTypes()
        
        // Add imports
        statements.append(contentsOf: generateImports(for: widgetTypes))
        
        // Generate class definitions for rules and templates
        for rule in module.rules {
            statements.append(contentsOf: try generateClassForRule(rule))
        }
        
        // Convert to Python source code
        let pyModule = Module.module(statements)
        
        // Apply Black formatter for proper blank line formatting
        let formatter = BlackFormatter()
        let formattedModule = formatter.formatDeep(pyModule)
        
        let code = try formatModule(formattedModule)
        
        return code
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
            switch rule.selector {
            case .dynamicClass(_, let bases):
                // Only add base classes that aren't custom widgets
                for base in bases where !customWidgets.contains(base) {
                    types.insert(base)
                }
            case .name(_):
                // Skip this name itself since it's a custom widget
                break
            default:
                break
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
            let baseClasses: [String]
            switch rule.selector {
            case .dynamicClass(_, let bases):
                baseClasses = bases.isEmpty ? ["Widget"] : bases
            default:
                continue
            }
            
            let customProps = getCustomProperties(for: rule, baseClasses: baseClasses)
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
    
    private func generateClassForRule(_ rule: KvRule) throws -> [Statement] {
        let selector = rule.selector
        
        // Extract class name and base classes from selector
        let (className, baseClasses): (String, [String])
        switch selector {
        case .dynamicClass(let name, let bases):
            className = name
            // Check if we have Python class info for this class
            if let pythonClass = pythonClasses.first(where: { $0.name == name }) {
                // Use base classes from Python code if they exist
                baseClasses = pythonClass.baseClasses.isEmpty ? (bases.isEmpty ? ["Widget"] : bases) : pythonClass.baseClasses
            } else {
                baseClasses = bases.isEmpty ? ["Widget"] : bases
            }
        case .name(let name):
            // For simple name selectors, check Python code first
            className = name
            if let pythonClass = pythonClasses.first(where: { $0.name == name }) {
                baseClasses = pythonClass.baseClasses.isEmpty ? ["Widget"] : pythonClass.baseClasses
            } else {
                baseClasses = ["Widget"]
            }
        case .className, .multiple:
            // These selector types don't generate classes
            return []
        }
        
        // Generate class body with properties and children
        nameCounter.reset()
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
                let expr = assign.value
                
                // Use visitor to extract watched keys
                let visitor = PropertyExpressionVisitor()
                visitor.visitExpression(expr)
                return (expr, visitor.watchedKeys)
            }
        } catch {
            // If parsing fails, fall back to the pre-computed watchedKeys
            return (nil, property.watchedKeys ?? [])
        }
        
        return (nil, property.watchedKeys ?? [])
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
        guard let watchedKeys = property.watchedKeys, !watchedKeys.isEmpty else {
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
        guard let watchedKeys = property.watchedKeys, !watchedKeys.isEmpty else {
            return ([], [])
        }
        
        // Parse the expression to get the AST
        let (parsedExpr, _) = parsePropertyExpression(property)
        
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
