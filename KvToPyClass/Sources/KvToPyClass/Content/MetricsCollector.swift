//
//  MetricsCollector.swift
//  KvToPyClass
//

/// Names of kivy.metrics helpers seen in property values, so they can be
/// imported. KV gets these for free from Builder's environment; generated
/// Python has to import them.
final class MetricsCollector {
    static let functions: Swift.Set<String> = ["dp", "sp", "pt", "mm", "cm", "inch"]
    /// Every name any generated value reads, so `#:import` aliases that are
    /// actually used can be imported and the rest left out.
    private(set) var names = Swift.Set<String>()
    var used: Swift.Set<String> { names.intersection(Self.functions) }
    
    func record(_ names: Swift.Set<String>) {
        self.names.formUnion(names)
    }
}
