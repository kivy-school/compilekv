//
//  KvPyClass.swift
//  KvToPyClass
//

import KvParser
import PySwiftAST
import Foundation

/// The Python class one KV rule becomes: what it is called, what it
/// inherits, the hand-written class it extends (if any) and the properties
/// the generators need to know about.
public final class KvPyClass {
    
    let name: String
    let bases: [String]
    let rule: KvRule
    /// The class the .py already has under this name, which the generated
    /// members are merged into.
    let existing: PythonClassInfo?
    /// Properties the rule assigns or watches that no base provides. Kivy's
    /// Builder would create them on the fly; here they are declared.
    let customProperties: Swift.Set<String>
    /// Every id the rule's own widget tree declares, at any depth.
    let ids: Swift.Set<String>
    /// Kivy properties the existing class declares at class level.
    let properties: [KvClassProperty]
    
    init(
        name: String,
        bases: [String],
        rule: KvRule,
        existing: PythonClassInfo?,
        customProperties: Swift.Set<String>,
        ids: Swift.Set<String>
    ) {
        self.name = name
        self.bases = bases
        self.rule = rule
        self.existing = existing
        self.customProperties = customProperties
        self.ids = ids
        self.properties = (existing?.classDefAST.body ?? []).compactMap { statement in
            guard case .assign(let assign) = statement else { return nil }
            return KvClassProperty.fromAssign(assign, owner: name)
        }
    }
    
    /// Names `self.x` can bind to: whatever the .py declares as a Kivy
    /// property, plus the ones this rule declares itself.
    var selfProperties: Swift.Set<String> {
        Swift.Set(existing?.kivyProperties.keys ?? [:].keys).union(customProperties)
    }
    
    func property(named name: String) -> KvClassProperty? {
        properties.first { $0.name == name }
    }
    
    /// Does the rule do anything that needs an `__init__`?
    var needsInit: Bool {
        !rule.properties.isEmpty || !rule.children.isEmpty
            || !CanvasLayer.layers(of: rule.body).isEmpty || !rule.conditionals.isEmpty
    }
}
