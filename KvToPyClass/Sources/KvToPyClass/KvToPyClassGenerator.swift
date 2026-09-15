import Foundation
import KvParser
import PySwiftAST
import PySwiftCodeGen
import PyFormatters

/// Generates Python class code from KV language rules.
///
/// Kivy's Builder dynamically applies KV rules to widgets at runtime. This
/// generator instead creates equivalent Python class definitions that
/// produce the same widget tree structure and property bindings.
///
/// The work is done by the generators in `Generators/`, one per kind of
/// output; this is the entry point that sets them up and formats the result.
public struct KvToPyClassGenerator {
    
    private let module: KvModule
    private let pythonClasses: [PythonClassInfo]
    private let existingBody: [Statement]
    private let directives: KvDirectives
    
    /// Generator dialect from `#:mode`, the file's own directive winning over
    /// a shared one.
    public var mode: String { directives.mode }
    
    /// `#:set name value` directives, which KV treats as globals.
    var constants: [String: String] { directives.constants }

    public init(
        module: KvModule,
        pythonClasses: [PythonClassInfo] = [],
        existingBody: [Statement] = [],
        sharedDirectives: [KvDirective] = []
    ) {
        self.module = module
        self.pythonClasses = pythonClasses
        self.existingBody = existingBody
        self.directives = KvDirectives(own: module.directives, shared: sharedDirectives)
    }

    public init(module: KvModule, existing: PythonModuleInfo, sharedDirectives: [KvDirective] = []) {
        self.init(
            module: module,
            pythonClasses: existing.classes,
            existingBody: existing.body,
            sharedDirectives: sharedDirectives
        )
    }
    
    /// Generate Python code for all dynamic classes and rules.
    public func generate() throws -> String {
        let context = GenerationContext(
            module: module,
            pythonClasses: pythonClasses,
            existingBody: existingBody,
            directives: directives
        )
        // Kept alive for the whole run: every generator holds it unowned.
        let generators = KvGenerators(context: context)
        let pyModule = try generators.module.module()
        
        // Black for the blank lines between definitions, then source text.
        let formatted = BlackFormatter().formatDeep(pyModule)
        return PySwiftCodeGen.generatePythonCode(from: formatted)
    }
}
