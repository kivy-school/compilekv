//
//  PropertyBindingGenerator.swift
//  KvToPyClass
//

import KvParser
import PySwiftAST

/// Keeps a property in step with what its value reads.
///
/// A value that is nothing but `obj.prop` gets a setter:
///
///     app.bind(title=label_1.setter("text"))
///
/// Anything else gets one callback per watched key that recomputes the whole
/// expression, with the changed value coming in as a parameter:
///
///     _callback_0 = lambda instance, app_title: setattr(label_1, "text", f"{app_title}!")
///     app.bind(title=_callback_0)
final class PropertyBindingGenerator: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    /// `target.name = <value>` for a bound property: the watched attribute
    /// itself when that is all the value is, else the parsed expression, else
    /// the raw text.
    func initialAssignment(_ property: KvProperty, target: String) -> Statement {
        let (parsed, keys) = values.parsePropertyExpression(property)
        
        // Simple means the value is nothing but `obj.prop`. That is a question
        // about the parsed expression, not about what characters the source
        // happens to contain: `{...}[self.parent.role]` watches one key and has
        // no parentheses, but assigning `self.parent` to the property would be
        // nonsense.
        let value: Expression
        if case .attribute = parsed, keys.count == 1, let key = keys.first {
            value = Py.attr(key.source.name, key.property)
        } else if let parsed {
            value = parsed
        } else {
            value = Py.string(property.value.trimmingCharacters(in: .whitespaces))
        }
        return Py.assign(target, property.name, value)
    }
    
    /// The bind calls that keep `target.name` current, tracked in `scope`
    /// where they need unbinding later.
    func bind(_ property: KvProperty, target: String, in scope: MethodScope) {
        if property.isBlock {
            generators.blocks.valueBlockBindings(property, target: Py.name(target), in: scope)
            return
        }
        
        // Watched keys come back with `root` renamed and unbindable
        // attributes dropped.
        let (parsed, keys) = values.parsePropertyExpression(property)
        guard let expr = parsed, !keys.isEmpty else { return }
        
        // A direct attribute access and nothing else: a setter does it, and
        // Kivy manages that callback itself, so there is nothing to track.
        if keys.count == 1, case .attribute = expr {
            scope.emit(keys[0].bindSetter(of: target, property.name))
            return
        }
        
        for key in keys {
            let parameter = "\(key.source.name)_\(key.property)"
            let callback = scope.nextCallback()
            
            // lambda instance, app_title: setattr(target, "name", <expr with app.title -> app_title>)
            let recompute = Py.call("setattr", [
                Py.name(target),
                Py.string(property.name),
                replaceAttribute(key, withName: parameter, in: expr),
            ])
            scope.emit(Py.assign(callback, Py.lambda(["instance", parameter], body: recompute)))
            scope.emit(key.bind(callback))
            scope.track(BindingInfo(key: key, callback: callback))
        }
    }
    
    /// Bindings for a canvas instruction's property, e.g. `pos: self.pos`.
    ///
    /// The callback takes the new value; a value that is just the watched
    /// attribute uses it directly, anything else is re-read off the instance.
    func bindCanvas(_ property: KvProperty, instruction: Expression, in scope: MethodScope) {
        if property.isBlock {
            generators.blocks.valueBlockBindings(property, target: instruction, in: scope)
            return
        }
        
        let (parsed, _) = values.parsePropertyExpression(property)
        let visitor = WatchedKeyVisitor()
        if let parsed {
            visitor.visitExpression(parsed)
        }
        
        for key in visitor.watchedKeys.compactMap(BindableKey.init) {
            let callback = scope.nextCallback()
            
            let value: Expression
            if let parsed {
                if case .attribute(let attr) = parsed,
                   case .name(let object) = attr.value,
                   object.id == key.source.name && attr.attr == key.property {
                    value = Py.name("value")
                } else {
                    value = replaceSelfWithInstance(in: parsed)
                }
            } else {
                value = Py.name("value")
            }
            
            let update = Py.call("setattr", [instruction, Py.string(property.name), value])
            scope.emit(Py.assign(callback, Py.lambda(["instance", "value"], body: update)))
            scope.emit(key.bind(callback))
            scope.track(BindingInfo(key: key, callback: callback))
        }
    }
}
