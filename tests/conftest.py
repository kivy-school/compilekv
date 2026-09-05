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
