//
//  MetricsCollector.swift
//  KvToPyClass
//
//  Created by CodeBuilder on 12/09/2026.
//


final class MetricsCollector {
    static let functions: Swift.Set<String> = ["dp", "sp", "pt", "mm", "cm", "inch"]
    /// Every name any generated value reads, so `#:import` aliases that are
    /// actually used can be imported and the rest left out.
    var names = Swift.Set<String>()
    var used: Swift.Set<String> { names.intersection(Self.functions) }
}