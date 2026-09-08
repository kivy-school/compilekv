"""`root` in KV is the rule's own widget, and only properties can be bound."""

import ast

import pytest

BINDABLE_PY = """\
from kivy.uix.boxlayout import BoxLayout
from kivy.properties import NumericProperty, StringProperty


class Card(BoxLayout):
    title = StringProperty("")
    count = NumericProperty(0)
    plain = "static"
"""


def child(compiler, kv, py=BINDABLE_PY):
    generated = compiler.compile_source(kv, py)
    ast.parse(generated)
    return generated.split("def __init__")[1].split("def __del__")[0]


def test_root_becomes_self(compiler):
    body = child(compiler, "<Card>:\n    Label:\n        text: root.title\n")
    assert "label_1.text = self.title" in body
    assert "root" not in body


def test_a_property_is_bound(compiler):
    body = child(compiler, "<Card>:\n    Label:\n        text: root.title\n")
    assert 'self.bind(title=label_1.setter("text"))' in body


def test_a_plain_attribute_is_only_assigned(compiler):
    body = child(compiler, "<Card>:\n    Label:\n        text: root.plain\n")
    assert "label_1.text = self.plain" in body
    assert "self.bind(" not in body


def test_an_inherited_property_is_bound_without_a_python_file(compiler):
    body = child(compiler, "<Card>:\n    Label:\n        width: root.size_hint_x\n", py="")
    assert "self.bind(size_hint_x=" in body


def test_an_unknown_attribute_is_only_assigned_without_a_python_file(compiler):
    body = child(compiler, "<Card>:\n    Label:\n        text: root.whatever\n", py="")
    assert "label_1.text = self.whatever" in body
    assert "self.bind(" not in body


def test_a_generated_object_property_is_bindable(compiler):
    """A rule property that itself needs binding becomes an ObjectProperty."""
    kv = "<Card@BoxLayout>:\n    custom: app.thing\n    Label:\n        text: root.custom\n"
    generated = compiler.compile_source(kv)
    assert "custom = ObjectProperty(None)" in generated
    assert 'self.bind(custom=label_1.setter("text"))' in generated


def test_a_constant_rule_property_is_a_plain_attribute(compiler):
    """No ObjectProperty is declared for a constant, so there is nothing to bind."""
    kv = "<Card@BoxLayout>:\n    custom: 1\n    Label:\n        text: root.custom\n"
    generated = compiler.compile_source(kv)
    assert "ObjectProperty" not in generated
    assert "label_1.text = self.custom" in generated
    assert "self.bind(" not in generated


def test_root_on_the_rule_itself(compiler):
    body = child(compiler, "<Card>:\n    orientation: root.title\n")
    assert "self.orientation = self.title" in body
    assert 'self.bind(title=self.setter("orientation"))' in body


def test_root_inside_an_f_string(compiler):
    body = child(compiler, '<Card>:\n    Label:\n        text: f"{root.title}!"\n')
    assert 'label_1.text = f"{self.title}!"' in body
    assert "self.bind(title=_callback_0)" in body


def test_a_plain_attribute_stays_inline_in_an_f_string(compiler):
    """The bindable half binds; the plain half is read once, in place."""
    body = child(compiler, '<Card>:\n    Label:\n        text: f"{root.title}-{root.plain}"\n')
    assert body.count("self.bind(") == 1
    assert "self.bind(title=" in body
    assert "self.plain" in body


@pytest.mark.parametrize(
    "value", ["str(root.count)", 'f"{root.count}{root.count}"']
)
def test_a_property_named_twice_binds_once(compiler, value):
    body = child(compiler, f"<Card>:\n    Label:\n        text: {value}\n")
    assert body.count("self.bind(count=") == 1


def test_root_method_calls_still_work(compiler):
    body = child(compiler, "<Card>:\n    Button:\n        on_press: root.go()\n")
    assert "lambda instance: self.go()" in body
