//
//  WidgetTreeGenerator.swift
//  KvToPyClass
//

import KvParser
import PySwiftAST

/// A child widget, built the way it would be by hand:
///
///     label_1 = Label(text="static")
///     label_1.font_size = app.size
///     app.bind(size=label_1.setter("font_size"))
///     self.ids["title"] = label_1
///     ...its canvas, children, conditionals and handlers...
///     self.add_widget(label_1)
final class WidgetTreeGenerator: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    /// The local a child widget is assigned to: its id, or a fresh
    /// `<type>_<n>` (e.g. `label_3`, `box_4` for a BoxLayout).
    func variableName(for widget: KvWidget) -> String {
        if let id = widget.id {
            return id
        }
        let prefix = widget.name.lowercased().replacingOccurrences(of: "layout", with: "").prefix(10)
        return "\(prefix)_\(context.names.take())"
    }
    
    /// Create `widget`, wire it up and add it to `parent`.
    func add(_ widget: KvWidget, to parent: String, as variable: String? = nil, in scope: MethodScope) throws {
        let name = variable ?? variableName(for: widget)
        
        // Inside this block KV's `self` means this widget, not the rule root.
        try context.selfScope.inside(name, type: widget.name) {
            try build(widget, as: name, in: scope)
        }
        
        scope.emit(Py.expr(Py.method(parent, "add_widget", [Py.name(name)])))
    }
    
    private func build(_ widget: KvWidget, as name: String, in scope: MethodScope) throws {
        let bound = widget.properties.filter { ValueParser.needsBinding($0) || $0.isBlock }
        let fixed = widget.properties.filter { !(ValueParser.needsBinding($0) || $0.isBlock) }
        
        // Constructed with only the static properties.
        let keywords = try fixed.map { Py.keyword($0.name, try values.expression(for: $0)) }
        scope.emit(Py.assign(name, Py.call(widget.name, keywords: keywords)))
        
        // The reactive ones are set afterwards and then bound.
        for property in bound {
            if property.isBlock {
                scope.emit(try generators.blocks.valueBlockDefinition(property))
            }
            let value = try values.parsePropertyExpression(property).expression ?? values.expression(for: property)
            scope.emit(Py.assign(name, property.name, value))
            generators.bindings.bind(property, target: name, in: scope)
        }
        
        // An id is the local variable, and generated code refers to it that
        // way. It is also published in self.ids, because that is where hand
        // written code looks for it -- as a dict entry, which is what `x in
        // self.ids` and `self.ids.x` both read.
        if let id = widget.id {
            scope.emit(Py.assign(Py.item(Py.selfAttr("ids"), Py.string(id), ctx: .store), Py.name(name)))
        }
        
        // The widget's own canvas layers. `self` inside them is this widget,
        // which the scope set above already takes care of.
        for (layer, canvas) in CanvasLayer.layers(of: widget.body) where !canvas.instructions.isEmpty {
            try generators.canvas.instructions(canvas.instructions, layer: layer, in: scope)
        }
        
        for child in widget.children {
            try add(child, to: name, in: scope)
        }
        
        // Conditional blocks whose branches hang off this widget.
        for conditional in widget.conditionals {
            try generators.conditionals.generate(conditional, parent: name, in: scope)
        }
        
        for handler in widget.handlers {
            try generators.handlers.bindChild(handler, target: name, in: scope)
        }
    }
}
