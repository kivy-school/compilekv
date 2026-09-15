//
//  KvGenerators.swift
//  KvToPyClass
//

/// The set of generators for one run, each responsible for one kind of
/// output and reaching the others through here. Built lazily so they can
/// refer to each other freely: a conditional block builds child widgets,
/// and a child widget can hold a conditional block.
final class KvGenerators {
    let context: GenerationContext
    let resolver: PropertyResolver
    let values: ValueParser
    let analysis: ModuleAnalysis
    
    lazy var module = ModuleGenerator(self)
    lazy var imports = ImportGenerator(self)
    lazy var factory = FactoryGenerator(self)
    lazy var moduleMerger = ModuleMerger(self)
    lazy var classes = ClassGenerator(self)
    lazy var classMerger = ClassMerger()
    lazy var initMethod = InitMethodGenerator(self)
    lazy var delMethod = DelMethodGenerator()
    lazy var bindings = PropertyBindingGenerator(self)
    lazy var handlers = EventHandlerGenerator(self)
    lazy var widgets = WidgetTreeGenerator(self)
    lazy var canvas = CanvasGenerator(self)
    lazy var blocks = BlockGenerator(self)
    lazy var conditionals = ConditionalGenerator(self)
    
    init(context: GenerationContext) {
        self.context = context
        let resolver = PropertyResolver(context: context)
        self.resolver = resolver
        self.values = ValueParser(context: context, resolver: resolver)
        self.analysis = ModuleAnalysis(context: context, resolver: resolver)
    }
}

/// What every generator holds: the bundle it belongs to.
protocol KvGenerator: AnyObject {
    var generators: KvGenerators { get }
}

extension KvGenerator {
    var context: GenerationContext { generators.context }
    var values: ValueParser { generators.values }
    var resolver: PropertyResolver { generators.resolver }
}
