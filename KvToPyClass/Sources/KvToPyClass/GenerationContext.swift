//
//  GenerationContext.swift
//  KvToPyClass
//

import KvParser
import PySwiftAST

/// Everything the generators share for one run: the parsed input, the
/// existing Python, the directives, and the mutable state of where in the
/// output generation currently is.
final class GenerationContext {
    let module: KvModule
    let pythonClasses: [PythonClassInfo]
    /// Body of the existing .py file, if one was supplied. Generated code is
    /// merged into this rather than replacing it.
    let existingBody: [Statement]
    let directives: KvDirectives
    let dialect: any WidgetDialect
    
    let metrics = MetricsCollector()
    let names = NameCounter()
    /// The class being generated.
    let rule = RuleContext()
    /// The widget KV's `self` means right now.
    let selfScope = SelfContext()
    
    init(module: KvModule, pythonClasses: [PythonClassInfo], existingBody: [Statement], directives: KvDirectives) {
        self.module = module
        self.pythonClasses = pythonClasses
        self.existingBody = existingBody
        self.directives = directives
        self.dialect = (KvMode(rawValue: directives.mode) ?? .default).dialect
    }
    
    func pythonClass(named name: String) -> PythonClassInfo? {
        pythonClasses.first { $0.name == name }
    }
    
    /// Start a new class: fresh numbering, `self` back to the rule root.
    func enter(_ pyClass: KvPyClass) {
        names.reset()
        selfScope.name = "self"
        selfScope.widgetType = nil
        rule.enter(pyClass)
    }
}
