//
//  WidgetDialect.swift
//  KvToPyClass
//

import KivyWidgetRegistry
import KvParser

/// What the generator knows about the widget toolkit a KV file targets:
/// which widget names exist, where they are imported from, and which of
/// their attributes are properties that can be bound.
///
/// `#:mode` picks the dialect. Only Kivy's own widgets are known today; a
/// mode that spells widgets differently (SwiftUI-style names, say) adds a
/// dialect here rather than branches through the generators.
protocol WidgetDialect {
    /// Does the toolkit ship a widget by this name?
    func widgetExists(_ name: String) -> Bool
    /// The declared type of `property` on `widget`, or nil if it has none.
    func propertyType(_ property: String, on widget: String) -> KivyPropertyType?
    /// The Python module `widget` is imported from.
    func module(for widget: String) -> String
}

extension KvMode {
    /// The dialect a `#:mode` names. Every mode resolves to Kivy until
    /// another toolkit is described.
    var dialect: any WidgetDialect {
        switch self {
        case .default, .carbonkivy, .nucleant, .swiftui:
            KivyDialect()
        }
    }
}
