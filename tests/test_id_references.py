"""A rule property may name a child by id; KV does not care about order, Python does."""

import ast

import pytest

KV = """\
<Header@BoxLayout>:
    size_hint: None, None
    width: inner.width
    height: 40

    BoxLayout:
        id: inner
        padding: 16
"""


@pytest.fixture
def generated(compiler):
    out = compiler.compile_source(KV)
    ast.parse(out)
    return out.split("def __init__")[1].split("def __del__")[0]


def test_the_id_is_assigned_before_it_is_read(generated):
    assert generated.index("inner = BoxLayout(") < generated.index("self.width = inner.width")


def test_the_binding_comes_after_the_child_too(generated):
    assert generated.index("inner = BoxLayout(") < generated.index("inner.bind(width=")


def test_properties_that_need_no_child_stay_first(generated):
    assert generated.index("self.height = 40") < generated.index("inner = BoxLayout(")


def test_the_module_executes(compiler, fake_kivy):
    """The whole point: reading the id used to raise NameError."""
    namespace = {}
    exec(compile(compiler.compile_source(KV), "generated.py", "exec"), namespace)
    namespace["Header"]()


def test_a_deeply_nested_id_is_still_found(compiler):
    kv = (
        "<Header@BoxLayout>:\n"
        "    width: deep.width\n"
        "    BoxLayout:\n"
        "        BoxLayout:\n"
        "            id: deep\n"
    )
    out = compiler.compile_source(kv)
    ast.parse(out)
    body = out.split("def __init__")[1]
    assert body.index("deep = BoxLayout(") < body.index("self.width = deep.width")


def test_an_empty_rule_is_a_valid_class(compiler):
    """<Name>: with nothing under it still needs a body."""
    out = compiler.compile_source("<Blank@Label>:\n")
    ast.parse(out)
    assert "class Blank(Label):" in out
    assert "pass" in out
