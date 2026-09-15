//
//  EventHandlerGenerator.swift
//  KvToPyClass
//

import Foundation
import KvParser
import PySwiftAST

/// `on_press: ...` and friends. On the rule itself a handler is a method:
///
///     self.bind(on_press=self._on_press_handler)
///     def _on_press_handler(self, instance): ...
///
/// On a child it is a lambda bound in __init__, where the child is a local.
final class EventHandlerGenerator: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    /// Event handlers in Kivy start with "on_".
    private func isEventHandler(_ property: KvProperty) -> Bool {
        property.name.hasPrefix("on_")
    }
    
    private func methodName(_ property: KvProperty) -> String {
        "_\(property.name)_handler"
    }
    
    /// `self.bind(on_event=self._on_event_handler)`
    func ruleBinding(_ property: KvProperty) -> Statement? {
        guard isEventHandler(property) else { return nil }
        return Py.expr(Py.method("self", "bind", keywords: [
            Py.keyword(property.name, Py.selfAttr(methodName(property)))
        ]))
    }
    
    /// `def _on_event_handler(self, instance): <handler code>`
    func ruleMethod(_ property: KvProperty) throws -> Statement? {
        guard isEventHandler(property) else { return nil }
        if property.isBlock { return try generators.blocks.handlerBlockMethod(property) }
        
        let code = property.value.trimmingCharacters(in: .whitespaces)
        
        // A call is run; anything else is left as `pass` for now.
        var body: [Statement] = []
        if code.contains("(") && code.contains(")"), let expr = try? handlerExpression(code) {
            body.append(Py.expr(expr))
        } else {
            body.append(Py.pass)
        }
        
        return Py.def(methodName(property), params: ["self", "instance"], body: body)
    }
    
    /// `_callback_N = lambda instance: <handler>` then `target.bind(on_x=_callback_N)`.
    func bindChild(_ handler: KvProperty, target: String, in scope: MethodScope) throws {
        if handler.isBlock {
            try generators.blocks.handlerBlockBinding(handler, target: target, in: scope)
            return
        }
        
        let expr = try handlerExpression(handler.value.trimmingCharacters(in: .whitespaces))
        let callback = scope.nextCallback()
        
        scope.emit(Py.assign(callback, Py.lambda(["instance"], body: expr)))
        scope.emit(Py.expr(Py.method(target, "bind", keywords: [Py.keyword(handler.name, Py.name(callback))])))
        scope.track(BindingInfo(source: target, property: handler.name, callback: callback))
    }
    
    /// The handler's code as an expression. Only the common shapes are
    /// understood: `print(...)` and a no-argument `obj.method()`; anything
    /// else comes back as a bare name.
    private func handlerExpression(_ code: String) throws -> Expression {
        // print("text")
        if code.hasPrefix("print(") && code.hasSuffix(")") {
            let content = String(code.dropFirst(6).dropLast(1))
            let arg: Expression
            
            if content.hasPrefix("\"") && content.hasSuffix("\"") {
                arg = Py.string(String(content.dropFirst(1).dropLast(1)))
            } else if content.hasPrefix("'") && content.hasSuffix("'") {
                arg = Py.string(String(content.dropFirst(1).dropLast(1)))
            } else {
                arg = try handlerExpression(content)
            }
            
            return Py.call("print", [arg])
        }
        
        // app.method(), self.method(), or root.method()
        if code.contains(".") && code.contains("("), let openParen = code.firstIndex(of: "(") {
            let dotParts = String(code[..<openParen]).components(separatedBy: ".")
            if dotParts.count == 2 {
                var object = dotParts[0].trimmingCharacters(in: .whitespaces)
                let method = dotParts[1].trimmingCharacters(in: .whitespaces)
                
                // In KV `root` is the widget the rule applies to, which is
                // `self` in the generated class.
                if object == "root" {
                    object = "self"
                }
                return Py.method(object, method)
            }
        }
        
        return Py.name(code)
    }
}
