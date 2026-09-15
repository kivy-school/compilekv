//
//  BlockGenerator.swift
//  KvToPyClass
//

import Foundation
import KvParser
import PySwiftAST

/// Block values (`name: |`).
///
/// A property written as `name: |` carries a Python block, not an expression.
/// A handler block becomes a real function body:
///
///     def _on_press_handler(self, instance):          # rule level
///         ...
///     def _callback_3(instance):                       # on a child, in __init__
///         ...
///     button.bind(on_press=_callback_3)
///
/// A value block is a function whose return value is the property, called
/// once for the initial value and again whenever a watched key changes:
///
///     def _value_4():
///         if self.state == "down":
///             return "pressed"
///         return "released"
///     self.text = _value_4()
///     _callback_5 = lambda *args: setattr(self, "text", _value_4())
///     self.bind(state=_callback_5)
final class BlockGenerator: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    enum BlockError: Error, CustomStringConvertible {
        case unparsable(property: String, line: Int)
        
        var description: String {
            switch self {
            case .unparsable(let property, let line):
                return "Line \(line): block value of '\(property)' is not valid Python"
            }
        }
    }
    
    /// The block's statements with `root` / `self` resolved and `#:set`
    /// names substituted. An unparsable block is an error; silently
    /// emitting `pass` would hide it.
    func blockStatements(_ property: KvProperty) throws -> [Statement] {
        guard let statements = property.pythonAST ?? KvPythonParser.parseHandler(property.value) else {
            throw BlockError.unparsable(property: property.name, line: property.line)
        }
        let selfName = context.selfScope.name
        let resolved = statements.map { statement in
            mapNames(inStatement: statement) { name in
                let id: String
                switch name.id {
                case "root": id = "self"
                case "self": id = selfName
                default: return values.constantExpression(named: name.id)
                }
                return .name(Name(id: id, ctx: name.ctx, lineno: name.lineno, colOffset: name.colOffset, endLineno: name.endLineno, endColOffset: name.endColOffset))
            }
        }
        for statement in resolved {
            values.recordMetrics(inStatement: statement)
        }
        return resolved.isEmpty ? [Py.pass] : resolved
    }
    
    // MARK: Value blocks
    
    /// `def _value_N(): ...` -- goes right before the first assignment, in
    /// the same scope, so it closes over ids, `app` and the child locals.
    func valueBlockDefinition(_ property: KvProperty) throws -> Statement {
        Py.def(context.rule.valueBlockName(property, counter: context.names), params: [], body: try blockStatements(property))
    }
    
    /// Re-run the block into `target.<name>` whenever a watched key changes.
    func valueBlockBindings(_ property: KvProperty, target: Expression, in scope: MethodScope) {
        for key in resolver.bindableKeys(property.watchedKeys ?? []) {
            let callback = scope.nextCallback()
            let rerun = Py.call("setattr", [target, Py.string(property.name), values.valueBlockCall(property)])
            scope.emit(Py.assign(callback, Py.lambda(vararg: "args", body: rerun)))
            scope.emit(key.bind(callback))
            scope.track(BindingInfo(key: key, callback: callback))
        }
    }
    
    // MARK: Handler blocks
    
    /// `def _on_x_handler(self, instance): ...` on the class. It runs outside
    /// __init__, so `app` and ids are looked up again first.
    func handlerBlockMethod(_ property: KvProperty) throws -> Statement {
        let body = try blockStatements(property)
        var preamble: [Statement] = []
        
        if property.value.contains("app.") {
            preamble.append(Py.assign("app", Py.method("App", "get_running_app")))
        }
        
        var used = Swift.Set<String>()
        for statement in body { used.formUnion(namesUsed(inStatement: statement)) }
        for id in used.intersection(context.rule.pyClass.ids).sorted() {
            preamble.append(Py.assign(id, Py.item(Py.selfAttr("ids"), Py.string(id))))
        }
        
        return Py.def("_\(property.name)_handler", params: ["self", "instance"], body: preamble + body)
    }
    
    /// `def _callback_N(instance): ...` then `target.bind(on_x=_callback_N)`,
    /// inside __init__ where the child and its siblings are locals.
    func handlerBlockBinding(_ property: KvProperty, target: String, in scope: MethodScope) throws {
        let callback = scope.nextCallback()
        scope.emit(Py.def(callback, params: ["instance"], body: try blockStatements(property)))
        scope.emit(Py.expr(Py.method(target, "bind", keywords: [Py.keyword(property.name, Py.name(callback))])))
        scope.track(BindingInfo(source: target, property: property.name, callback: callback))
    }
}
