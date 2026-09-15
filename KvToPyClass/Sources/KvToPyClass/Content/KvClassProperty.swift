//
//  KvClassProperty.swift
//  KvToPyClass
//
//  Created by CodeBuilder on 12/09/2026.
//

import KvParser
import KivyWidgetRegistry
import PySwiftAST
import Foundation

/// A Kivy property declared on a generated class. Each property type is its
/// own class, so what differs between them is answered by the type rather
/// than by a switch at every call site.
public protocol KvPropertyProtocol: AnyObject, Identifiable, Sendable {
    var id: Int { get }
    var type: KvPropertyType { get }
    var name: String { get set }
    var owner: String { get set }
    
    /// Can a bare word assigned to this property be a string literal?
    /// `orientation: vertical` is a sloppy literal; `width: vertical` is not.
    var holdsString: Bool { get }
    
    init(id: Int, name: String, owner: String)
}

extension KvPropertyProtocol {
    public var holdsString: Bool { false }
    
    static func new(name: String, owner: KvPyClass) -> Self {
        new(name: name, owner: owner.name)
    }
    
    static func new(name: String, owner: String) -> Self {
        .init(id: UUID().hashValue, name: name, owner: owner)
    }
    
    /// `name = Type(default)` -- the class level declaration.
    func declaration(default value: Expression) -> Statement {
        Py.assign(name, Py.call(type.rawValue, [value]))
    }
}


/// Kivy property types
public enum KvPropertyType: String, Equatable, Hashable, Sendable {
    case numericProperty = "NumericProperty"
    case stringProperty = "StringProperty"
    case listProperty = "ListProperty"
    case objectProperty = "ObjectProperty"
    case booleanProperty = "BooleanProperty"
    case dictProperty = "DictProperty"
    case optionProperty = "OptionProperty"
    case referenceListProperty = "ReferenceListProperty"
    case aliasProperty = "AliasProperty"
    case boundedNumericProperty = "BoundedNumericProperty"
    case variableListProperty = "VariableListProperty"
    case colorProperty = "ColorProperty"
    
    case environmentProperty = "EnvironmentProperty"
    
    /// The registry's view of the same type.
    public init(_ type: KivyPropertyType) {
        self.init(rawValue: type.rawValue)!
    }
    
    /// The class that models this type; the one table the enum keeps.
    var propertyClass: any KvPropertyProtocol.Type {
        switch self {
        case .numericProperty: NumericProperty.self
        case .stringProperty: StringProperty.self
        case .listProperty: ListProperty.self
        case .objectProperty: ObjectProperty.self
        case .booleanProperty: BooleanProperty.self
        case .dictProperty: DictProperty.self
        case .optionProperty: OptionProperty.self
        case .referenceListProperty: ReferenceListProperty.self
        case .aliasProperty: AliasProperty.self
        case .boundedNumericProperty: BoundedNumericProperty.self
        case .variableListProperty: VariableListProperty.self
        case .colorProperty: ColorProperty.self
        case .environmentProperty: EnvironmentProperty.self
        }
    }
}

public final class NumericProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .numericProperty
    public var name: String
    public var owner: String
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class StringProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .stringProperty
    public var name: String
    public var owner: String
    public var holdsString: Bool { true }
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class ListProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .listProperty
    public var name: String
    public var owner: String
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class ObjectProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .objectProperty
    public var name: String
    public var owner: String
    public var holdsString: Bool { true }
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class BooleanProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .booleanProperty
    public var name: String
    public var owner: String
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class DictProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .dictProperty
    public var name: String
    public var owner: String
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class OptionProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .optionProperty
    public var name: String
    public var owner: String
    public var holdsString: Bool { true }
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class ReferenceListProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .referenceListProperty
    public var name: String
    public var owner: String
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class AliasProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .aliasProperty
    public var name: String
    public var owner: String
    public var holdsString: Bool { true }
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class BoundedNumericProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .boundedNumericProperty
    public var name: String
    public var owner: String
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class VariableListProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .variableListProperty
    public var name: String
    public var owner: String
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class ColorProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .colorProperty
    public var name: String
    public var owner: String
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}

public final class EnvironmentProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    public let type: KvPropertyType = .environmentProperty
    public var name: String
    public var owner: String
    
    public init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}


/// A declared property, wrapped so a list of them can be stored and matched
/// on; `base` is the protocol view for everything else.
public enum KvClassProperty {
    case numericProperty(NumericProperty)
    case stringProperty(StringProperty)
    case listProperty(ListProperty)
    case objectProperty(ObjectProperty)
    case booleanProperty(BooleanProperty)
    case dictProperty(DictProperty)
    case optionProperty(OptionProperty)
    case referenceListProperty(ReferenceListProperty)
    case aliasProperty(AliasProperty)
    case boundedNumericProperty(BoundedNumericProperty)
    case variableListProperty(VariableListProperty)
    case colorProperty(ColorProperty)
    
    case environmentProperty(EnvironmentProperty)
}

extension KvClassProperty {
    public var base: any KvPropertyProtocol {
        switch self {
        case .numericProperty(let property): property
        case .stringProperty(let property): property
        case .listProperty(let property): property
        case .objectProperty(let property): property
        case .booleanProperty(let property): property
        case .dictProperty(let property): property
        case .optionProperty(let property): property
        case .referenceListProperty(let property): property
        case .aliasProperty(let property): property
        case .boundedNumericProperty(let property): property
        case .variableListProperty(let property): property
        case .colorProperty(let property): property
        case .environmentProperty(let property): property
        }
    }
    
    public var name: String { base.name }
    public var type: KvPropertyType { base.type }
    
    static func make(_ type: KvPropertyType, name: String, owner: String) -> KvClassProperty {
        switch type {
        case .aliasProperty: .aliasProperty(.new(name: name, owner: owner))
        case .booleanProperty: .booleanProperty(.new(name: name, owner: owner))
        case .boundedNumericProperty: .boundedNumericProperty(.new(name: name, owner: owner))
        case .colorProperty: .colorProperty(.new(name: name, owner: owner))
        case .dictProperty: .dictProperty(.new(name: name, owner: owner))
        case .environmentProperty: .environmentProperty(.new(name: name, owner: owner))
        case .listProperty: .listProperty(.new(name: name, owner: owner))
        case .numericProperty: .numericProperty(.new(name: name, owner: owner))
        case .objectProperty: .objectProperty(.new(name: name, owner: owner))
        case .optionProperty: .optionProperty(.new(name: name, owner: owner))
        case .referenceListProperty: .referenceListProperty(.new(name: name, owner: owner))
        case .stringProperty: .stringProperty(.new(name: name, owner: owner))
        case .variableListProperty: .variableListProperty(.new(name: name, owner: owner))
        }
    }
    
    /// From a class level `name = SomeProperty(...)`; nil for anything else.
    static func fromAssign(_ assign: Assign, owner: String) -> Self? {
        guard case .name(let target) = assign.targets.first,
              case .call(let call) = assign.value,
              case .name(let callee) = call.fun,
              let type = KvPropertyType(rawValue: callee.id)
        else { return nil }
        return make(type, name: target.id, owner: owner)
    }
}
