import XCTest
@testable import KvToPyClass
@testable import KivyWidgetRegistry

final class KivyWidgetRegistryTests: XCTestCase {
    
    func testMultipleInheritance() {
        // Test Button inherits from both ButtonBehavior and Label
        let buttonProps = KivyWidgetRegistry.getAllProperties(for: .Button)
        
        // Check for ButtonBehavior properties
        XCTAssertTrue(buttonProps.contains { $0.name == "pressed" }, "Button should have 'pressed' from ButtonBehavior")
        XCTAssertTrue(buttonProps.contains { $0.name == "always_release" }, "Button should have 'always_release' from ButtonBehavior")
        
        // Check for Label properties
        XCTAssertTrue(buttonProps.contains { $0.name == "text" }, "Button should have 'text' from Label")
        XCTAssertTrue(buttonProps.contains { $0.name == "font_size" }, "Button should have 'font_size' from Label")
        
        // Check for Widget properties (inherited through Label)
        XCTAssertTrue(buttonProps.contains { $0.name == "pos" }, "Button should have 'pos' from Widget")
        XCTAssertTrue(buttonProps.contains { $0.name == "size" }, "Button should have 'size' from Widget")
        
        // Check for Button's own properties
        XCTAssertTrue(buttonProps.contains { $0.name == "background_color" }, "Button should have its own 'background_color'")
        
        // Test ToggleButton (triple inheritance chain)
        let toggleProps = KivyWidgetRegistry.getAllProperties(for: .ToggleButton)
        XCTAssertTrue(toggleProps.contains { $0.name == "active" }, "ToggleButton should have 'active' from ToggleButtonBehavior")
        XCTAssertTrue(toggleProps.contains { $0.name == "group" }, "ToggleButton should have 'group' from ToggleButtonBehavior")
        XCTAssertTrue(toggleProps.contains { $0.name == "pressed" }, "ToggleButton should have 'pressed' from ButtonBehavior via Button")
        XCTAssertTrue(toggleProps.contains { $0.name == "text" }, "ToggleButton should have 'text' from Label via Button")
        
        print("✅ Multiple inheritance test passed!")
        print("   Button has \(buttonProps.count) properties (ButtonBehavior + Label + Widget)")
        print("   ToggleButton has \(toggleProps.count) properties (full chain)")
    }
    
    func testWidgetExists() {
        XCTAssertTrue(KivyWidgetRegistry.widgetExists("Widget"))
        XCTAssertTrue(KivyWidgetRegistry.widgetExists("Button"))
        XCTAssertTrue(KivyWidgetRegistry.widgetExists("Label"))
        XCTAssertTrue(KivyWidgetRegistry.widgetExists("BoxLayout"))
        XCTAssertTrue(KivyWidgetRegistry.widgetExists("FloatLayout"))
        XCTAssertTrue(KivyWidgetRegistry.widgetExists("GridLayout"))
        XCTAssertFalse(KivyWidgetRegistry.widgetExists("NonExistentWidget"))
    }
    
    func testGetWidgetInfo() {
        let buttonInfo = KivyWidgetRegistry.getWidgetInfo("Button")
        XCTAssertNotNil(buttonInfo)
        XCTAssertEqual(buttonInfo?.widgetName, "Button")
        
        let labelInfo = KivyWidgetRegistry.getWidgetInfo("Label")
        XCTAssertNotNil(labelInfo)
        XCTAssertEqual(labelInfo?.widgetName, "Label")
    }
    
    func testWidgetProperties() {
        // Test Widget base class properties
        let widgetInfo = KivyWidgetRegistry.getWidgetInfo("Widget")
        XCTAssertNotNil(widgetInfo)
        
        let widgetProps = widgetInfo?.directProperties ?? []
        XCTAssertTrue(widgetProps.contains(KivyPropertyInfo(name: "x", type: .numericProperty)))
        XCTAssertTrue(widgetProps.contains(KivyPropertyInfo(name: "y", type: .numericProperty)))
        XCTAssertTrue(widgetProps.contains(KivyPropertyInfo(name: "width", type: .numericProperty)))
        XCTAssertTrue(widgetProps.contains(KivyPropertyInfo(name: "height", type: .numericProperty)))
        XCTAssertTrue(widgetProps.contains(KivyPropertyInfo(name: "pos", type: .referenceListProperty)))
        XCTAssertTrue(widgetProps.contains(KivyPropertyInfo(name: "size", type: .referenceListProperty)))
        
        // Test Label properties
        let labelInfo = KivyWidgetRegistry.getWidgetInfo("Label")
        let labelProps = labelInfo?.directProperties ?? []
        XCTAssertTrue(labelProps.contains(KivyPropertyInfo(name: "text", type: .stringProperty)))
        XCTAssertTrue(labelProps.contains(KivyPropertyInfo(name: "font_size", type: .numericProperty)))
        XCTAssertTrue(labelProps.contains(KivyPropertyInfo(name: "color", type: .colorProperty)))
        XCTAssertTrue(labelProps.contains(KivyPropertyInfo(name: "bold", type: .booleanProperty)))
        
        // Test Button properties
        let buttonInfo = KivyWidgetRegistry.getWidgetInfo("Button")
        let buttonProps = buttonInfo?.directProperties ?? []
        XCTAssertTrue(buttonProps.contains(KivyPropertyInfo(name: "background_color", type: .colorProperty)))
        XCTAssertTrue(buttonProps.contains(KivyPropertyInfo(name: "background_normal", type: .stringProperty)))
    }
    
    func testHasProperty() {
        // Widget base properties
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("x", on: "Widget"))
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("y", on: "Widget"))
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("width", on: "Widget"))
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("height", on: "Widget"))
        
        // Label should have Widget properties + its own
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("x", on: "Label"))
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("y", on: "Label"))
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("text", on: "Label"))
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("font_size", on: "Label"))
        
        // Button should have its properties
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("background_color", on: "Button"))
        
        // BoxLayout should have Widget properties + Layout + BoxLayout
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("x", on: "BoxLayout"))
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("orientation", on: "BoxLayout"))
        XCTAssertTrue(KivyWidgetRegistry.hasProperty("spacing", on: "BoxLayout"))
        
        // Non-existent properties
        XCTAssertFalse(KivyWidgetRegistry.hasProperty("nonexistent", on: "Widget"))
        XCTAssertFalse(KivyWidgetRegistry.hasProperty("text", on: "BoxLayout"))
    }
    
    func testGetPropertyType() {
        XCTAssertEqual(KivyWidgetRegistry.getPropertyType("x", on: "Widget"), .numericProperty)
        XCTAssertEqual(KivyWidgetRegistry.getPropertyType("text", on: "Label"), .stringProperty)
        XCTAssertEqual(KivyWidgetRegistry.getPropertyType("bold", on: "Label"), .booleanProperty)
        XCTAssertEqual(KivyWidgetRegistry.getPropertyType("background_color", on: "Button"), .colorProperty)
        XCTAssertEqual(KivyWidgetRegistry.getPropertyType("orientation", on: "BoxLayout"), .optionProperty)
        
        XCTAssertNil(KivyWidgetRegistry.getPropertyType("nonexistent", on: "Widget"))
    }
    
    func testGetAllProperties() {
        // Widget should only have its own properties
        let widgetProps = KivyWidgetRegistry.getAllProperties(for: "Widget")
        XCTAssertGreaterThan(widgetProps.count, 20) // Widget has 28 properties
        
        // Label inherits from Widget, so should have more properties
        let labelProps = KivyWidgetRegistry.getAllProperties(for: "Label")
        XCTAssertGreaterThan(labelProps.count, widgetProps.count)
        
        // BoxLayout inherits from Layout which inherits from Widget
        let boxLayoutProps = KivyWidgetRegistry.getAllProperties(for: "BoxLayout")
        XCTAssertGreaterThan(boxLayoutProps.count, widgetProps.count)
        
        // Verify BoxLayout has inherited Widget properties
        XCTAssertTrue(boxLayoutProps.contains(KivyPropertyInfo(name: "x", type: .numericProperty)))
        XCTAssertTrue(boxLayoutProps.contains(KivyPropertyInfo(name: "y", type: .numericProperty)))
        
        // And its own properties
        XCTAssertTrue(boxLayoutProps.contains(KivyPropertyInfo(name: "orientation", type: .optionProperty)))
        XCTAssertTrue(boxLayoutProps.contains(KivyPropertyInfo(name: "spacing", type: .numericProperty)))
    }
    
    func testGetAllWidgetNames() {
        let allNames = KivyWidgetRegistry.getAllWidgetNames()
        
        XCTAssertTrue(allNames.contains("Widget"))
        XCTAssertTrue(allNames.contains("Button"))
        XCTAssertTrue(allNames.contains("Label"))
        XCTAssertTrue(allNames.contains("BoxLayout"))
        XCTAssertTrue(allNames.contains("FloatLayout"))
        XCTAssertTrue(allNames.contains("GridLayout"))
        XCTAssertTrue(allNames.contains("TextInput"))
        XCTAssertTrue(allNames.contains("Image"))
        XCTAssertTrue(allNames.contains("Slider"))
        
        // Should be sorted
        XCTAssertEqual(allNames, allNames.sorted())
        
        // Should have many widgets
        XCTAssertGreaterThan(allNames.count, 50)
    }
    
    func testInheritanceChain() {
        // Test that Button inherits from both ButtonBehavior and Label (multiple inheritance)
        let buttonInfo = KivyWidgetRegistry.getWidgetInfo("Button")
        XCTAssertEqual(buttonInfo?.baseClasses.count, 2)
        XCTAssertTrue(buttonInfo?.baseClasses.contains(.ButtonBehavior) ?? false)
        XCTAssertTrue(buttonInfo?.baseClasses.contains(.Label) ?? false)
        
        // Test that Label inherits from Widget
        let labelInfo = KivyWidgetRegistry.getWidgetInfo("Label")
        XCTAssertEqual(labelInfo?.baseClasses, [.Widget])
        
        // Test that BoxLayout inherits from Layout
        let boxLayoutInfo = KivyWidgetRegistry.getWidgetInfo("BoxLayout")
        XCTAssertEqual(boxLayoutInfo?.baseClasses, [.Layout])
        
        // Test that Layout inherits from Widget
        let layoutInfo = KivyWidgetRegistry.getWidgetInfo("Layout")
        XCTAssertEqual(layoutInfo?.baseClasses, [.Widget])
        
        // Test that ToggleButton inherits from both ToggleButtonBehavior and Button
        let toggleButtonInfo = KivyWidgetRegistry.getWidgetInfo("ToggleButton")
        XCTAssertEqual(toggleButtonInfo?.baseClasses.count, 2)
        XCTAssertTrue(toggleButtonInfo?.baseClasses.contains(.ToggleButtonBehavior) ?? false)
        XCTAssertTrue(toggleButtonInfo?.baseClasses.contains(.Button) ?? false)
    }
}
