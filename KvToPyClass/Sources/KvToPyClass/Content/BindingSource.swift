//
//  BindingSource.swift
//  KvToPyClass
//

/// The object a bound value reads from, as it is named in generated code.
public enum BindingSource: Hashable, Sendable {
    case `self`
    case app
    /// An id, a child widget's local, or `parent` inside a conditional.
    case other(String)
    
    public init(_ name: String) {
        switch name {
        case "self": self = .self
        case "app": self = .app
        default: self = .other(name)
        }
    }
}

extension BindingSource {
    var name: String {
        switch self {
        case .self:
            "self"
        case .app:
            "app"
        case .other(let string):
            string
        }
    }
}
