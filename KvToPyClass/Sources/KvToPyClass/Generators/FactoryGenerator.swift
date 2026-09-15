//
//  FactoryGenerator.swift
//  KvToPyClass
//

import PySwiftAST

/// What connects the generated module to Kivy's Factory and Builder: aliases
/// for widgets we cannot import, registrations for the classes we define,
/// and the `#:set` constants published for KV files loaded later.
final class FactoryGenerator: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    /// `MyWidget = Factory.MyWidget`
    ///
    /// A plain module constant so the name can be called: a PEP 695
    /// `type MyWidget = Factory.MyWidget` builds a TypeAliasType, which
    /// resolves lazily but is not callable, so `MyWidget(...)` would fail.
    /// The cost is that the Factory is read at import time, which means the
    /// widget has to be registered by then.
    func alias(_ name: String) -> Statement {
        Py.assign(name, Py.attr("Factory", name))
    }
    
    /// `Factory.register("MyWidget", cls=MyWidget)` for each generated class,
    /// so other KV files and Builder can resolve it by name.
    func registrations(for classes: [Statement]) -> [Statement] {
        let registered = StatementQueries.factoryRegistrations(in: context.existingBody)
        var statements: [Statement] = []
        for statement in classes {
            guard case .classDef(let classDef) = statement, !registered.contains(classDef.name) else {
                continue
            }
            statements.append(Py.expr(Py.method(
                "Factory", "register",
                [Py.string(classDef.name)],
                keywords: [Py.keyword("cls", Py.name(classDef.name))]
            )))
        }
        return statements
    }
    
    /// `global_idmap["plex_16"] = sp(16)` for each `#:set` this file declares.
    ///
    /// Builder resolves `#:set` names only for files it has already loaded, so
    /// a .kv loaded at runtime after this module would not see them otherwise.
    func globalIdmapAssignments() -> [Statement] {
        let declared = context.directives.declaredConstants
        return declared.keys.sorted().compactMap { name in
            guard let value = declared[name],
                  let expr = values.parseValue(value) ?? values.parseAssignedExpression(value)
            else { return nil }
            values.recordMetrics(in: expr)
            return Py.assign(Py.item(Py.name("global_idmap"), Py.string(name), ctx: .store), expr)
        }
    }
}
