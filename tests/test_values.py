"""KV property values are Python expressions, not strings."""

import ast

import pytest


def rule(compiler, line, py=""):
    generated = compiler.compile_source(f"<Card@BoxLayout>:\n    {line}\n", py)
    ast.parse(generated)
    return generated


def assignment(compiler, line, py=""):
    generated = rule(compiler, line, py)
    body = generated.split("def __init__")[1].split("def __del__")[0]
    return next(l.strip() for l in body.splitlines() if l.strip().startswith("self.") and "_bindings" not in l)


@pytest.mark.parametrize(
    "line,expected",
    [
        ("padding: dp(24)", "self.padding = dp(24)"),
        ("spacing: sp(20)", "self.spacing = sp(20)"),
        ("height: dp(40) + 2", "self.height = (dp(40) + 2)"),
        ("height: min(dp(40), 100)", "self.height = min(dp(40), 100)"),
        ("padding: dp(24), dp(12)", "self.padding = (dp(24), dp(12))"),
    ],
)
def test_a_call_stays_a_call(compiler, line, expected):
    assert assignment(compiler, line) == expected


@pytest.mark.parametrize(
    "line,expected",
    [
        ("size_hint: None, None", "self.size_hint = (None, None)"),
        ("background_color: 0.2, 0.6, 1, 1", "self.background_color = (0.2, 0.6, 1, 1)"),
        ("orientation: 'vertical'", 'self.orientation = "vertical"'),
        ("multiline: False", "self.multiline = False"),
        ("font_size: 18", "self.font_size = 18"),
    ],
)
def test_literals_are_unchanged(compiler, line, expected):
    assert assignment(compiler, line) == expected


@pytest.mark.parametrize(
    "line,expected",
    [
        ("color: (1, 1, 1, 1)", "self.color = (1, 1, 1, 1)"),
        ("pos: (10, 20)", "self.pos = (10, 20)"),
        ("size: 200, 50", "self.size = (200, 50)"),
        ("padding: [1, 2, 3, 4]", "self.padding = [1, 2, 3, 4]"),
        ("padding: (dp(4), dp(8))", "self.padding = (dp(4), dp(8))"),
    ],
)
def test_a_tuple_stays_a_tuple(compiler, line, expected):
    """Brackets around the value do not turn it into a string."""
    assert assignment(compiler, line) == expected


def test_a_bare_word_stays_a_string(compiler):
    """An unquoted KV word is a sloppy literal, not a module global."""
    assert assignment(compiler, "orientation: vertical") == 'self.orientation = "vertical"'


@pytest.mark.parametrize(
    "line,imported",
    [
        ("padding: dp(24)", "from kivy.metrics import dp"),
        ("font_size: sp(18)", "from kivy.metrics import sp"),
        ("padding: dp(24)\n    font_size: sp(18)", "from kivy.metrics import dp, sp"),
    ],
)
def test_metrics_helpers_are_imported(compiler, line, imported):
    assert imported in rule(compiler, line)


def test_no_metrics_import_when_unused(compiler):
    assert "kivy.metrics" not in rule(compiler, "padding: 24")


def test_an_existing_metrics_import_is_not_duplicated(compiler):
    existing = "from kivy.metrics import dp\nfrom kivy.uix.boxlayout import BoxLayout\n"
    generated = rule(compiler, "padding: dp(24)", existing)
    assert generated.count("from kivy.metrics import dp") == 1


def test_dp_on_a_child_widget(compiler):
    generated = compiler.compile_source(
        "<Card@BoxLayout>:\n    Label:\n        font_size: sp(18)\n        height: dp(40)\n"
    )
    ast.parse(generated)
    assert "sp(18)" in generated and "dp(40)" in generated
    assert '"sp' not in generated and '"dp' not in generated


def test_a_comma_inside_a_call_is_not_a_tuple_separator(compiler):
    assert assignment(compiler, "height: min(dp(40), 100)").count("(") == 2
