//
//  ModuleAnalysis.swift
//  KvToPyClass
//

import KvParser

/// Read-only walks over the KV tree: what it names, what it draws, and
/// whether it reads `app`.
final class ModuleAnalysis {
    private let context: GenerationContext
    private let resolver: PropertyResolver
    
    init(context: GenerationContext, resolver: PropertyResolver) {
        self.context = context
        self.resolver = resolver
    }
    
    // MARK: Widgets
    
    /// Every widget type the module uses, apart from the classes it defines
    /// itself.
    func widgetTypes() -> Swift.Set<String> {
        var types = Swift.Set<String>()
        
        var customWidgets = Swift.Set<String>()
        for rule in context.module.rules {
            switch rule.selector {
            case .dynamicClass(let name, _):
                customWidgets.insert(name)
            case .name(let name):
                customWidgets.insert(name)
            default:
                break
            }
        }
        
        for rule in context.module.rules {
            // The resolved bases, so the implicit `Widget` fallback gets
            // imported too. Bases the existing .py already provides are
            // dropped later when the generated imports are merged into it.
            if let resolved = resolver.resolvedClass(for: rule) {
                for base in resolved.bases where !customWidgets.contains(base) {
                    types.insert(base)
                }
            }
            collectTypes(in: rule.children, into: &types, excluding: customWidgets)
            for body in Self.conditionalBodies(rule.conditionals) {
                collectTypes(in: body.children, into: &types, excluding: customWidgets)
            }
        }
        
        return types
    }
    
    private func collectTypes(in children: [KvWidget], into types: inout Swift.Set<String>, excluding customWidgets: Swift.Set<String>) {
        for child in children {
            if !customWidgets.contains(child.name) {
                types.insert(child.name)
            }
            collectTypes(in: child.children, into: &types, excluding: customWidgets)
            for body in Self.conditionalBodies(child.conditionals) {
                collectTypes(in: body.children, into: &types, excluding: customWidgets)
            }
        }
    }
    
    /// Every id in the widget tree, at any depth.
    static func ids(in children: [KvWidget]) -> Swift.Set<String> {
        var ids = Swift.Set<String>()
        for child in children {
            if let id = child.id { ids.insert(id) }
            ids.formUnion(self.ids(in: child.children))
        }
        return ids
    }
    
    // MARK: Conditionals
    
    /// Every branch body under these conditionals, nested ones included.
    /// Child widgets inside a branch are not descended into; callers that
    /// walk children do that themselves.
    static func conditionalBodies(_ conditionals: [KvConditional]) -> [KvBody] {
        var bodies: [KvBody] = []
        for conditional in conditionals {
            for body in [conditional.body] + (conditional.elseBody.map { [$0] } ?? []) {
                bodies.append(body)
                bodies.append(contentsOf: conditionalBodies(body.conditionals))
            }
        }
        return bodies
    }
    
    /// Branch bodies of conditionals sitting inside child widgets, at any depth.
    static func conditionalBodies(inChildren children: [KvWidget]) -> [KvBody] {
        var bodies: [KvBody] = []
        for child in children {
            bodies.append(contentsOf: conditionalBodies(child.conditionals))
            bodies.append(contentsOf: conditionalBodies(inChildren: child.children))
            for body in conditionalBodies(child.conditionals) {
                bodies.append(contentsOf: conditionalBodies(inChildren: body.children))
            }
        }
        return bodies
    }
    
    // MARK: Graphics
    
    /// Every graphics instruction type used in a canvas, anywhere.
    func graphicsTypes() -> Swift.Set<String> {
        var types = Swift.Set<String>()
        
        for rule in context.module.rules {
            collectGraphicsTypes(in: rule.children, into: &types)
            // A branch's canvas is wrapped in a group so it can be removed again.
            for body in Self.conditionalBodies(rule.conditionals) + Self.conditionalBodies(inChildren: rule.children) {
                for (_, canvas) in CanvasLayer.layers(of: body) {
                    types.insert("InstructionGroup")
                    for instruction in canvas.instructions {
                        types.insert(instruction.instructionType)
                    }
                }
                collectGraphicsTypes(in: body.children, into: &types)
            }
            for (_, canvas) in CanvasLayer.layers(of: rule.body) {
                for instruction in canvas.instructions {
                    types.insert(instruction.instructionType)
                }
            }
        }
        
        return types
    }
    
    private func collectGraphicsTypes(in children: [KvWidget], into types: inout Swift.Set<String>) {
        for child in children {
            for (_, canvas) in CanvasLayer.layers(of: child.body) {
                for instruction in canvas.instructions {
                    types.insert(instruction.instructionType)
                }
            }
            collectGraphicsTypes(in: child.children, into: &types)
        }
    }
    
    // MARK: App
    
    /// Does anything in the rule read `app`, so `App.get_running_app()` is
    /// needed?
    static func mentionsApp(_ rule: KvRule) -> Bool {
        mentionsApp(rule.properties) || mentionsApp(rule.handlers)
            || mentionsApp(inChildren: rule.children) || mentionsApp(inCanvasOf: rule.body)
            || mentionsApp(rule.conditionals)
    }
    
    static func mentionsApp(_ properties: [KvProperty]) -> Bool {
        properties.contains { $0.value.contains("app.") }
    }
    
    private static func mentionsApp(inCanvasOf body: KvBody) -> Bool {
        CanvasLayer.layers(of: body).contains { _, canvas in
            mentionsApp(canvas.instructions.flatMap(\.properties))
        }
    }
    
    static func mentionsApp(inChildren children: [KvWidget]) -> Bool {
        children.contains { child in
            mentionsApp(child.properties) || mentionsApp(child.handlers)
                || mentionsApp(inChildren: child.children) || mentionsApp(child.conditionals)
        }
    }
    
    /// Does any value in these blocks, or a condition nested in them, read `app`?
    static func mentionsApp(_ conditionals: [KvConditional]) -> Bool {
        for conditional in conditionals {
            if let condition = conditional.condition, condition.contains("app.") { return true }
            for body in [conditional.body] + (conditional.elseBody.map { [$0] } ?? []) {
                if mentionsApp(body.properties + body.handlers) { return true }
                if mentionsApp(inCanvasOf: body) { return true }
                if mentionsApp(inChildren: body.children) { return true }
                if mentionsApp(body.conditionals) { return true }
            }
        }
        return false
    }
}
