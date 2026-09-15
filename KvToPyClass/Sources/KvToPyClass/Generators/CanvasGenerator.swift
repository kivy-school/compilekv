//
//  CanvasGenerator.swift
//  KvToPyClass
//

import KvParser
import PySwiftAST

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
final class CanvasGenerator: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    func instructions(_ instructions: [KvCanvasInstruction], layer: CanvasLayer, in scope: MethodScope) throws {
        guard !instructions.isEmpty else { return }
        
        var body: [Statement] = []
        var definitions: [Statement] = []
        
        let updates = try scope.capture {
            for instruction in instructions {
                var keywords: [Keyword] = []
                for property in instruction.properties {
                    if property.isBlock {
                        definitions.append(try generators.blocks.valueBlockDefinition(property))
                    }
                    keywords.append(Py.keyword(property.name, try keywordValue(property)))
                }
                let construction = Py.call(instruction.instructionType, keywords: keywords)
                
                let tracked = instruction.properties.filter(ValueParser.needsBinding)
                guard !tracked.isEmpty else {
                    body.append(Py.expr(construction))
                    continue
                }
                
                let attribute = name(for: instruction)
                body.append(Py.assign("self", attribute, construction))
                for property in tracked {
                    generators.bindings.bindCanvas(property, instruction: Py.selfAttr(attribute), in: scope)
                }
            }
        }
        
        scope.emit(definitions)
        scope.emit(Py.with(target(layer), body))
        scope.emit(updates)
    }
    
    /// `self.rectangle_3` -- the attribute a tracked instruction is kept in.
    func name(for instruction: KvCanvasInstruction) -> String {
        "\(instruction.instructionType.lowercased())_\(context.names.take())"
    }
    
    /// `self.canvas`, `self.canvas.before`, or the same on the child widget
    /// whose block we are in.
    func target(_ layer: CanvasLayer) -> Expression {
        let canvas = Py.attr(context.selfScope.name, "canvas")
        guard let attribute = layer.attribute else { return canvas }
        return Py.attr(canvas, attribute)
    }
    
    /// The instruction's constructor argument. A tracked property needs its
    /// resolved expression, not the placeholder string binding values carry.
    func keywordValue(_ property: KvProperty) throws -> Expression {
        if ValueParser.needsBinding(property), let parsed = values.parsePropertyExpression(property).expression {
            return parsed
        }
        return try values.expression(for: property)
    }
}
