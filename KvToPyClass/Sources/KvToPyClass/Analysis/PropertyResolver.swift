//
//  PropertyResolver.swift
//  KvToPyClass
//

import KivyWidgetRegistry
import KvParser

/// Answers what a rule's class is, which of its names are Kivy properties,
/// and therefore which watched keys can actually be bound.
final class PropertyResolver {
    private let context: GenerationContext
    
    init(context: GenerationContext) {
        self.context = context
    }
    
    private var dialect: any WidgetDialect { context.dialect }
    
    // MARK: Classes
    
    /// The class a rule defines and what it inherits from.
    ///
    /// A `<Name>:` rule styles a class that already exists in Python, so its
    /// bases come from that file; `<Name@Base>:` declares them inline. Falling
    /// back to `Widget` matches what Kivy's own Builder does.
    func resolvedClass(for rule: KvRule) -> (name: String, bases: [String])? {
        switch rule.selector {
        case .dynamicClass(let name, let bases):
            if let pythonClass = context.pythonClass(named: name), !pythonClass.baseClasses.isEmpty {
                return (name, pythonClass.baseClasses)
            }
            return (name, bases.isEmpty ? ["Widget"] : bases)
        case .name(let name):
            if let pythonClass = context.pythonClass(named: name), !pythonClass.baseClasses.isEmpty {
                return (name, pythonClass.baseClasses)
            }
            return (name, ["Widget"])
        case .className, .multiple:
            return nil
        }
    }
    
    /// The rule that generates a class by this name, if any.
    func rule(generating name: String) -> KvRule? {
        context.module.rules.first { resolvedClass(for: $0)?.name == name }
    }
    
    /// Is this name a class the generated module defines, or one already in
    /// the .py we are extending?
    func isDefinedHere(_ name: String) -> Bool {
        context.pythonClass(named: name) != nil || rule(generating: name) != nil
    }
    
    /// Properties the rule assigns or watches that no base class provides.
    func customProperties(for rule: KvRule, bases: [String]) -> Swift.Set<String> {
        func providedByABase(_ name: String) -> Bool {
            bases.contains { dialect.propertyType(name, on: $0) != nil }
        }
        
        var custom = Swift.Set<String>()
        for property in rule.properties where ValueParser.needsBinding(property) {
            if !providedByABase(property.name) {
                custom.insert(property.name)
            }
        }
        
        // A value can only re-evaluate when what it watches is a property,
        // so `text: self.state` and `if self.state:` declare `state` too.
        for name in Self.watchedRuleProperties(rule) where !providedByABase(name) {
            custom.insert(name)
        }
        return custom
    }
    
    /// Names watched on the rule root -- `self.x` where `self` is the root,
    /// `root.x` anywhere -- that have to be properties for that to work.
    ///
    /// Kivy's Builder turns an unknown name a rule assigns into a property
    /// (`create_property`), so a watched name the rule assigns is one here
    /// too. A name the rule does not assign is left alone: it belongs to the
    /// hand written class, where it may well be a plain attribute. A
    /// condition is the exception, since a block that never re-evaluates
    /// is not worth having.
    static func watchedRuleProperties(_ rule: KvRule) -> Swift.Set<String> {
        var names = Swift.Set<String>()
        let assigned = Swift.Set(rule.properties.map(\.name))
        
        func note(_ keys: [[String]]?, selfIsRoot: Bool, always: Bool = false) {
            for key in keys ?? [] where key.count == 2 {
                if key[0] == "root" || (key[0] == "self" && selfIsRoot),
                   always || assigned.contains(key[1]) {
                    names.insert(key[1])
                }
            }
        }
        func visit(_ body: KvBody, selfIsRoot: Bool) {
            for property in body.properties {
                note(property.watchedKeys, selfIsRoot: selfIsRoot)
            }
            for (_, canvas) in CanvasLayer.layers(of: body) {
                for property in canvas.instructions.flatMap(\.properties) {
                    note(property.watchedKeys, selfIsRoot: selfIsRoot)
                }
            }
            for child in body.children {
                visit(child.body, selfIsRoot: false)
            }
            for conditional in body.conditionals {
                if case .if(_, let keys) = conditional.kind {
                    note(keys, selfIsRoot: selfIsRoot, always: true)
                }
                visit(conditional.body, selfIsRoot: selfIsRoot)
                if let elseBody = conditional.elseBody {
                    visit(elseBody, selfIsRoot: selfIsRoot)
                }
            }
        }
        
        visit(rule.body, selfIsRoot: true)
        return names
    }
    
    // MARK: Property Types
    
    /// Can the property named here hold a string? A bare word assigned to a
    /// numeric or colour property is never a string literal; a property we
    /// know nothing about might as well be able to.
    func holdsString(_ propertyName: String) -> Bool {
        declaredProperty(named: propertyName)?.base.holdsString ?? true
    }
    
    /// The declared property on whatever the value is being assigned to: the
    /// child widget whose block we are in, or the rule's own class.
    func declaredProperty(named name: String) -> KvClassProperty? {
        if let widgetType = context.selfScope.widgetType {
            return declaredProperty(named: name, on: widgetType, depth: 0)
        }
        // The rule's own class first: it may declare the property itself.
        let pyClass = context.rule.pyClass
        if let property = declaredProperty(named: name, on: pyClass.name, depth: 0) {
            return property
        }
        for base in pyClass.bases {
            if let property = declaredProperty(named: name, on: base, depth: 0) { return property }
        }
        return nil
    }
    
    private func declaredProperty(named name: String, on owner: String, depth: Int) -> KvClassProperty? {
        guard depth < 8 else { return nil }
        
        // The class being generated knows its own declarations. Any other
        // class in the .py is read by name; a property type we do not model
        // is still a property, just not one a bare word can be assigned to.
        if let pyClass = context.rule.current, pyClass.name == owner, let property = pyClass.property(named: name) {
            return property
        }
        if let declared = context.pythonClass(named: owner)?.kivyProperties[name] {
            return KvPropertyType(rawValue: declared).map { .make($0, name: name, owner: owner) }
        }
        if let type = dialect.propertyType(name, on: owner) {
            return .make(KvPropertyType(type), name: name, owner: owner)
        }
        
        // Not a Kivy widget: follow whatever it inherits from.
        let bases = context.pythonClass(named: owner)?.baseClasses
            ?? rule(generating: owner).flatMap { resolvedClass(for: $0)?.bases }
            ?? []
        for base in bases where base != owner {
            if let property = declaredProperty(named: name, on: base, depth: depth + 1) { return property }
        }
        return nil
    }
    
    // MARK: Bindability
    
    /// Watched keys with `root` renamed to `self`, dropping the ones that are
    /// not Kivy properties.
    ///
    /// `self.x` only binds when `x` is a property -- declared in the KV rule,
    /// inherited from a base widget, or assigned in the existing .py as
    /// `x = StringProperty(...)`. A plain Python attribute raises in
    /// `bind()`, so those get the initial assignment and nothing more.
    func bindableKeys(_ keys: [[String]]) -> [BindableKey] {
        var seen = Swift.Set<BindableKey>()
        return keys.compactMap { key -> BindableKey? in
            guard key.count == 2 else { return nil }
            let property = key[1]
            
            let object: String
            let bindable: Bool
            switch key[0] {
            case "root":
                object = "self"
                bindable = isBindableRuleProperty(property)
            case "self":
                object = context.selfScope.name
                bindable = context.selfScope.widgetType.map { isBindableProperty(property, on: $0) }
                    ?? isBindableRuleProperty(property)
            default:
                // app, or an id: nothing here can say what it is.
                object = key[0]
                bindable = true
            }
            guard bindable else { return nil }
            
            // One expression can name the same property more than once; it
            // still only needs binding once.
            let resolved = BindableKey(object, property)
            return seen.insert(resolved).inserted ? resolved : nil
        }
    }
    
    /// Is `name` a property of the class this rule generates?
    private func isBindableRuleProperty(_ name: String) -> Bool {
        let pyClass = context.rule.pyClass
        if pyClass.selfProperties.contains(name) { return true }
        return pyClass.bases.contains { dialect.propertyType(name, on: $0) != nil }
    }
    
    /// Is `name` a property of `widgetType`?
    ///
    /// The registry answers for anything Kivy ships. A widget defined by
    /// another rule, or by a class in the .py, is resolved to its own
    /// declarations and bases. A widget from outside the module cannot be
    /// checked, so it is assumed bindable rather than silently dropped.
    func isBindableProperty(_ name: String, on widgetType: String) -> Bool {
        if dialect.widgetExists(widgetType) {
            return dialect.propertyType(name, on: widgetType) != nil
        }
        
        if let pythonClass = context.pythonClass(named: widgetType) {
            if pythonClass.kivyProperties[name] != nil { return true }
            if pythonClass.baseClasses.contains(where: { isBindableProperty(name, on: $0) }) { return true }
            // A class we can see in full: if it does not declare the property,
            // it does not have one.
            return false
        }
        
        if let rule = rule(generating: widgetType), let resolved = resolvedClass(for: rule) {
            if customProperties(for: rule, bases: resolved.bases).contains(name) { return true }
            return resolved.bases.contains { isBindableProperty(name, on: $0) }
        }
        
        return true
    }
}
