import XCTest
@testable import KvToPyClass
import KvParser

final class KvToPyClassTests: XCTestCase {
    
    func testSimpleButtonGeneration() throws {
        let kvSource = """
        <MyButton@Button>:
            text: 'Click me'
            size_hint: (0.5, 0.5)
        """
        
        let tokenizer = KvTokenizer(source: kvSource)
        let tokens = try tokenizer.tokenize()
        let parser = KvParser(tokens: tokens)
        let module = try parser.parse()
        
        let generator = KvToPyClassGenerator(module: module)
        let pythonCode = try generator.generate()
        
        // Verify the generated code contains expected elements
        XCTAssertTrue(pythonCode.contains("class MyButton"))
        XCTAssertTrue(pythonCode.contains("def __init__"))
        XCTAssertTrue(pythonCode.contains("super().__init__"))
        XCTAssertTrue(pythonCode.contains("self.text"))
        XCTAssertTrue(pythonCode.contains("Click me"))  // Just check for the text, not the quote style
        
        print("Generated Python code:")
        print(pythonCode)
    }
    
    func testButtonWithHandler() throws {
        let kvSource = """
        <MyButton@Button>:
            text: 'Press me'
            on_press: print("Button pressed!")
        """
        
        let tokenizer = KvTokenizer(source: kvSource)
        let tokens = try tokenizer.tokenize()
        let parser = KvParser(tokens: tokens)
        let module = try parser.parse()
        
        let generator = KvToPyClassGenerator(module: module)
        let pythonCode = try generator.generate()
        
        // Verify handler generation
        XCTAssertTrue(pythonCode.contains("class MyButton"))
        XCTAssertTrue(pythonCode.contains("def _on_press_handler"))
        XCTAssertTrue(pythonCode.contains("self.bind"))
        XCTAssertTrue(pythonCode.contains("print"))
        
        print("Generated Python code with handler:")
        print(pythonCode)
    }
    
    func testWidgetWithChildren() throws {
        let kvSource = """
        <MyLayout@BoxLayout>:
            orientation: 'vertical'
            Button:
                text: 'Top'
            Button:
                text: 'Bottom'
        """
        
        let tokenizer = KvTokenizer(source: kvSource)
        let tokens = try tokenizer.tokenize()
        let parser = KvParser(tokens: tokens)
        let module = try parser.parse()
        
        let generator = KvToPyClassGenerator(module: module)
        let pythonCode = try generator.generate()
        
        // Verify child widget generation
        XCTAssertTrue(pythonCode.contains("class MyLayout"))
        XCTAssertTrue(pythonCode.contains("self.add_widget"))
        XCTAssertTrue(pythonCode.contains("Button"))
        
        print("Generated Python code with children:")
        print(pythonCode)
    }
    
    func testMultipleClasses() throws {
        let kvSource = """
        <FirstWidget@Label>:
            text: 'First'
        
        <SecondWidget@Button>:
            text: 'Second'
        """
        
        let tokenizer = KvTokenizer(source: kvSource)
        let tokens = try tokenizer.tokenize()
        let parser = KvParser(tokens: tokens)
        let module = try parser.parse()
        
        let generator = KvToPyClassGenerator(module: module)
        let pythonCode = try generator.generate()
        
        // Verify multiple classes
        XCTAssertTrue(pythonCode.contains("class FirstWidget"))
        XCTAssertTrue(pythonCode.contains("class SecondWidget"))
        
        print("Generated Python code with multiple classes:")
        print(pythonCode)
    }
    
    func testPropertyBinding() throws {
        let kvSource = """
        <MyButton@Button>:
            text: app.title
            background_color: 0.2, 0.6, 1, 1
        """
        
        let tokenizer = KvTokenizer(source: kvSource)
        let tokens = try tokenizer.tokenize()
        let parser = KvParser(tokens: tokens)
        let module = try parser.parse()
        
        let generator = KvToPyClassGenerator(module: module)
        let pythonCode = try generator.generate()
        
        // Verify property binding generates assignment and bind() call
        XCTAssertTrue(pythonCode.contains("class MyButton"))
        XCTAssertTrue(pythonCode.contains("app = App.get_running_app()"))  // App instance
        XCTAssertTrue(pythonCode.contains("self.text = app.title"))  // Initial assignment
        XCTAssertTrue(pythonCode.contains("app.bind(title=self.setter(\"text\"))"))  // Reactive binding
        XCTAssertTrue(pythonCode.contains("from kivy.app import App"))  // Import App
        
        print("Generated Python code with property binding:")
        print(pythonCode)
    }
    
    func testRootReference() throws {
        let kvSource = """
        <ProfileWidget@BoxLayout>:
            Button:
                text: 'Save'
                on_press: root.save_profile()
        """
        
        let tokenizer = KvTokenizer(source: kvSource)
        let tokens = try tokenizer.tokenize()
        let parser = KvParser(tokens: tokens)
        let module = try parser.parse()
        
        let generator = KvToPyClassGenerator(module: module)
        let pythonCode = try generator.generate()
        
        // Verify root is converted to self in child widget event handlers
        XCTAssertTrue(pythonCode.contains("class ProfileWidget"))
        XCTAssertTrue(pythonCode.contains("lambda instance: self.save_profile"))
        XCTAssertFalse(pythonCode.contains("root.save_profile"))  // Should not contain root
        
        print("Generated Python code with root reference:")
        print(pythonCode)
    }
    
    func testChildWidgetFStringBinding() throws {
        let kvSource = """
        <AppHeader@BoxLayout>:
            Label:
                text: f"{app.title} - {app.version}"
        """
        
        let tokenizer = KvTokenizer(source: kvSource)
        let tokens = try tokenizer.tokenize()
        let parser = KvParser(tokens: tokens)
        let module = try parser.parse()
        
        // Debug: print property value
        if let rule = module.rules.first, let child = rule.children.first {
            if let textProp = child.properties.first(where: { $0.name == "text" }) {
                print("Property value: '\(textProp.value)'")
                print("Watched keys: \(textProp.watchedKeys ?? [])")
            }
        }
        
        let generator = KvToPyClassGenerator(module: module)
        let pythonCode = try generator.generate()
        
        // Verify child widget f-string creates proper binding
        XCTAssertTrue(pythonCode.contains("class AppHeader"))
        // Widget should be created without text parameter
        XCTAssertTrue(pythonCode.contains("Label("))
        // text should be set after widget creation
        XCTAssertTrue(pythonCode.contains("widget_") || pythonCode.contains(".text = f"))
        // Should have bind() call with lambda that re-evaluates expression
        XCTAssertTrue(pythonCode.contains("app.bind("))
        XCTAssertTrue(pythonCode.contains("setattr(") || pythonCode.contains("lambda"))
        
        print("Generated Python code with child widget f-string binding:")
        print(pythonCode)
    }
    
    func testChildWidgetStrBinding() throws {
        let kvSource = """
        <InfoWidget@BoxLayout>:
            Label:
                text: str(app.count)
            Label:
                text: str(app.price)
        """
        
        let tokenizer = KvTokenizer(source: kvSource)
        let tokens = try tokenizer.tokenize()
        let parser = KvParser(tokens: tokens)
        let module = try parser.parse()
        
        let generator = KvToPyClassGenerator(module: module)
        let pythonCode = try generator.generate()
        
        // Verify str() calls create lambda bindings, not .setter()
        XCTAssertTrue(pythonCode.contains("class InfoWidget"))
        XCTAssertTrue(pythonCode.contains("app = App.get_running_app()"))
        XCTAssertTrue(pythonCode.contains(".text = str(app.count)"))
        XCTAssertTrue(pythonCode.contains(".text = str(app.price)"))
        // Should use lambda with parameter, not .setter()
        XCTAssertTrue(pythonCode.contains("lambda instance, app_count:"))
        XCTAssertTrue(pythonCode.contains("lambda instance, app_price:"))
        XCTAssertTrue(pythonCode.contains("str(app_count)"))
        XCTAssertTrue(pythonCode.contains("str(app_price)"))
        XCTAssertFalse(pythonCode.contains(".setter(\"text\")"))  // Should NOT use setter for str() calls
        
        print("Generated Python code with str() binding:")
        print(pythonCode)
    }
}