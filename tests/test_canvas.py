"""Canvas layers are `with` blocks, and tracked instructions get bound."""

import ast

import pytest

RULE_CANVAS = """\
<Card@BoxLayout>:
    canvas.before:
        Color:
            rgba: (0.1, 0.11, 0.13, 1)
        Rectangle:
            pos: self.pos
            size: self.size
"""

CHILD_CANVAS = """\
<Card@BoxLayout>:
    BoxLayout:
        canvas.before:
            Color:
                rgba: (0.16, 0.18, 0.21, 1)
            RoundedRectangle:
                pos: self.pos
                size: self.size
                radius: [12]
"""


@pytest.fixture
def rule_canvas(compiler):
    out = compiler.compile_source(RULE_CANVAS)
    ast.parse(out)
    return out


@pytest.fixture
def child_canvas(compiler):
    out = compiler.compile_source(CHILD_CANVAS)
    ast.parse(out)
    return out


def test_the_layer_is_a_with_block(rule_canvas):
    assert "with self.canvas.before:" in rule_canvas
    assert ".canvas.before.add(" not in rule_canvas


def test_properties_are_constructor_arguments(rule_canvas):
    assert "self.rectangle_1 = Rectangle(pos=self.pos, size=self.size)" in rule_canvas


def test_an_untracked_instruction_stays_anonymous(rule_canvas):
    assert "Color(rgba=(0.1, 0.11, 0.13, 1))" in rule_canvas
    assert "= Color(" not in rule_canvas


def test_the_tracked_instruction_is_bound(rule_canvas):
    assert 'setattr(self.rectangle_1, "pos", value)' in rule_canvas
    assert "self.bind(pos=" in rule_canvas
    assert "self.bind(size=" in rule_canvas


def test_bindings_come_after_the_block(rule_canvas):
    body = rule_canvas.split("def __init__")[1]
    assert body.index("with self.canvas.before:") < body.index("self.bind(pos=")


def test_bindings_are_tracked_for_cleanup(rule_canvas):
    assert '_bindings.append((self, "pos"' in rule_canvas
    assert '_bindings.append((self, "size"' in rule_canvas


@pytest.mark.parametrize("layer,expected", [("before", "with self.canvas.before:"),
                                            ("after", "with self.canvas.after:")])
def test_each_layer_targets_its_own_attribute(compiler, layer, expected):
    kv = f"<Card@BoxLayout>:\n    canvas.{layer}:\n        Color:\n            rgba: (1, 0, 0, 1)\n"
    assert expected in compiler.compile_source(kv)


def test_the_plain_canvas_layer(compiler):
    kv = "<Card@BoxLayout>:\n    canvas:\n        Color:\n            rgba: (1, 0, 0, 1)\n"
    out = compiler.compile_source(kv)
    ast.parse(out)
    assert "with self.canvas:" in out


# --- Canvases on child widgets -------------------------------------------


def test_a_child_canvas_is_generated_at_all(child_canvas):
    assert "RoundedRectangle(" in child_canvas


def test_a_child_canvas_targets_the_child(child_canvas):
    assert "with box_1.canvas.before:" in child_canvas


def test_self_in_a_child_canvas_is_the_child(child_canvas):
    assert "pos=box_1.pos" in child_canvas
    assert "size=box_1.size" in child_canvas
    assert "box_1.bind(pos=" in child_canvas


def test_a_child_canvas_instruction_type_is_imported(child_canvas):
    assert "from kivy.graphics import Color, RoundedRectangle" in child_canvas


def test_static_canvas_properties_are_kept(child_canvas):
    assert "radius=[12]" in child_canvas


def test_canvas_output_is_idempotent(compiler):
    first = compiler.compile_source(CHILD_CANVAS)
    second = compiler.compile_source(CHILD_CANVAS, first)
    assert first == second
