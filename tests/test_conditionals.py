"""if/else and try/expect blocks, and the #:from and #:mode directives."""

import ast
import sys
import types

import pytest

from compilekv import collect_directives

PLAN_KV = """\
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


def generated(compiler, kv, py="", directives=""):
    out = compiler.compile_source(kv, py, directives)
    ast.parse(out)
    return out


@pytest.fixture
def reactive_kivy(monkeypatch):
    """A fake kivy whose bind() actually fires, so a block can re-evaluate."""

    class Property:
        def __init__(self, default=None):
            self.default = default

    class Widget:
        def __init__(self, **kwargs):
            object.__setattr__(self, "_callbacks", {})
            object.__setattr__(self, "children", [])
            object.__setattr__(self, "ids", {})
            object.__setattr__(self, "parent", None)
            object.__setattr__(self, "canvas", Canvas())
            for name, value in {"disabled": False, "width": 0, "opacity": 1, "pos": (0, 0), "size": (0, 0), "state": "normal"}.items():
                object.__setattr__(self, name, value)
            for name, value in type(self).__dict__.items():
                if isinstance(value, Property):
                    object.__setattr__(self, name, value.default)
            for name, value in kwargs.items():
                object.__setattr__(self, name, value)

        def __setattr__(self, name, value):
            object.__setattr__(self, name, value)
            for callback in list(self._callbacks.get(name, [])):
                callback(self, value)

        def add_widget(self, widget):
            self.children.append(widget)
            object.__setattr__(widget, "parent", self)

        def remove_widget(self, widget):
            self.children.remove(widget)
            object.__setattr__(widget, "parent", None)

        def clear_widgets(self):
            self.children.clear()

        def bind(self, **kwargs):
            for name, callback in kwargs.items():
                self._callbacks.setdefault(name, []).append(callback)

        def unbind(self, **kwargs):
            for name, callback in kwargs.items():
                self._callbacks.get(name, []).remove(callback)

        def setter(self, name):
            return lambda instance, value: setattr(self, name, value)

    class Canvas:
        """Collects instructions, added directly or inside `with canvas:`."""

        current = []

        def __init__(self):
            self.items = []

        def add(self, item):
            self.items.append(item)

        def remove(self, item):
            self.items.remove(item)

        def __enter__(self):
            Canvas.current.append(self)

        def __exit__(self, *exc):
            Canvas.current.pop()

    class Instruction:
        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            if Canvas.current:
                Canvas.current[-1].add(self)

    class InstructionGroup:
        def __init__(self):
            self.items = []

        def add(self, item):
            self.items.append(item)

    class Failing(Widget):
        def __init__(self, **kwargs):
            raise RuntimeError("cannot build")

    app = Widget(dark=False, name="app")
    App = types.SimpleNamespace(get_running_app=lambda: app)
    # Unknown widgets are read off the Factory at import time.
    factory = types.SimpleNamespace(register=lambda *args, **kwargs: None, Failing=Failing)

    for name, attrs in {
        "kivy": {},
        "kivy.uix": {},
        "kivy.uix.boxlayout": {"BoxLayout": Widget},
        "kivy.uix.label": {"Label": Widget},
        "kivy.uix.button": {"Button": Widget},
        "kivy.uix.widget": {"Widget": Widget},
        "kivy.app": {"App": App},
        "kivy.factory": {"Factory": factory},
        "kivy.properties": {"ObjectProperty": Property},
        "kivy.graphics": {
            "Color": Instruction,
            "Rectangle": Instruction,
            "InstructionGroup": InstructionGroup,
        },
    }.items():
        module = types.ModuleType(name)
        module.__dict__.update(attrs)
        monkeypatch.setitem(sys.modules, name, module)

    return types.SimpleNamespace(Widget=Widget, app=app)


def load(compiler, kv, class_name):
    namespace = {}
    exec(compile(compiler.compile_source(kv), "generated.py", "exec"), namespace)
    return namespace[class_name]


def texts(widget):
    return [child.text for child in widget.children]


# --- #:from and #:mode ------------------------------------------------------


def test_a_from_directive_becomes_an_import(compiler):
    kv = "#:from kivy.metrics import dp\n\n<Item@Label>:\n    padding: dp(4)\n"
    assert "from kivy.metrics import dp\n" in generated(compiler, kv)


def test_a_from_directive_keeps_its_alias(compiler):
    kv = "#:from pkg.mod import long_name as short\n\n<Item@Label>:\n    text: short()\n"
    assert "from pkg.mod import long_name as short" in generated(compiler, kv)


def test_an_unused_from_directive_is_not_emitted(compiler):
    kv = "#:from pkg.mod import unused\n\n<Item@Label>:\n    text: 'x'\n"
    assert "pkg.mod" not in generated(compiler, kv)


def test_from_directives_are_shared_between_files(compiler, tmp_path):
    (tmp_path / "theme.kv").write_text("#:from pkg.mod import helper\n")
    (tmp_path / "other.kv").write_text("#:mode carbonkivy\n")
    directives = collect_directives(sorted(tmp_path.iterdir()))

    assert directives == "#:from pkg.mod import helper"
    kv = "<Item@Label>:\n    text: helper()\n"
    assert "from pkg.mod import helper" in generated(compiler, kv, "", directives)


def test_a_mode_directive_is_accepted(compiler):
    kv = "#:mode carbonkivy\n\n<Item@Label>:\n    text: 'x'\n"
    assert "class Item(Label)" in generated(compiler, kv)


# --- if / else ----------------------------------------------------------------


def test_the_plan_example_generates_and_runs(compiler, reactive_kivy):
    widget = load(compiler, PLAN_KV, "MyWidget")()
    # disabled is None (falsy), other_state None, try succeeds.
    assert texts(widget) == ["press me", "success"]


def test_a_block_re_evaluates_when_its_property_changes(compiler, reactive_kivy):
    widget = load(compiler, PLAN_KV, "MyWidget")()

    widget.disabled = True
    assert texts(widget) == ["success", "no press"]

    widget.other_state = True
    assert texts(widget) == ["success", "no press", "extra press"]

    widget.disabled = False
    widget.other_state = False
    assert texts(widget) == ["success", "press me"]


def test_a_condition_on_a_plain_name_declares_a_property(compiler):
    out = generated(compiler, PLAN_KV)
    assert "other_state = ObjectProperty(None)" in out
    assert "self.bind(other_state=" in out


def test_branch_widgets_are_removed_with_their_bindings(compiler, reactive_kivy):
    kv = (
        "<Panel@BoxLayout>:\n"
        "    Label:\n"
        "        id: title\n"
        "        text: 'Title'\n"
        "    if self.disabled:\n"
        "        Label:\n"
        "            text: title.text + ' (off)'\n"
    )
    widget = load(compiler, kv, "Panel")()
    title = widget.ids["title"]

    widget.disabled = True
    assert texts(widget) == ["Title", "Title (off)"]
    title.text = "Head"
    assert texts(widget) == ["Head", "Head (off)"]

    widget.disabled = False
    assert texts(widget) == ["Head"]
    assert title._callbacks["text"] == [], "the branch's binding must be unbound with it"


def test_a_block_inside_a_child_binds_on_that_child(compiler, reactive_kivy):
    kv = (
        "<Panel@BoxLayout>:\n"
        "    BoxLayout:\n"
        "        id: body\n"
        "        if self.width > 400:\n"
        "            Label:\n"
        "                text: 'wide'\n"
        "        else:\n"
        "            Label:\n"
        "                text: 'narrow'\n"
    )
    widget = load(compiler, kv, "Panel")()
    body = widget.ids["body"]
    body.width = 100
    assert texts(body) == ["narrow"]
    body.width = 800
    assert texts(body) == ["wide"]


def test_branch_properties_and_canvas_apply_to_the_enclosing_widget(compiler, reactive_kivy):
    kv = (
        "<Panel@BoxLayout>:\n"
        "    if self.disabled:\n"
        "        opacity: 0.5\n"
        "        canvas:\n"
        "            Color:\n"
        "                rgba: 1, 0, 0, 1\n"
        "            Rectangle:\n"
        "                pos: self.pos\n"
        "                size: self.size\n"
    )
    widget = load(compiler, kv, "Panel")()
    assert widget.canvas.items == []

    widget.disabled = True
    assert widget.opacity == 0.5
    assert len(widget.canvas.items) == 1
    assert len(widget.canvas.items[0].items) == 2

    widget.disabled = False
    assert widget.canvas.items == []


def test_a_nested_block_is_torn_down_with_its_parent(compiler, reactive_kivy):
    kv = (
        "<Panel@BoxLayout>:\n"
        "    if self.disabled:\n"
        "        if app.dark:\n"
        "            Label:\n"
        "                text: 'dark'\n"
    )
    widget = load(compiler, kv, "Panel")()
    app = reactive_kivy.app

    widget.disabled = True
    assert texts(widget) == []
    app.dark = True
    assert texts(widget) == ["dark"]

    widget.disabled = False
    assert texts(widget) == []
    app.dark = False
    app.dark = True
    assert texts(widget) == [], "the nested block must not fire once its parent is gone"


# --- try / expect -------------------------------------------------------------


def test_try_falls_back_to_expect_when_the_branch_fails(compiler, reactive_kivy):
    kv = (
        "<Panel@BoxLayout>:\n"
        "    try:\n"
        "        Label:\n"
        "            text: 'first'\n"
        "        Failing:\n"
        "            text: 'boom'\n"
        "    expect:\n"
        "        Label:\n"
        "            text: 'failed'\n"
    )
    widget = load(compiler, kv, "Panel")()
    # The Label built before the failure is cleared out too.
    assert texts(widget) == ["failed"]


def test_except_is_accepted_for_expect(compiler):
    kv = "<Panel@BoxLayout>:\n    try:\n        Label:\n            text: 'a'\n    except:\n        Label:\n            text: 'b'\n"
    out = generated(compiler, kv)
    assert "except Exception:" in out
