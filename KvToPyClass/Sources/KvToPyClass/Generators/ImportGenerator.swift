//
//  ImportGenerator.swift
//  KvToPyClass
//

import PySwiftAST

/// The import block: widgets from their kivy.uix modules, App, the property
/// and graphics classes the file uses, and whatever the `#:` directives ask
/// for.
final class ImportGenerator: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    func widgetImports(for widgetTypes: Swift.Set<String>) -> [Statement] {
        var imports: [Statement] = []
        var lineNum = 1
        
        for widgetType in widgetTypes.sorted() {
            imports.append(Py.importFrom(
                context.dialect.module(for: widgetType),
                [Alias(name: widgetType, asName: nil)],
                lineno: lineNum
            ))
            lineNum += 1
        }
        
        if context.module.rules.contains(where: ModuleAnalysis.mentionsApp) {
            imports.append(Py.importFrom("kivy.app", [Alias(name: "App", asName: nil)], lineno: lineNum))
            lineNum += 1
        }
        
        let propertyTypes = propertyTypes()
        if !propertyTypes.isEmpty {
            imports.append(Py.importFrom(
                "kivy.properties",
                propertyTypes.sorted().map { Alias(name: $0, asName: nil) },
                lineno: lineNum
            ))
            lineNum += 1
        }
        
        let graphicsTypes = generators.analysis.graphicsTypes()
        if !graphicsTypes.isEmpty {
            imports.append(Py.importFrom(
                "kivy.graphics",
                graphicsTypes.sorted().map { Alias(name: $0, asName: nil) },
                lineno: lineNum
            ))
        }
        
        return imports
    }
    
    /// Property classes the generated declarations use. Every property a
    /// rule declares is an ObjectProperty.
    private func propertyTypes() -> Swift.Set<String> {
        var types = Swift.Set<String>()
        for rule in context.module.rules {
            guard let resolved = resolver.resolvedClass(for: rule) else { continue }
            if !resolver.customProperties(for: rule, bases: resolved.bases).isEmpty {
                types.insert(KvPropertyType.objectProperty.rawValue)
            }
        }
        return types
    }
    
    /// An import for each `#:import` alias the generated code actually reads.
    ///
    /// `#:import get_font_name carbonkivy.utils.get_font_name` becomes
    /// `from carbonkivy.utils import get_font_name`. The last segment may name
    /// a module or an attribute of one; `from parent import last` covers both.
    func directiveImports() -> [Statement] {
        let directives = context.directives
        let used = context.metrics.names
        var statements: [Statement] = []
        
        // `#:from pkg.mod import name as alias` is already an import statement.
        for alias in directives.fromImports.keys.sorted() where used.contains(alias) {
            guard let (module, name) = directives.fromImports[alias] else { continue }
            statements.append(Py.importFrom(module, [Alias(name: name, asName: alias == name ? nil : alias)]))
        }
        
        for alias in directives.imports.keys.sorted() where used.contains(alias) {
            guard let package = directives.imports[alias] else { continue }
            
            let parts = package.split(separator: ".").map(String.init)
            guard let last = parts.last else { continue }
            
            if parts.count == 1 {
                statements.append(Py.import([Alias(name: package, asName: alias == package ? nil : alias)]))
            } else {
                statements.append(Py.importFrom(
                    parts.dropLast().joined(separator: "."),
                    [Alias(name: last, asName: alias == last ? nil : alias)]
                ))
            }
        }
        return statements
    }
    
    /// `from kivy.metrics import dp, sp` for the helpers the values used.
    var metricsImport: Statement? {
        let used = context.metrics.used
        guard !used.isEmpty else { return nil }
        return Py.importFrom("kivy.metrics", used.sorted().map { Alias(name: $0, asName: nil) })
    }
    
    var factoryImport: Statement {
        Py.importFrom("kivy.factory", [Alias(name: "Factory", asName: nil)])
    }
    
    var globalIdmapImport: Statement {
        Py.importFrom("kivy.lang.parser", [Alias(name: "global_idmap", asName: nil)])
    }
}
