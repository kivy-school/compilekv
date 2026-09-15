//
//  KvDirectives.swift
//  KvToPyClass
//

import KvParser

/// What the `#:` directives of a file, and of the files it shares them with,
/// mean to the generator.
struct KvDirectives {
    /// `#:set name value`, which KV treats as globals. Builder substitutes
    /// them at load time; generated Python has no Builder, so they are
    /// substituted here.
    let constants: [String: String]
    /// The `#:set` names this file declares, as opposed to ones it merely uses.
    let declaredConstants: [String: String]
    /// `#:import alias package.path`, which KV resolves into its own
    /// namespace. Generated Python needs a real import for each one it uses.
    let imports: [String: String]
    /// `#:from module import name [as alias]`, keyed by the name KV code uses.
    let fromImports: [String: (module: String, name: String)]
    /// Generator dialect from `#:mode`, the file's own directive winning over
    /// a shared one.
    let mode: String
    
    /// Shared first, so a `#:set` in this file overrides the same name from
    /// another one.
    init(own: [KvDirective], shared: [KvDirective] = []) {
        var constants: [String: String] = [:]
        var imports: [String: String] = [:]
        var fromImports: [String: (module: String, name: String)] = [:]
        var mode = KvMode.default.rawValue
        for directive in shared + own {
            switch directive {
            case .set(let name, let value, _):
                constants[name] = value
            case .import(let alias, let package, _):
                imports[alias] = package
            case .from(let module, let name, let alias, _):
                fromImports[alias ?? name] = (module, name)
            case .mode(let name, _):
                mode = name
            default:
                break
            }
        }
        self.constants = constants
        self.imports = imports
        self.fromImports = fromImports
        self.mode = mode
        
        var declared: [String: String] = [:]
        for directive in own {
            if case .set(let name, let value, _) = directive {
                declared[name] = value
            }
        }
        self.declaredConstants = declared
    }
}
