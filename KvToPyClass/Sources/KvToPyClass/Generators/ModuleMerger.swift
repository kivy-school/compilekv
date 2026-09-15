//
//  ModuleMerger.swift
//  KvToPyClass
//

import PySwiftAST

/// Lays the generated pieces out as a module, either on their own or folded
/// into the body of the .py that was there already.
final class ModuleMerger: KvGenerator {
    unowned let generators: KvGenerators
    
    init(_ generators: KvGenerators) {
        self.generators = generators
    }
    
    func assemble(
        imports: [Statement],
        aliases: [Statement],
        idmap: [Statement],
        classes: [Statement],
        registrations: [Statement],
        into existing: [Statement]
    ) -> [Statement] {
        if existing.isEmpty {
            return separateImportBlock(
                in: imports + aliases + idmap + classes + registrations,
                endingAt: imports.count
            )
        }
        return merge(
            imports: imports,
            aliases: aliases + idmap,
            classes: classes,
            registrations: registrations,
            into: existing
        )
    }
    
    /// Fold generated imports and classes into the body of the existing .py.
    ///
    /// Imports land after the ones already there, classes replace the
    /// same-named definition in place, and everything else the file had --
    /// docstring, constants, helper functions, unrelated classes -- is left
    /// exactly where the author put it.
    private func merge(
        imports: [Statement],
        aliases: [Statement],
        classes: [Statement],
        registrations: [Statement],
        into body: [Statement]
    ) -> [Statement] {
        let alreadyBound = StatementQueries.importedNames(in: body)
        let newImports = imports.compactMap { dropAliases(boundIn: alreadyBound, from: $0) }
        
        // A Factory alias is only needed for a name the file does not already
        // bind, whether by import, assignment or class definition.
        let boundAtModuleLevel = alreadyBound.union(StatementQueries.assignedNames(in: body))
        let published = StatementQueries.idmapKeys(in: body)
        let newAliases = aliases.filter { statement in
            guard case .assign(let assign) = statement, let target = assign.targets.first else {
                return true
            }
            switch target {
            case .name(let name):
                return !boundAtModuleLevel.contains(name.id)
            case .subscriptExpr(let subscriptNode):
                // global_idmap["x"] = ... that is already there.
                guard case .constant(let key) = subscriptNode.slice,
                      case .string(let name) = key.value
                else { return true }
                return !published.contains(name)
            default:
                return true
            }
        }
        
        var generated: [String: Statement] = [:]
        for statement in classes {
            if case .classDef(let classDef) = statement {
                generated[classDef.name] = statement
            }
        }
        
        var result: [Statement] = []
        var used = Swift.Set<String>()
        for statement in body {
            if case .classDef(let classDef) = statement,
               let replacement = generated[classDef.name] {
                result.append(replacement)
                used.insert(classDef.name)
            } else {
                result.append(statement)
            }
        }
        
        // Rules with no matching class in the file are appended in KV order.
        for statement in classes {
            if case .classDef(let classDef) = statement, !used.contains(classDef.name) {
                result.append(statement)
            }
        }
        
        // Registrations name the classes, so they go last.
        result.append(contentsOf: registrations)
        
        let insertAt = importInsertionPoint(in: result)
        result.insert(contentsOf: newImports + newAliases, at: insertAt)
        return separateImportBlock(in: result, endingAt: insertAt + newImports.count + newAliases.count)
    }
    
    /// One blank line after the imports. BlackFormatter only spaces defs and
    /// classes, so without this a following constant butts up against them.
    private func separateImportBlock(in body: [Statement], endingAt index: Int) -> [Statement] {
        guard index > 0, index < body.count else { return body }
        switch body[index] {
        case .blank, .classDef, .functionDef, .asyncFunctionDef:
            return body
        default:
            var spaced = body
            spaced.insert(.blank(1), at: index)
            return spaced
        }
    }
    
    /// Strip aliases already bound; returns nil when nothing is left to import.
    private func dropAliases(boundIn bound: Swift.Set<String>, from statement: Statement) -> Statement? {
        guard case .importFrom(let node) = statement else { return statement }
        let keep = node.names.filter { !bound.contains($0.asName ?? $0.name) }
        if keep.isEmpty { return nil }
        if keep.count == node.names.count { return statement }
        return .importFrom(ImportFrom(
            module: node.module,
            names: keep,
            level: node.level,
            lineno: node.lineno,
            colOffset: node.colOffset,
            endLineno: nil,
            endColOffset: nil
        ))
    }
    
    /// Just after the file's existing imports, or after its docstring.
    private func importInsertionPoint(in body: [Statement]) -> Int {
        var index = 0
        for (offset, statement) in body.enumerated() {
            switch statement {
            case .importStmt, .importFrom:
                index = offset + 1
            case .expr(let expr) where offset == 0:
                if case .constant(let constant) = expr.value, case .string = constant.value {
                    index = 1
                }
            case .blank:
                continue
            default:
                break
            }
        }
        return index
    }
}
