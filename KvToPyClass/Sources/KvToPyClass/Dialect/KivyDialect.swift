//
//  KivyDialect.swift
//  KvToPyClass
//

import KivyWidgetRegistry

/// Kivy's own widgets, answered from the registry.
struct KivyDialect: WidgetDialect {
    
    func widgetExists(_ name: String) -> Bool {
        KivyWidgetRegistry.widgetExists(name)
    }
    
    func propertyType(_ property: String, on widget: String) -> KivyPropertyType? {
        KivyWidgetRegistry.getPropertyType(property, on: widget)
    }
    
    func module(for widget: String) -> String {
        Self.widgetModules[widget] ?? "kivy.uix.\(widget.lowercased())"
    }
    
    /// Where a widget actually lives. Most are `kivy.uix.<lowercase>`, but
    /// plenty share a module with a sibling, and guessing invents a module
    /// that does not exist.
    private static let widgetModules: [String: String] = {
        var modules: [String: String] = [:]
        func put(_ module: String, _ names: [String]) {
            for name in names { modules[name] = module }
        }
        put("kivy.uix.behaviors", [
            "ButtonBehavior", "ToggleButtonBehavior", "DragBehavior", "FocusBehavior",
            "CompoundSelectionBehavior", "CodeNavigationBehavior", "EmacsBehavior",
            "CoverBehavior", "TouchRippleBehavior", "TouchRippleButtonBehavior",
            "MotionCollideBehavior", "MotionBlockBehavior",
        ])
        put("kivy.uix.screenmanager", [
            "Screen", "TransitionBase", "NoTransition", "SlideTransition",
            "CardTransition", "FadeTransition", "FallOutTransition",
            "RiseInTransition", "ShaderTransition", "WipeTransition",
        ])
        put("kivy.uix.actionbar", [
            "ActionButton", "ActionGroup", "ActionItem", "ActionOverflow",
            "ActionPrevious", "ActionSeparator", "ActionToggleButton", "ActionView",
        ])
        put("kivy.uix.settings", [
            "Settings", "SettingsPanel", "SettingItem", "SettingBoolean", "SettingColor",
            "SettingOptions", "SettingPath", "SettingSidebarLabel", "SettingString",
            "SettingTitle", "InterfaceWithSidebar", "InterfaceWithSpinner",
            "InterfaceWithTabbedPanel", "MenuSidebar", "MenuSpinner", "ContentPanel",
        ])
        put("kivy.uix.effectwidget", [
            "EffectBase", "AdvancedEffectBase", "ChannelMixEffect",
            "HorizontalBlurEffect", "VerticalBlurEffect", "PixelateEffect",
        ])
        put("kivy.uix.tabbedpanel", ["TabbedPanelHeader", "TabbedPanelStrip", "StripLayout"])
        put("kivy.uix.videoplayer", [
            "VideoPlayerAnnotation", "VideoPlayerPlayPause", "VideoPlayerPreview",
            "VideoPlayerProgressBar", "VideoPlayerStop", "VideoPlayerVolume",
        ])
        put("kivy.uix.rst", [
            "RstBlockQuote", "RstDefinition", "RstDefinitionList", "RstDefinitionSpace",
            "RstDocument", "RstFieldName", "RstFootName", "RstListBullet", "RstListItem",
            "RstLiteralBlock", "RstNote", "RstParagraph", "RstTerm", "RstTitle", "RstWarning",
        ])
        put("kivy.uix.filechooser", [
            "FileChooserController", "FileChooserLayout", "FileChooserProgressBase",
            "FileChooserListView", "FileChooserIconView",
        ])
        put("kivy.uix.accordion", ["AccordionItem"])
        put("kivy.uix.bubble", ["BubbleContent", "BubbleButton"])
        put("kivy.uix.colorpicker", ["ColorWheel"])
        put("kivy.uix.gesturesurface", ["GestureContainer"])
        put("kivy.uix.treeview", ["TreeViewNode", "TreeViewLabel"])
        put("kivy.uix.textinput", ["TextInputCutCopyPaste"])
        put("kivy.uix.image", ["AsyncImage"])
        return modules
    }()
}
