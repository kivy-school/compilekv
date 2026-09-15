//
//  StatementQueries.swift
//  KvToPyClass
//
//  Questions about a Python body that the mergers ask: which names it
//  binds, which it imports, and which generated lines it already has.

import PySwiftAST

enum StatementQueries {
    
    /// Module level names bound by a plain assignment or a class definition.
    static func assignedNames(in body: [Statement]) -> Swift.Set<String> {
        var names = Swift.Set<String>()
        for statement in body {
            switch statement {
            case .assign(let assign):
                for target in assign.targets {
                    if case .name(let name) = target { names.insert(name.id) }
                }
            case .classDef(let classDef):
                names.insert(classDef.name)
            case .functionDef(let funcDef):
                names.insert(funcDef.name)
            case .typeAlias(let alias):
                if case .name(let name) = alias.name { names.insert(name.id) }
            default:
                break
            }
        }
        return names
    }
    
    /// Names bound by a plain assignment, annotation, def or class.
    static func boundNames(in body: [Statement]) -> Swift.Set<String> {
        var names = assignedNames(in: body)
        for statement in body {
            if case .annAssign(let annotated) = statement, case .name(let target) = annotated.target {
                names.insert(target.id)
            }
        }
        return names
    }
    
    /// Every module level name an import statement binds, so we do not add an
    /// import for something the file already brings in (under any alias).
    static func importedNames(in body: [Statement]) -> Swift.Set<String> {
        var names = Swift.Set<String>()
        for statement in body {
            switch statement {
            case .importStmt(let node):
                for alias in node.names {
                    names.insert(alias.asName ?? alias.name.split(separator: ".").first.map(String.init) ?? alias.name)
                }
            case .importFrom(let node):
                for alias in node.names {
                    names.insert(alias.asName ?? alias.name)
                }
            default:
                break
            }
        }
        return names
    }
    
    /// Keys the file already publishes as `global_idmap["key"] = ...`.
    static func idmapKeys(in body: [Statement]) -> Swift.Set<String> {
        var keys = Swift.Set<String>()
        for statement in body {
            guard case .assign(let assign) = statement,
                  case .subscriptExpr(let target) = assign.targets.first,
                  case .name(let object) = target.value,
                  object.id == "global_idmap",
                  case .constant(let key) = target.slice,
                  case .string(let name) = key.value
            else { continue }
            keys.insert(name)
        }
        return keys
    }
    
    /// Names the file already passes to Factory.register, under any spelling
    /// of the first argument.
    static func factoryRegistrations(in body: [Statement]) -> Swift.Set<String> {
        var names = Swift.Set<String>()
        for statement in body {
            guard case .expr(let expr) = statement,
                  case .call(let call) = expr.value,
                  case .attribute(let callee) = call.fun,
                  callee.attr == "register",
                  case .name(let target) = callee.value,
                  target.id == "Factory",
                  let first = call.args.first,
                  case .constant(let constant) = first,
                  case .string(let name) = constant.value
            else { continue }
            names.insert(name)
        }
        return names
    }
    
    /// `self._bindings = []`
    static func isBindingsInit(_ statement: Statement) -> Bool {
        guard case .assign(let assign) = statement,
              case .attribute(let target) = assign.targets.first,
              target.attr == "_bindings",
              case .name(let object) = target.value,
              object.id == "self"
        else { return false }
        return true
    }
    
    /// `super().__init__(...)`
    static func isSuperInit(_ statement: Statement) -> Bool {
        guard case .expr(let expr) = statement,
              case .call(let call) = expr.value,
              case .attribute(let callee) = call.fun,
              callee.attr == "__init__",
              case .call(let inner) = callee.value,
              case .name(let superName) = inner.fun,
              superName.id == "super"
        else { return false }
        return true
    }
    
    static func isStringConstant(_ expr: Expression) -> Bool {
        guard case .constant(let constant) = expr, case .string = constant.value else { return false }
        return true
    }
}
