"""KV's `self` is the widget whose block it appears in, not the rule root."""

import ast

import pytest


def child_body(compiler, lines, py=""):
    kv = "<Card@BoxLayout>:\n    Label:\n" + "".join(f"        {l}\n" for l in lines)
    generated = compiler.compile_source(kv, py)
    ast.parse(generated)
    return generated.split("def __init__")[1].split("def __del__")[0]


def test_self_is_the_child_widget(compiler):
    body = child_body(compiler, ["text_size: self.width, None"])
    assert "label_1.text_size = (label_1.width, None)" in body
    assert "self.width" not in body


def test_self_binds_against_the_child(compiler):
    body = child_body(compiler, ["height: self.texture_size[1]"])
    assert "label_1.height = label_1.texture_size[1]" in body
    assert "label_1.bind(texture_size=" in body
    assert "self.bind(" not in body


def test_root_still_means_the_rule(compiler):
    body = child_body(compiler, ["text: root.width"])
    assert "label_1.text = self.width" in body
    assert "self.bind(width=" in body


def test_self_and_root_in_one_expression(compiler):
    body = child_body(compiler, ['text: f"{self.width}-{root.width}"'])
    assert "label_1.width" in body
    assert "self.width" in body
    assert "label_1.bind(width=" in body
    assert "self.bind(width=" in body


def test_a_non_property_on_the_child_is_not_bound(compiler):
    body = child_body(compiler, ["text: self.bogus_thing"])
    assert "label_1.text = label_1.bogus_thing" in body
    assert "bind(" not in body


def test_an_inherited_property_is_bound(compiler):
    """opacity comes from Widget, which Label inherits."""
    body = child_body(compiler, ["opacity: self.width"])
    assert 'label_1.bind(width=label_1.setter("opacity"))' in body


def test_nesting_restores_the_enclosing_self(compiler):
    kv = (
        "<Card@BoxLayout>:\n"
        "    BoxLayout:\n"
        "        Label:\n"
        "            text_size: self.width, None\n"
        "        size_hint_x: self.opacity\n"
    )
    generated = compiler.compile_source(kv)
    ast.parse(generated)
    assert "label_2.text_size = (label_2.width, None)" in generated
    assert "box_1.size_hint_x = box_1.opacity" in generated


def test_a_property_on_a_custom_widget_from_another_rule(compiler):
    kv = (
        "<Fancy@Label>:\n"
        "    text: 'x'\n\n"
        "<Card@BoxLayout>:\n"
        "    Fancy:\n"
        "        text_size: self.width, None\n"
        "        opacity: self.nope\n"
    )
    generated = compiler.compile_source(kv)
    ast.parse(generated)
    assert "bind(width=" in generated
    assert "bind(nope=" not in generated


def test_a_kivy_property_declared_in_python_is_bindable(compiler):
    py = (
        "from kivy.uix.label import Label\n"
        "from kivy.properties import StringProperty\n\n"
        "class Fancy(Label):\n"
        '    tag = StringProperty("")\n'
    )
    kv = "<Card@BoxLayout>:\n    Fancy:\n        text: self.tag\n"
    generated = compiler.compile_source(kv, py)
    ast.parse(generated)
    assert "bind(tag=" in generated


def test_a_plain_attribute_declared_in_python_is_not_bindable(compiler):
    py = "from kivy.uix.label import Label\n\nclass Fancy(Label):\n    tag = 'x'\n"
    kv = "<Card@BoxLayout>:\n    Fancy:\n        text: self.tag\n"
    generated = compiler.compile_source(kv, py)
    ast.parse(generated)
    assert "bind(tag=" not in generated


def test_an_unknown_widget_is_assumed_bindable(compiler):
    """Nothing can say what an external widget has, so do not silently skip."""
    kv = "<Card@BoxLayout>:\n    FromElsewhere:\n        text: self.whatever\n"
    generated = compiler.compile_source(kv)
    ast.parse(generated)
    assert "bind(whatever=" in generated
