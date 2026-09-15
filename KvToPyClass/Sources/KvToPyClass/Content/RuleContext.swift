//
//  RuleContext.swift
//  KvToPyClass
//

import KvParser
import PySwiftAST

/// The class currently being generated, kept where the deep helpers can
/// reach it without every signature carrying the rule through.
final class RuleContext {
    /// Nothing until a class is entered; `pyClass` traps before that, which
    /// is a bug in the caller, not a state worth handling.
    private(set) var current: KvPyClass?
    var pyClass: KvPyClass { current! }
    
    /// Methods the conditional blocks of this rule produced, in order.
    var conditionalMethods: [Statement] = []
    /// Reset methods of those blocks, so `__del__` can tear them down.
    var conditionalResets: [String] = []
    /// Function name of each `name: |` value block, keyed by line and name.
    var blockFunctions: [String: String] = [:]
    private var conditionalCount = 0

    func nextConditionalIndex() -> Int {
        defer { conditionalCount += 1 }
        return conditionalCount
    }

    func enter(_ pyClass: KvPyClass) {
        current = pyClass
        conditionalMethods = []
        conditionalResets = []
        blockFunctions = [:]
        conditionalCount = 0
    }
}

extension RuleContext {
    /// The function a value block is wrapped in. One name per block, so the
    /// definition and the bindings that call it agree.
    func valueBlockName(_ property: KvProperty, counter: NameCounter) -> String {
        let key = "\(property.line):\(property.name)"
        if let name = blockFunctions[key] { return name }
        let name = "_value_\(counter.take())"
        blockFunctions[key] = name
        return name
    }
}
