import pytest

from compilekv import KvCompiler

SIMPLE_KV = """\
<MyButton@Button>:
    text: 'Hello World'
    size_hint: 0.5, 0.5
"""

CHILDREN_KV = """\
<MyWidget@BoxLayout>:
    orientation: 'vertical'
    Label:
        text: app.some_prop
        font_size: 20
    Button:
        text: 'Click Me'
        on_press: app.handle_click()
"""

CANVAS_KV = """\
<Painted@Widget>:
    canvas:
        Color:
            rgb: 1, 0, 0
        Rectangle:
            pos: self.pos
            size: self.size
"""

ALL_KV = {"simple": SIMPLE_KV, "children": CHILDREN_KV, "canvas": CANVAS_KV}


@pytest.fixture(scope="session")
def compiler() -> KvCompiler:
    return KvCompiler()


@pytest.fixture
def project(tmp_path):
    """A directory of .kv files, one of them nested."""
    (tmp_path / "simple.kv").write_text(SIMPLE_KV)
    (tmp_path / "children.kv").write_text(CHILDREN_KV)
    nested = tmp_path / "nested"
    nested.mkdir()
    (nested / "canvas.kv").write_text(CANVAS_KV)
    return tmp_path


@pytest.fixture
def fake_kivy(monkeypatch):
    """Enough of kivy in sys.modules to import and run generated code."""
    import sys
    import types

    class Ids(dict):
        """Kivy's ids: a dict that also reads back as attributes."""

        def __getattr__(self, name):
            try:
                return self[name]
            except KeyError as error:
                raise AttributeError(name) from error

    class Widget:
        def __init__(self, **kwargs):
            self.__dict__.update(kwargs)
            self.children = []
            self.ids = Ids()
            self.width = 0

        def add_widget(self, widget):
            self.children.append(widget)

        def clear_widgets(self):
            self.children.clear()

        def bind(self, **kwargs):
            pass

        def unbind(self, **kwargs):
            pass

        def setter(self, name):
            return lambda *args: None

    factory = types.SimpleNamespace(register=lambda *args, **kwargs: None)
    for name, attrs in {
        "kivy": {},
        "kivy.uix": {},
        "kivy.uix.boxlayout": {"BoxLayout": Widget},
        "kivy.uix.label": {"Label": Widget},
        "kivy.factory": {"Factory": factory},
    }.items():
        module = types.ModuleType(name)
        module.__dict__.update(attrs)
        monkeypatch.setitem(sys.modules, name, module)

    return Widget
