"""Generated members fold into the author's class; nothing gets dropped."""

import ast

import pytest

KV = """\
<IntroScreen>:
    orientation: 'vertical'
    Label:
        text: root.label_text
"""

PY = '''"""Module docstring."""

from kivy.uix.boxlayout import BoxLayout
from kivy.properties import StringProperty


class IntroScreen(BoxLayout):
    """Class docstring."""

    label_text = StringProperty("Welcome!")
    subtitle_text = StringProperty("Subtitle.")
    seen: bool = False

    class Meta:
        version = 1

    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.counter = 0
        print("hand written setup")

    def bump(self):
        self.counter += 1
'''


@pytest.fixture
def merged(compiler):
    out = compiler.compile_source(KV, PY)
    ast.parse(out)
    return out


@pytest.mark.parametrize(
    "fragment",
    [
        'label_text = StringProperty("Welcome!")',
        'subtitle_text = StringProperty("Subtitle.")',
        "seen: bool = False",
        "class Meta:",
        "version = 1",
        "def bump(self):",
        "self.counter += 1",
        "Class docstring.",
    ],
)
def test_class_members_survive(merged, fragment):
    assert fragment in merged


def test_the_existing_init_body_is_kept(merged):
    init = merged.split("def __init__")[1].split("def bump")[0]
    assert "self.counter = 0" in init
    assert 'print("hand written setup")' in init


def test_generated_code_is_appended_to_the_existing_init(merged):
    init = merged.split("def __init__")[1].split("def bump")[0]
    assert init.index("self.counter = 0") < init.index("self._bindings = []")
    assert "self.add_widget(label_1)" in init


def test_super_is_called_once(merged):
    assert merged.count("super().__init__") == 1


def test_the_authors_signature_is_kept(compiler):
    py = PY.replace("def __init__(self, **kwargs):", "def __init__(self, tag=None, **kwargs):")
    out = compiler.compile_source(KV, py)

    tree = ast.parse(out)
    cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "IntroScreen")
    init = next(n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == "__init__")
    assert [a.arg for a in init.args.args] == ["self", "tag"]
    assert init.args.kwarg.arg == "kwargs"
    assert [ast.literal_eval(d) for d in init.args.defaults] == [None]


def test_regenerating_does_not_stack_the_widget_tree(compiler):
    first = compiler.compile_source(KV, PY)
    second = compiler.compile_source(KV, first)
    third = compiler.compile_source(KV, second)
    assert first == second == third
    assert second.count("self.add_widget(label_1)") == 1
    assert second.count("self._bindings = []") == 1


def test_a_property_the_author_declared_is_not_shadowed(compiler):
    """A rule property that would become ObjectProperty defers to the real one."""
    kv = "<Card@BoxLayout>:\n    custom: app.thing\n"
    py = (
        "from kivy.uix.boxlayout import BoxLayout\n"
        "from kivy.properties import StringProperty\n\n"
        "class Card(BoxLayout):\n"
        '    custom = StringProperty("")\n'
    )
    out = compiler.compile_source(kv, py)
    assert 'custom = StringProperty("")' in out
    assert "custom = ObjectProperty(None)" not in out


def test_a_class_with_only_pass_gains_a_body(compiler):
    py = "from kivy.uix.boxlayout import BoxLayout\n\nclass IntroScreen(BoxLayout):\n    pass\n"
    out = compiler.compile_source(KV, py)
    ast.parse(out)
    body = out.split("class IntroScreen(BoxLayout):")[1]
    assert "pass" not in body.split("def __del__")[0]
    assert "def __init__" in body


def test_an_init_without_super_stays_without_one(compiler):
    """The author's __init__ is appended to, not rewritten."""
    py = (
        "from kivy.uix.boxlayout import BoxLayout\n\n"
        "class IntroScreen(BoxLayout):\n"
        "    def __init__(self, **kwargs):\n"
        "        self.ready = True\n"
    )
    out = compiler.compile_source(KV, py)
    ast.parse(out)
    assert "super().__init__" not in out
    assert "self.ready = True" in out
