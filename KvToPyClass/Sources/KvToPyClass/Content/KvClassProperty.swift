//
//  KvProperty.swift
//  KvToPyClass
//
//  Created by CodeBuilder on 12/09/2026.
//

import KvParser

public protocol KvPropertyProtocol: AnyObject, Identifiable, Sendable {
    var id: Int { get }
    var type: KvPropertyType { get }
    var name: String { get set }
    var owner: String { get set }
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
}

public final class NumericProperty: KvPropertyProtocol, @unchecked Sendable {
    public let id: Int
    
    public let type: KvPropertyType = .numericProperty
    
    public var name: String
    
    public var owner: String
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
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
    
    init(id: Int, name: String, owner: String) {
        self.id = id
        self.name = name
        self.owner = owner
    }
}



