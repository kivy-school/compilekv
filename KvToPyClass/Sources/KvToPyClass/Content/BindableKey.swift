//
//  BindableKey.swift
//  KvToPyClass
//
//  Created by CodeBuilder on 12/09/2026.
//

import PySwiftAST

/// One `object.property` a value watches, resolved to what the generated
/// code calls the object and checked to be a real Kivy property.
public struct BindableKey: Hashable, Sendable {
    public let source: BindingSource
    public let property: String
    
    public init(source: BindingSource, property: String) {
        self.source = source
        self.property = property
    }
    
    init(_ source: String, _ property: String) {
        self.init(source: BindingSource(source), property: property)
    }
    
    /// From the parser's `[object, attribute]` pair; nil for anything else.
    init?(_ pair: [String]) {
        guard pair.count == 2 else { return nil }
        self.init(pair[0], pair[1])
    }
    
    /// `object.bind(property=callback)`
    func bind(_ callback: String) -> Statement {
        Py.expr(Py.method(source.name, "bind", keywords: [Py.keyword(property, Py.name(callback))]))
    }
    
    /// `object.bind(property=target.setter("name"))`
    func bindSetter(of target: String, _ name: String) -> Statement {
        Py.expr(Py.method(source.name, "bind", keywords: [
            Py.keyword(property, Py.method(target, "setter", [Py.string(name)]))
        ]))
    }
}
