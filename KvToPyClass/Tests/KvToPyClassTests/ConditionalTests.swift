import XCTest
@testable import KvToPyClass
import KvParser

/// if/else and try/expect blocks, plus the #:mode and #:from directives.
final class ConditionalTests: XCTestCase {
    
    private func generate(_ kv: String) throws -> String {
        let tokens = try KvTokenizer(source: kv).tokenize()
        let module = try KvParser(tokens: tokens).parse()
        return try KvToPyClassGenerator(module: module).generate()
    }
    
    // MARK: - Directives
    
    func testFromDirectiveBecomesAnImport() throws {
        let code = try generate("""
        #:from kivy.metrics import dp
        #:from kivy.metrics import sp as scaled
        #:from pkg.mod import unused
        
        <Item@Label>:
            font_size: scaled(16)
            padding: dp(4)
        """)
        
        XCTAssertTrue(code.contains("from kivy.metrics import dp\n"))
        XCTAssertTrue(code.contains("from kivy.metrics import sp as scaled\n"))
        XCTAssertFalse(code.contains("pkg.mod"), "unused #:from must not be imported")
    }
    
    func testModeIsReadFromTheFile() throws {
        let tokens = try KvTokenizer(source: "#:mode swiftui\n\n<Item@Label>:\n    text: 'x'\n").tokenize()
        let module = try KvParser(tokens: tokens).parse()
        XCTAssertEqual(KvToPyClassGenerator(module: module).mode, "swiftui")
        
        let plain = try KvParser(tokens: try KvTokenizer(source: "<Item@Label>:\n    text: 'x'\n").tokenize()).parse()
        XCTAssertEqual(KvToPyClassGenerator(module: plain).mode, "default")
    }
    
    func testFileModeWinsOverSharedMode() throws {
        let tokens = try KvTokenizer(source: "#:mode nucleant\n\n<Item@Label>:\n    text: 'x'\n").tokenize()
        let module = try KvParser(tokens: tokens).parse()
        let generator = KvToPyClassGenerator(module: module, sharedDirectives: [.mode(name: "carbonkivy", line: 1)])
        XCTAssertEqual(generator.mode, "nucleant")
    }
    
    // MARK: - if / else
    
    private let planExample = """
    <MyWidget@BoxLayout>:
        if self.disabled: # if true show label else button..
            Label:
                text: "no press"
        else:
            Button:
                text: "press me"
        if self.other_state: # only show button if true
            Button:
                text: "extra press"
        try: # if no issues with proeprties or binding stuff
            Button:
                text: "success"
        expect:
            Label:
                text: "failed"
    """
    
    func testIfElseBecomesAMethodEvaluatedFromInit() throws {
        let code = try generate(planExample)
        
        // Evaluated once, then bound to what the condition watches.
        XCTAssertTrue(code.contains("self._conditional_0(self)\n"))
        XCTAssertTrue(code.contains("self.bind(disabled=_callback_0)"))
        XCTAssertTrue(code.contains("_callback_0 = lambda *args: self._conditional_0(self)"))
        
        XCTAssertTrue(code.contains("def _conditional_0(self, parent, *args):"))
        XCTAssertTrue(code.contains("self._conditional_0_reset()\n        if self.disabled:"))
        XCTAssertTrue(code.contains("label_1 = Label(text=\"no press\")"))
        XCTAssertTrue(code.contains("parent.add_widget(label_1)"))
        XCTAssertTrue(code.contains("self._conditional_0_widgets.append(label_1)"))
        XCTAssertTrue(code.contains("else:\n            button_2 = Button(text=\"press me\")"))
        
        // Widgets never go straight onto self from __init__.
        XCTAssertFalse(code.contains("self.add_widget"))
    }
    
    func testConditionOnAPlainAttributeDeclaresAProperty() throws {
        let code = try generate(planExample)
        XCTAssertTrue(code.contains("other_state = ObjectProperty(None)"))
        XCTAssertTrue(code.contains("self.bind(other_state=_callback_1)"))
        XCTAssertTrue(code.contains("from kivy.properties import ObjectProperty"))
    }
    
    func testTryExpectFallsBackAfterResetting() throws {
        let code = try generate(planExample)
        
        XCTAssertTrue(code.contains("def _conditional_2(self, parent, *args):"))
        XCTAssertTrue(code.contains("try:\n            button_4 = Button(text=\"success\")"))
        XCTAssertTrue(code.contains("except Exception:\n            self._conditional_2_reset()\n            label_5 = Label(text=\"failed\")"))
        // Nothing to watch, so nothing to bind.
        XCTAssertFalse(code.contains("self._conditional_2(self)\n        _callback"))
    }
    
    func testResetRemovesWidgetsAndUnbinds() throws {
        let code = try generate(planExample)
        
        XCTAssertTrue(code.contains("def _conditional_0_reset(self):"))
        XCTAssertTrue(code.contains("for widget in getattr(self, \"_conditional_0_widgets\", []):"))
        XCTAssertTrue(code.contains("widget.parent.remove_widget(widget)"))
        XCTAssertTrue(code.contains("for (obj, prop, callback) in getattr(self, \"_conditional_0_bindings\", []):"))
        XCTAssertTrue(code.contains("self._conditional_0_bindings = []"))
        
        // __del__ tears every block down before the generic cleanup.
        XCTAssertTrue(code.contains("def __del__(self):\n        self._conditional_0_reset()\n        self._conditional_1_reset()\n        self._conditional_2_reset()"))
    }
    
    // MARK: - Where the block sits
    
    func testBlockInsideAChildBindsOnThatChild() throws {
        let code = try generate("""
        <Panel@BoxLayout>:
            Label:
                id: title
                text: "Title"
            BoxLayout:
                id: body
                if self.width > 400 and root.compact:
                    Label:
                        text: title.text + " wide"
        """)
        
        // `self` is the BoxLayout in __init__, `parent` inside the method.
        XCTAssertTrue(code.contains("self._conditional_0(body)"))
        XCTAssertTrue(code.contains("body.bind(width=_callback_0)"))
        XCTAssertTrue(code.contains("self.bind(compact=_callback_1)"))
        XCTAssertTrue(code.contains("if (parent.width > 400 and self.compact):"))
        XCTAssertTrue(code.contains("compact = ObjectProperty(None)"))
        
        // An id from __init__ is re-read from self.ids inside the method.
        XCTAssertTrue(code.contains("title = self.ids[\"title\"]"))
        XCTAssertTrue(code.contains("title.bind(text=_callback_0)"))
        XCTAssertTrue(code.contains("self._conditional_0_bindings.append((title, \"text\", _callback_0))"))
    }
    
    func testBranchPropertiesCanvasAndNestedBlocks() throws {
        let code = try generate("""
        <Panel@BoxLayout>:
            if self.disabled:
                opacity: 0.5
                canvas:
                    Color:
                        rgba: 1, 0, 0, 1
                    Rectangle:
                        pos: self.pos
                        size: self.size
                if app.dark:
                    Label:
                        text: "dark"
        """)
        
        XCTAssertTrue(code.contains("self.opacity = 0.5"))
        
        // Canvas goes into a group the reset can remove.
        XCTAssertTrue(code.contains("from kivy.graphics import Color, InstructionGroup, Rectangle"))
        XCTAssertTrue(code.contains("group_1 = InstructionGroup()"))
        XCTAssertTrue(code.contains("group_1.add(Color(rgba=(1, 0, 0, 1)))"))
        XCTAssertTrue(code.contains("self.rectangle_2 = Rectangle(pos=self.pos, size=self.size)"))
        XCTAssertTrue(code.contains("group_1.add(self.rectangle_2)"))
        XCTAssertTrue(code.contains("self.canvas.add(group_1)"))
        XCTAssertTrue(code.contains("self._conditional_0_canvas.append((self.canvas, group_1))"))
        XCTAssertTrue(code.contains("for (canvas, group) in getattr(self, \"_conditional_0_canvas\", []):\n            canvas.remove(group)"))
        
        // Nested block: bound inside the outer method, reset by the outer reset.
        XCTAssertTrue(code.contains("from kivy.app import App"))
        XCTAssertTrue(code.contains("def _conditional_0(self, parent, *args):\n        self._conditional_0_reset()\n        app = App.get_running_app()"))
        XCTAssertTrue(code.contains("self._conditional_1(parent)"))
        XCTAssertTrue(code.contains("app.bind(dark=_callback_2)"))
        XCTAssertTrue(code.contains("self._conditional_0_bindings.append((app, \"dark\", _callback_2))"))
        XCTAssertTrue(code.contains("self._conditional_0_canvas = []\n        self._conditional_1_reset()"))
        
        // Outer method first; __del__ resets only the outer one.
        let outer = code.range(of: "def _conditional_0(")!.lowerBound
        let inner = code.range(of: "def _conditional_1(")!.lowerBound
        XCTAssertLessThan(outer, inner)
        XCTAssertTrue(code.contains("def __del__(self):\n        self._conditional_0_reset()\n        for"))
        
        // Callback names stay unique across canvas and nested block.
        XCTAssertEqual(code.components(separatedBy: "_callback_2 = ").count, 2)
    }
    
    func testBranchPropertyIsAssignedOnSelf() throws {
        let code = try generate("""
        <W@Widget>:
            if self.disabled:
                pass_marker: 1
            else:
                Label:
                    text: "x"
        """)
        XCTAssertTrue(code.contains("if self.disabled:\n            self.pass_marker = 1"))
    }
}
