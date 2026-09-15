//
//  BindingInfo.swift
//  KvToPyClass
//

import PySwiftAST

/// A callback bound in generated code, kept so it can be unbound again.
struct BindingInfo {
    let key: BindableKey
    /// The local the callback was assigned to, e.g. `_callback_0`.
    let callback: String
    
    init(key: BindableKey, callback: String) {
        self.key = key
        self.callback = callback
    }
    
    init(source: String, property: String, callback: String) {
        self.init(key: BindableKey(source, property), callback: callback)
    }
    
    /// `(obj, "prop", callback)` -- the entry a bindings list holds.
    var tuple: Expression {
        Py.tuple([Py.name(key.source.name), Py.string(key.property), Py.name(callback)])
    }
}
