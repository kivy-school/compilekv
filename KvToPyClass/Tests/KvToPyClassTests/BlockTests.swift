import XCTest
@testable import KvToPyClass
import KvParser

/// `name: |` blocks become functions.
final class BlockTests: XCTestCase {
    
    private func generate(_ kv: String) throws -> String {
        let tokens = try KvTokenizer(source: kv).tokenize()
        let module = try KvParser(tokens: tokens).parse()
        return try KvToPyClassGenerator(module: module).generate()
    }
    
    func testValueBlockIsAFunctionAssignedAndRebound() throws {
        let code = try generate("""
        <StatusLabel@Label>:
            error: False
            text: |
                if self.error:
                    return "failed"
                return "ok"
        """)
        
        XCTAssertTrue(code.contains("error = ObjectProperty(None)"), "a watched rule attribute becomes a property")
        XCTAssertTrue(code.contains("def _value_1():\n            if self.error:\n                return \"failed\"\n            return \"ok\""))
        XCTAssertTrue(code.contains("self.text = _value_1()"))
        XCTAssertTrue(code.contains("_callback_0 = lambda *args: setattr(self, \"text\", _value_1())"))
        XCTAssertTrue(code.contains("self.bind(error=_callback_0)"))
        XCTAssertTrue(code.contains("self._bindings.append((self, \"error\", _callback_0))"))
    }
    
    func testValueBlockOnAChildResolvesSelfToTheChild() throws {
        let code = try generate("""
        <W@BoxLayout>:
            Button:
                text: |
                    return "pressed" if self.state == "down" else "released"
        """)
        
        XCTAssertTrue(code.contains("button_1 = Button()"))
        XCTAssertTrue(code.contains("def _value_2():\n            return \"pressed\" if button_1.state == \"down\" else \"released\""))
        XCTAssertTrue(code.contains("button_1.text = _value_2()"))
        XCTAssertTrue(code.contains("button_1.bind(state=_callback_0)"))
        XCTAssertFalse(code.contains("Button(text="), "a block is never a constructor argument")
    }
    
    func testHandlerBlockAtRuleLevelIsAMethod() throws {
        let code = try generate("""
        #:set BIG 20
        
        <StatusLabel@Label>:
            on_error: |
                if self.error:
                    self.font_size = BIG
                else:
                    self.font_size = 14
                app.log(root.text, inner.text)
            Label:
                id: inner
        """)
        
        XCTAssertTrue(code.contains("self.bind(on_error=self._on_error_handler)"))
        XCTAssertTrue(code.contains("""
            def _on_error_handler(self, instance):
                app = App.get_running_app()
                inner = self.ids["inner"]
                if self.error:
                    self.font_size = 20
                else:
                    self.font_size = 14
                app.log(self.text, inner.text)
        """))
        XCTAssertTrue(code.contains("from kivy.app import App"))
    }
    
    func testHandlerBlockOnAChildIsANestedFunction() throws {
        let code = try generate("""
        <W@BoxLayout>:
            Button:
                on_press: |
                    # toggle
                    root.error = not root.error
                    print(self.text)
        """)
        
        XCTAssertTrue(code.contains("def _callback_0(instance):\n            self.error = not self.error\n            print(button_1.text)"))
        XCTAssertTrue(code.contains("button_1.bind(on_press=_callback_0)"))
        XCTAssertTrue(code.contains("self._bindings.append((button_1, \"on_press\", _callback_0))"))
    }
    
    func testCanvasBlockIsDefinedBeforeTheWithBlock() throws {
        let code = try generate("""
        <W@Widget>:
            canvas:
                Color:
                    rgba: |
                        if self.disabled:
                            return 0.5, 0.5, 0.5, 1
                        return 1, 1, 1, 1
        """)
        
        let definition = code.range(of: "def _value_1():")!.lowerBound
        let with = code.range(of: "with self.canvas:")!.lowerBound
        XCTAssertLessThan(definition, with)
        XCTAssertTrue(code.contains("self.color_2 = Color(rgba=_value_1())"))
        XCTAssertTrue(code.contains("_callback_0 = lambda *args: setattr(self.color_2, \"rgba\", _value_1())"))
        XCTAssertTrue(code.contains("self.bind(disabled=_callback_0)"))
    }
    
    func testBlockInsideAConditionalBranch() throws {
        let code = try generate("""
        <W@BoxLayout>:
            if self.disabled:
                Label:
                    text: |
                        return "off"
        """)
        XCTAssertTrue(code.contains("def _value_1():\n                return \"off\""))
        XCTAssertTrue(code.contains("label_2.text = _value_1()"))
    }
    
    func testUnparsableBlockIsAnError() throws {
        XCTAssertThrowsError(try generate("<W@Label>:\n    text: |\n        return (\n")) { error in
            XCTAssertTrue("\(error)".contains("block value of 'text' is not valid Python"))
        }
    }
    
    func testMetricsUsedInABlockAreImported() throws {
        let code = try generate("<W@Label>:\n    font_size: |\n        return sp(16) if self.disabled else sp(12)\n")
        XCTAssertTrue(code.contains("from kivy.metrics import sp"))
    }
}
