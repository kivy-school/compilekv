"""`name: |` blocks: the value is a function body, not an expression."""

import ast

import pytest

from test_conditionals import reactive_kivy  # noqa: F401  (fixture)

STATUS_KV = """\
<StatusLabel@Label>:
    error: False
    text: |
        if self.error:
            return "failed"
        return "ok"
    on_error: |
        if self.error:
            self.font_size = 18
        else:
            self.font_size = 14
        self.log.append(inner.text)
    Button:
        id: inner
        text: |
            return "pressed" if self.state == "down" else "released"
        on_press: |
            # toggle the root
            root.error = not root.error
"""


def generated(compiler, kv):
    out = compiler.compile_source(kv)
    ast.parse(out)
    return out


def load(compiler, kv, class_name):
    namespace = {}
    exec(compile(compiler.compile_source(kv), "generated.py", "exec"), namespace)
    return namespace[class_name]


def test_a_value_block_is_a_function(compiler):
    out = generated(compiler, STATUS_KV)
    assert 'def _value_1():\n            if self.error:\n                return "failed"\n            return "ok"' in out
    assert "self.text = _value_1()" in out


def test_a_handler_block_at_rule_level_is_a_method(compiler):
    out = generated(compiler, STATUS_KV)
    assert "def _on_error_handler(self, instance):" in out
    assert '        inner = self.ids["inner"]\n        if self.error:\n            self.font_size = 18' in out


def test_a_handler_block_on_a_child_is_a_nested_function(compiler):
    out = generated(compiler, STATUS_KV)
    assert "def _callback_2(instance):\n            self.error = not self.error" in out
    assert "inner.bind(on_press=_callback_2)" in out


def test_a_value_block_re_evaluates(compiler, reactive_kivy):
    widget = load(compiler, STATUS_KV, "StatusLabel")()
    assert widget.text == "ok"
    widget.error = True
    assert widget.text == "failed"

    inner = widget.ids["inner"]
    assert inner.text == "released"
    inner.state = "down"
    assert inner.text == "pressed"


def test_a_handler_block_runs_as_written(compiler, reactive_kivy):
    widget = load(compiler, STATUS_KV, "StatusLabel")()
    widget.log = []

    widget._on_error_handler(widget)
    assert widget.font_size == 14
    assert widget.log == ["released"]

    # The child's on_press flips root.error, which the value block follows.
    inner = widget.ids["inner"]
    for callback in inner._callbacks["on_press"]:
        callback(inner)
    assert widget.error is True
    assert widget.text == "failed"


def test_a_canvas_block_binds(compiler, reactive_kivy):
    kv = (
        "<Painted@Widget>:\n"
        "    canvas:\n"
        "        Color:\n"
        "            rgba: |\n"
        "                if self.disabled:\n"
        "                    return 0.5, 0.5, 0.5, 1\n"
        "                return 1, 1, 1, 1\n"
    )
    widget = load(compiler, kv, "Painted")()
    color = widget.canvas.items[0]
    assert color.rgba == (1, 1, 1, 1)
    widget.disabled = True
    assert color.rgba == (0.5, 0.5, 0.5, 1)


def test_set_constants_are_substituted_in_blocks(compiler):
    kv = "#:set BIG 20\n\n<W@Label>:\n    on_press: |\n        self.font_size = BIG\n"
    assert "self.font_size = 20" in generated(compiler, kv)


def test_an_invalid_block_is_reported(compiler):
    kv = "<W@Label>:\n    text: |\n        return (\n"
    with pytest.raises(Exception, match="block value of 'text' is not valid Python"):
        compiler.compile_source(kv)


def test_a_pipe_in_an_expression_is_not_a_block(compiler):
    kv = "<W@Label>:\n    flags: self.a | self.b\n"
    assert "self.flags = (self.a | self.b)" in generated(compiler, kv)
