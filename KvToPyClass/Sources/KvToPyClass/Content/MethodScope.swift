//
//  MethodScope.swift
//  KvToPyClass
//

import PySwiftAST

/// The body of one generated method as it is being built: its statements,
/// the callbacks it bound, and the counter that names them.
///
/// Callback numbering restarts per method, since each method is its own
/// Python scope; the conditional generator opens a fresh one for each block.
final class MethodScope {
    fileprivate(set) var statements: [Statement] = []
    private(set) var bindings: [BindingInfo] = []
    private var callbackCount = 0
    
    func emit(_ statement: Statement) {
        statements.append(statement)
    }
    
    func emit(_ statements: [Statement]) {
        self.statements.append(contentsOf: statements)
    }
    
    func track(_ binding: BindingInfo) {
        bindings.append(binding)
    }
    
    func track(_ bindings: [BindingInfo]) {
        self.bindings.append(contentsOf: bindings)
    }
    
    /// Hand over the bindings tracked so far, so a caller can record them
    /// somewhere other than `self._bindings`.
    func takeBindings() -> [BindingInfo] {
        defer { bindings = [] }
        return bindings
    }
    
    /// A fresh `_callback_N` local.
    func nextCallback() -> String {
        defer { callbackCount += 1 }
        return "_callback_\(callbackCount)"
    }
}

extension MethodScope {
    /// Run `body` with what it emits captured instead of appended, so the
    /// statements can be placed elsewhere. Callbacks it names and bindings
    /// it tracks still belong to this scope.
    func capture(_ body: () throws -> Void) rethrows -> [Statement] {
        let enclosing = statements
        statements = []
        defer { statements = enclosing }
        try body()
        return statements
    }
}
