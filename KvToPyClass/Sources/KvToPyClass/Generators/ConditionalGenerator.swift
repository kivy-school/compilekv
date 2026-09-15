//
//  ConditionalGenerator.swift
//  KvToPyClass
//

import KvParser
import PySwiftAST

/// Conditional blocks.
///
/// KV has no conditional widgets, so an `if`/`else` or `try`/`expect` block
/// becomes a method on the class that builds whichever branch applies:
///
///     def __init__(self, **kwargs):
///         ...
///         self._conditional_0(self)
///         _callback_2 = lambda *args: self._conditional_0(self)
///         self.bind(disabled_state=_callback_2)
///
///     def _conditional_0(self, parent, *args):
///         self._conditional_0_reset()
///         if self.disabled_state:
///             label_1 = Label(text="no press")
///             parent.add_widget(label_1)
///             self._conditional_0_widgets.append(label_1)
///         else:
///             ...
///
///     def _conditional_0_reset(self):
///         # remove the widgets, unbind the callbacks and drop the canvas
///         # groups the previous evaluation left behind
///
/// `parent` is the widget whose block the conditional sits in; passing it in
/// keeps the method usable from inside a child widget's block, where that
/// widget is only a local of __init__. The method is re-run whenever a
/// property the condition watches changes, and its reset undoes the previous
/// run first, so the tree always reflects the current value.
final class ConditionalGenerator: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    /// Everything one conditional block needs to name.
    private struct Names {
        let index: Int
        var method: String { "_conditional_\(index)" }
        var reset: String { "_conditional_\(index)_reset" }
        var widgets: String { "_conditional_\(index)_widgets" }
        var bindings: String { "_conditional_\(index)_bindings" }
        var canvas: String { "_conditional_\(index)_canvas" }
    }
    
    /// Evaluate the block where it sits and bind its re-evaluation. The
    /// method itself is added to the rule, to go on the class.
    func generate(_ conditional: KvConditional, parent: String, in scope: MethodScope) throws {
        let rule = context.rule
        let names = Names(index: rule.nextConditionalIndex())
        
        // Bindings first, in the caller's scope: `self` still means the
        // widget whose block this is, which is how the watched keys resolve.
        scope.emit(Py.expr(evaluateCall(names, parent: parent)))
        
        if case .if(let condition, let watchedKeys) = conditional.kind {
            let probe = KvProperty(name: "if", value: condition, watchedKeys: watchedKeys, line: conditional.line)
            for key in values.parsePropertyExpression(probe).keys {
                let callback = scope.nextCallback()
                scope.emit(Py.assign(callback, Py.lambda(vararg: "args", body: evaluateCall(names, parent: parent))))
                scope.emit(key.bind(callback))
                scope.track(BindingInfo(key: key, callback: callback))
            }
        }
        
        // The method body runs in its own scope: `parent` stands in for the
        // enclosing widget, and locals of __init__ are out of reach.
        let selfScope = context.selfScope
        try selfScope.inside(parent == "self" ? "self" : "parent", type: selfScope.widgetType) {
            // Nested blocks register themselves while this method is built;
            // this one goes in front of them, and its reset covers theirs.
            let position = rule.conditionalMethods.count
            let resetPosition = rule.conditionalResets.count
            var nested: [String] = []
            let method = try conditionalMethod(conditional, names: names, nestedResets: &nested)
            rule.conditionalMethods.insert(contentsOf: [
                method,
                resetMethod(conditional, names: names, nestedResets: nested),
            ], at: position)
            rule.conditionalResets.removeSubrange(resetPosition...)
            rule.conditionalResets.append(names.reset)
        }
    }
    
    // MARK: Method
    
    /// `def _conditional_N(self, parent, *args):`
    private func conditionalMethod(_ conditional: KvConditional, names: Names, nestedResets: inout [String]) throws -> Statement {
        var body: [Statement] = [Py.expr(Py.method("self", names.reset))]
        
        // Same preamble __init__ gets, since this runs on its own.
        if ModuleAnalysis.mentionsApp([conditional]) {
            body.append(Py.assign("app", Py.method("App", "get_running_app")))
        }
        for id in try outerIdsReferenced(by: conditional).sorted() {
            body.append(Py.assign(id, Py.item(Py.selfAttr("ids"), Py.string(id))))
        }
        
        let resets = context.rule.conditionalResets.count
        let mainBranch = try branchStatements(conditional.body, names: names)
        let elseBranch = try conditional.elseBody.map { try branchStatements($0, names: names) } ?? []
        nestedResets = Array(context.rule.conditionalResets[resets...])
        
        switch conditional.kind {
        case .if(let condition, let watchedKeys):
            let probe = KvProperty(name: "if", value: condition, watchedKeys: watchedKeys, line: conditional.line)
            let test = try values.parsePropertyExpression(probe).expression ?? values.expression(for: probe)
            body.append(Py.if(test, mainBranch, orElse: elseBranch))
        case .try:
            // A failed build leaves half a branch behind; clear it before
            // the fallback goes in.
            body.append(Py.try(
                mainBranch,
                except: Py.name("Exception"),
                [Py.expr(Py.method("self", names.reset))] + elseBranch
            ))
        }
        
        return Py.def(names.method, params: ["self", "parent"], vararg: "args", body: body)
    }
    
    /// One branch: properties on the enclosing widget, then its handlers,
    /// canvas, children and nested blocks, each recorded so the reset can
    /// take it away again.
    private func branchStatements(_ body: KvBody, names: Names) throws -> [Statement] {
        // Its own method, so callback numbering starts over.
        let scope = MethodScope()
        let target = context.selfScope.name
        
        func recordBindings() {
            scope.emit(scope.takeBindings().map { track($0, in: names) })
        }
        
        for property in body.properties {
            if property.isBlock {
                scope.emit(try generators.blocks.valueBlockDefinition(property))
            }
            let value: Expression
            if ValueParser.needsBinding(property), let parsed = values.parsePropertyExpression(property).expression {
                value = parsed
            } else {
                value = try values.expression(for: property)
            }
            scope.emit(Py.assign(target, property.name, value))
            if ValueParser.needsBinding(property) {
                generators.bindings.bind(property, target: target, in: scope)
                recordBindings()
            }
        }
        
        for handler in body.handlers {
            try generators.handlers.bindChild(handler, target: target, in: scope)
            recordBindings()
        }
        
        for (layer, canvas) in CanvasLayer.layers(of: body) where !canvas.instructions.isEmpty {
            try groupedCanvas(canvas.instructions, layer: layer, names: names, in: scope)
            recordBindings()
        }
        
        for child in body.children {
            let variable = generators.widgets.variableName(for: child)
            try generators.widgets.add(child, to: "parent", as: variable, in: scope)
            scope.emit(Py.expr(Py.method(Py.selfAttr(names.widgets), "append", [Py.name(variable)])))
            recordBindings()
        }
        
        for nested in body.conditionals {
            try generate(nested, parent: "parent", in: scope)
            recordBindings()
        }
        
        return scope.statements.isEmpty ? [Py.pass] : scope.statements
    }
    
    /// A branch's canvas goes into an InstructionGroup, which is one thing
    /// to remove later, instead of straight onto the widget's canvas.
    ///
    ///     group_3 = InstructionGroup()
    ///     group_3.add(Color(rgba=(1, 0, 0, 1)))
    ///     self.rectangle_4 = Rectangle(pos=parent.pos, size=parent.size)
    ///     group_3.add(self.rectangle_4)
    ///     parent.canvas.add(group_3)
    ///     self._conditional_0_canvas.append((parent.canvas, group_3))
    private func groupedCanvas(_ instructions: [KvCanvasInstruction], layer: CanvasLayer, names: Names, in scope: MethodScope) throws {
        let canvasGenerator = generators.canvas
        let group = "group_\(context.names.take())"
        var statements: [Statement] = [Py.assign(group, Py.call("InstructionGroup"))]
        var updates: [Statement] = []
        
        for instruction in instructions {
            let keywords = try instruction.properties.map { Py.keyword($0.name, try canvasGenerator.keywordValue($0)) }
            let construction = Py.call(instruction.instructionType, keywords: keywords)
            
            let tracked = instruction.properties.filter(ValueParser.needsBinding)
            guard !tracked.isEmpty else {
                statements.append(Py.expr(Py.method(group, "add", [construction])))
                continue
            }
            
            let attribute = canvasGenerator.name(for: instruction)
            statements.append(Py.assign("self", attribute, construction))
            statements.append(Py.expr(Py.method(group, "add", [Py.selfAttr(attribute)])))
            
            for property in tracked {
                updates.append(contentsOf: scope.capture {
                    generators.bindings.bindCanvas(property, instruction: Py.selfAttr(attribute), in: scope)
                })
            }
        }
        
        let canvas = canvasGenerator.target(layer)
        statements.append(Py.expr(Py.method(canvas, "add", [Py.name(group)])))
        statements.append(Py.expr(Py.method(Py.selfAttr(names.canvas), "append", [Py.tuple([canvas, Py.name(group)])])))
        
        scope.emit(statements)
        scope.emit(updates)
    }
    
    // MARK: Reset
    
    /// `def _conditional_N_reset(self):` -- undo the previous evaluation.
    private func resetMethod(_ conditional: KvConditional, names: Names, nestedResets: [String]) -> Statement {
        var body: [Statement] = []
        
        // for widget in getattr(self, "_conditional_N_widgets", []):
        //     if widget.parent is not None:
        //         widget.parent.remove_widget(widget)
        let widget = Py.name("widget")
        body.append(Py.for(Py.name("widget", ctx: .store), in: storedList(names.widgets), [
            Py.if(
                Py.compare(Py.attr(widget, "parent"), .isNot, Py.none),
                [Py.expr(Py.method(Py.attr(widget, "parent"), "remove_widget", [widget]))]
            )
        ]))
        body.append(clearList(names.widgets))
        
        // for obj, prop, callback in getattr(self, "_conditional_N_bindings", []):
        //     try:
        //         obj.unbind(**{prop: callback})
        //     except:
        //         pass
        body.append(Py.for(
            Py.tuple(["obj", "prop", "callback"].map { Py.name($0, ctx: .store) }, ctx: .store),
            in: storedList(names.bindings),
            [Py.try([Py.expr(Py.method("obj", "unbind", keywords: [
                Py.keyword(nil, Py.dict([Py.name("prop")], [Py.name("callback")]))
            ]))], [Py.pass])]
        ))
        body.append(clearList(names.bindings))
        
        // for canvas, group in getattr(self, "_conditional_N_canvas", []):
        //     canvas.remove(group)
        if ModuleAnalysis.conditionalBodies([conditional]).contains(where: { !CanvasLayer.layers(of: $0).isEmpty }) {
            body.append(Py.for(
                Py.tuple(["canvas", "group"].map { Py.name($0, ctx: .store) }, ctx: .store),
                in: storedList(names.canvas),
                [Py.expr(Py.method("canvas", "remove", [Py.name("group")]))]
            ))
            body.append(clearList(names.canvas))
        }
        
        // Blocks nested in the branches built on top of this one.
        for reset in nestedResets {
            body.append(Py.expr(Py.method("self", reset)))
        }
        
        return Py.def(names.reset, params: ["self"], body: body)
    }
    
    // MARK: Analysis
    
    /// Ids declared outside the block that its values refer to. Those are
    /// locals of __init__, so the method re-reads them from `self.ids`.
    private func outerIdsReferenced(by conditional: KvConditional) throws -> Swift.Set<String> {
        var referenced = Swift.Set<String>()
        var declared = Swift.Set<String>()
        
        func visit(_ body: KvBody) throws {
            for property in body.properties + body.handlers {
                referenced.formUnion(try values.referencedNames(property))
            }
            for (_, canvas) in CanvasLayer.layers(of: body) {
                for property in canvas.instructions.flatMap(\.properties) {
                    referenced.formUnion(try values.referencedNames(property))
                }
            }
            declared.formUnion(ModuleAnalysis.ids(in: body.children))
            for child in body.children {
                try visit(child.body)
            }
            for nested in body.conditionals {
                try visit(nested)
            }
        }
        func visit(_ conditional: KvConditional) throws {
            if case .if(let condition, let keys) = conditional.kind {
                referenced.formUnion(try values.referencedNames(KvProperty(name: "if", value: condition, watchedKeys: keys, line: conditional.line)))
            }
            try visit(conditional.body)
            if let elseBody = conditional.elseBody {
                try visit(elseBody)
            }
        }
        try visit(conditional)
        
        return referenced.intersection(context.rule.pyClass.ids).subtracting(declared)
    }
    
    // MARK: Small AST Helpers
    
    /// `self._conditional_N(parent)`
    private func evaluateCall(_ names: Names, parent: String) -> Expression {
        Py.method("self", names.method, [Py.name(parent)])
    }
    
    /// `self._conditional_N_bindings.append((obj, "prop", callback))`
    private func track(_ binding: BindingInfo, in names: Names) -> Statement {
        Py.expr(Py.method(Py.selfAttr(names.bindings), "append", [binding.tuple]))
    }
    
    /// `getattr(self, "name", [])` -- the list may not exist on the first run.
    private func storedList(_ name: String) -> Expression {
        Py.call("getattr", [Py.name("self"), Py.string(name), Py.list()])
    }
    
    /// `self.name = []`
    private func clearList(_ name: String) -> Statement {
        Py.assign("self", name, Py.list())
    }
}
