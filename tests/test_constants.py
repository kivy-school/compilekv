"""`#:set` directives, including ones defined in another KV file."""

import ast

import pytest

from compilekv import collect_constants, compile_tree

THEME = "#:set plex_16 sp(16)\n#:set plex_20 sp(20)\n#:set brand (0.29, 0.69, 0.31, 1)\n"


def assignment(compiler, line, constants="", py=""):
    kv = f"{constants}\n<Item@BoxLayout>:\n    {line}\n"
    generated = compiler.compile_source(kv, py)
    ast.parse(generated)
    body = generated.split("def __init__")[1].split("def __del__")[0]
    return next(
        l.strip()
        for l in body.splitlines()
        if l.strip().startswith("self.") and "_bindings" not in l
    )


def test_a_constant_is_substituted(compiler):
    assert assignment(compiler, "font_size: plex_16", THEME) == "self.font_size = sp(16)"


def test_a_constant_inside_an_expression(compiler):
    assert assignment(compiler, "height: plex_20 + 4", THEME) == "self.height = (sp(20) + 4)"


def test_a_constant_holding_a_tuple(compiler):
    kv = f"{THEME}\n<Item@Label>:\n    color: brand\n"
    assert "self.color = (0.29, 0.69, 0.31, 1)" in compiler.compile_source(kv)


def test_the_metrics_helper_a_constant_uses_is_imported(compiler):
    kv = f"{THEME}\n<Item@BoxLayout>:\n    font_size: plex_16\n"
    assert "from kivy.metrics import sp" in compiler.compile_source(kv)


def test_an_unknown_bare_word_is_still_a_string(compiler):
    assert assignment(compiler, "orientation: vertical", THEME) == 'self.orientation = "vertical"'


# --- Sharing across files -------------------------------------------------


def test_collect_constants_reads_the_set_lines(tmp_path):
    (tmp_path / "theme.kv").write_text(THEME + "<Ignored@Label>:\n    text: 'x'\n")
    collected = collect_constants([tmp_path / "theme.kv"])
    assert collected.splitlines() == THEME.strip().splitlines()


def test_collect_constants_ignores_other_directives(tmp_path):
    (tmp_path / "a.kv").write_text("#:kivy 2.0\n#:import os os\n#:set a 1\n")
    assert collect_constants([tmp_path / "a.kv"]) == "#:set a 1"


def test_a_constant_from_another_file_is_used(compiler):
    """theme.kv defines it, tab.kv uses it."""
    generated = compiler.compile_source(
        "<Item@BoxLayout>:\n    font_size: plex_16\n", "", THEME
    )
    ast.parse(generated)
    assert "self.font_size = sp(16)" in generated


def test_a_local_set_wins_over_a_shared_one(compiler):
    kv = "#:set plex_16 sp(99)\n\n<Item@BoxLayout>:\n    font_size: plex_16\n"
    assert "self.font_size = sp(99)" in compiler.compile_source(kv, "", THEME)


def test_compile_tree_shares_constants_between_files(tmp_path, compiler):
    (tmp_path / "theme.kv").write_text(THEME)
    (tmp_path / "widget.kv").write_text("<Item@BoxLayout>:\n    font_size: plex_16\n")

    written = compile_tree(tmp_path, tmp_path / "build", compiler=compiler)

    widget = next(p for p in written if p.name == "widget.py")
    assert "self.font_size = sp(16)" in widget.read_text()


# --- Cross referencing declared property types ---------------------------


DECLARED = """\
from kivy.uix.boxlayout import BoxLayout
from kivy.properties import NumericProperty, StringProperty


class Item(BoxLayout):
    my_size = NumericProperty()
    my_text = StringProperty()
"""


@pytest.mark.parametrize(
    "line,expected",
    [
        ("my_size: SOME_GLOBAL", "self.my_size = SOME_GLOBAL"),
        ("my_text: SOME_GLOBAL", 'self.my_text = "SOME_GLOBAL"'),
    ],
)
def test_a_bare_word_follows_the_declared_property_type(compiler, line, expected):
    """A NumericProperty can never hold a bare word as a string."""
    kv = f"<Item>:\n    {line}\n"
    generated = compiler.compile_source(kv, DECLARED)
    ast.parse(generated)
    assert expected in generated


def test_an_option_property_keeps_the_string(compiler):
    kv = "<Item@BoxLayout>:\n    orientation: vertical\n"
    assert 'self.orientation = "vertical"' in compiler.compile_source(kv)


def test_a_numeric_property_from_the_registry(compiler):
    """opacity is a NumericProperty on Widget, so a bare word is a name."""
    kv = "<Item@BoxLayout>:\n    opacity: SOME_GLOBAL\n"
    assert "self.opacity = SOME_GLOBAL" in compiler.compile_source(kv)
