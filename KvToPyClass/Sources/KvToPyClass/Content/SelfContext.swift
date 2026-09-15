//
//  SelfContext.swift
//  KvToPyClass
//

/// What KV's `self` refers to right now: the rule root by default, or the
/// child widget whose block is being generated.
final class SelfContext {
    var name = "self"
    var widgetType: String?
    
    /// Run `body` with `self` meaning another widget, restoring the enclosing
    /// one afterwards so siblings are unaffected.
    func inside<T>(_ name: String, type: String?, _ body: () throws -> T) rethrows -> T {
        let enclosing = (self.name, widgetType)
        self.name = name
        widgetType = type
        defer {
            self.name = enclosing.0
            widgetType = enclosing.1
        }
        return try body()
    }
}
