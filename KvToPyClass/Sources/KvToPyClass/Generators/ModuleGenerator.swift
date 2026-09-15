//
//  ModuleGenerator.swift
//  KvToPyClass
//

import PySwiftAST

/// The whole output file: imports, Factory aliases, published constants,
/// one class per rule and the registrations, laid out fresh or folded into
/// the .py that already exists.
final class ModuleGenerator: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    func module() throws -> Module {
        let analysis = generators.analysis
        let imports = generators.imports
        let factory = generators.factory
        
        // Three kinds of widget name: one this module defines, which needs
        // nothing; one Kivy ships, which gets imported; and anything else,
        // which is a custom widget from somewhere we cannot see and so comes
        // off the Factory.
        let referenced = analysis.widgetTypes().filter { !resolver.isDefinedHere($0) }
        let external = referenced.filter { !context.dialect.widgetExists($0) }
        
        var classes: [Statement] = []
        for rule in context.module.rules {
            if let pyClass = generators.classes.pyClass(for: rule) {
                classes.append(try generators.classes.classDef(for: pyClass))
            }
        }
        
        let registrations = factory.registrations(for: classes)
        let needsFactory = !external.isEmpty || !registrations.isEmpty
        
        // A `#:set` is substituted into this file's own code, but KV files
        // loaded later still expect the name, so publish it too. Built before
        // the imports below, because a published value can be the only thing
        // in the file that uses dp() or sp().
        let idmap = factory.globalIdmapAssignments()
        
        var importStatements = imports.widgetImports(for: referenced.subtracting(external))
        importStatements.append(contentsOf: imports.directiveImports())
        if !idmap.isEmpty {
            importStatements.append(imports.globalIdmapImport)
        }
        // Populated while the classes above and the values above were built.
        if let metrics = imports.metricsImport {
            importStatements.append(metrics)
        }
        if needsFactory {
            importStatements.append(imports.factoryImport)
        }
        
        let aliases = external.sorted().map(factory.alias)
        
        let statements = generators.moduleMerger.assemble(
            imports: importStatements,
            aliases: aliases,
            idmap: idmap,
            classes: classes,
            registrations: registrations,
            into: context.existingBody
        )
        return Module.module(statements)
    }
}
