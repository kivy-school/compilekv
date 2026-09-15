//
//  InitMethodGenerator.swift
//  KvToPyClass
//

import KvParser
import PySwiftAST

/// `__init__`: super(), the bindings list, `app` if anything reads it, then
/// the rule's own properties, handlers, children, canvas and conditional
/// blocks, and finally the record of every callback bound along the way.
final class InitMethodGenerator: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    func initMethod(for pyClass: KvPyClass) throws -> Statement {
        let rule = pyClass.rule
        let scope = MethodScope()
        
        scope.emit(Py.expr(Py.method(Py.call("super"), "__init__", keywords: [Py.keyword(nil, Py.name("kwargs"))])))
        scope.emit(Py.assign("self", "_bindings", Py.list()))
        
        if ModuleAnalysis.mentionsApp(rule) {
            scope.emit(Py.assign("app", Py.method("App", "get_running_app")))
        }
        
        // A rule property can name a child by id -- `width: header_box_layout.width`
        // -- and in KV the order does not matter. In Python it does: the
        // variable does not exist until the tree below has been built, so
        // those properties are held back until it has.
        let childIds = ModuleAnalysis.ids(in: rule.children)
        let dependsOnAChild = try rule.properties.map { try !values.referencedNames($0).isDisjoint(with: childIds) }
        let immediate = zip(rule.properties, dependsOnAChild).filter { !$0.1 }.map(\.0)
        let deferred = zip(rule.properties, dependsOnAChild).filter { $0.1 }.map(\.0)
        
        try emitProperties(immediate, in: scope)
        
        for handler in rule.handlers {
            if let bind = generators.handlers.ruleBinding(handler) {
                scope.emit(bind)
            }
        }
        
        for child in rule.children {
            try generators.widgets.add(child, to: "self", in: scope)
        }
        
        // Now the ids they name are real variables.
        try emitProperties(deferred, in: scope)
        
        for (layer, canvas) in CanvasLayer.layers(of: rule.body) where !canvas.instructions.isEmpty {
            try generators.canvas.instructions(canvas.instructions, layer: layer, in: scope)
        }
        
        // if/else and try/expect blocks: evaluated once here, re-evaluated
        // whenever what the condition watches changes.
        for conditional in rule.conditionals {
            try generators.conditionals.generate(conditional, parent: "self", in: scope)
        }
        
        // self._bindings.append((obj, 'prop', callback)) for cleanup in __del__
        for binding in scope.bindings {
            scope.emit(Py.expr(Py.method(Py.selfAttr("_bindings"), "append", [binding.tuple])))
        }
        
        return Py.def("__init__", params: ["self"], kwarg: "kwargs", body: scope.statements)
    }
    
    /// Assign the rule's own properties, then bind the reactive ones.
    private func emitProperties(_ properties: [KvProperty], in scope: MethodScope) throws {
        let bindings = generators.bindings
        for property in properties {
            if property.isBlock {
                scope.emit(try generators.blocks.valueBlockDefinition(property))
            }
            if ValueParser.needsBinding(property) {
                scope.emit(bindings.initialAssignment(property, target: "self"))
            } else {
                scope.emit(Py.assign("self", property.name, try values.expression(for: property)))
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
        for property in properties where ValueParser.needsBinding(property) {
            bindings.bind(property, target: "self", in: scope)
        }
    }
}
