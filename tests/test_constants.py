"""`#:set` directives, including ones defined in another KV file."""

import ast

import pytest

from compilekv import collect_directives, compile_tree

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


def test_collect_directives_reads_the_set_lines(tmp_path):
    (tmp_path / "theme.kv").write_text(THEME + "<Ignored@Label>:\n    text: 'x'\n")
    collected = collect_directives([tmp_path / "theme.kv"])
    assert collected.splitlines() == THEME.strip().splitlines()


def test_collect_directives_keeps_set_and_import(tmp_path):
    (tmp_path / "a.kv").write_text("#:kivy 2.0\n#:import os os\n#:set a 1\n")
    assert collect_directives([tmp_path / "a.kv"]).splitlines() == ["#:import os os", "#:set a 1"]


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


# --- Scanning before generating ------------------------------------------


def test_project_scan_gathers_every_file(tmp_path):
    from compilekv import Project

    (tmp_path / "a.kv").write_text("#:set a 1\n<A@Label>:\n    text: 'x'\n")
    (tmp_path / "nested").mkdir()
    (tmp_path / "nested" / "theme.kv").write_text("#:set b 2\n")

    project = Project.scan(tmp_path)

    assert len(project.kv_files) == 2
    assert "#:set a 1" in project.directives
    assert "#:set b 2" in project.directives


def test_a_constant_from_a_file_scanned_later_still_applies(tmp_path, compiler):
    """theme.kv sorts after widget.kv, so ordering must not matter."""
    (tmp_path / "widget.kv").write_text("<Item@BoxLayout>:\n    font_size: plex_16\n")
    (tmp_path / "zz_theme.kv").write_text("#:set plex_16 sp(16)\n")

    written = compile_tree(tmp_path, tmp_path / "build", compiler=compiler)

    widget = next(p for p in written if p.name == "widget.py")
    assert "self.font_size = sp(16)" in widget.read_text()


def test_the_module_entry_point_shares_constants(tmp_path):
    import subprocess
    import sys

    (tmp_path / "widget.kv").write_text("<Item@BoxLayout>:\n    font_size: plex_16\n")
    (tmp_path / "zz_theme.kv").write_text("#:set plex_16 sp(16)\n")
    out = tmp_path / "build"

    result = subprocess.run(
        [sys.executable, "-m", "compilekv", str(tmp_path), "-o", str(out)],
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert "self.font_size = sp(16)" in (out / "widget.py").read_text()


# --- Values written across several lines ---------------------------------


def test_a_value_continued_over_lines(compiler):
    kv = (
        "#:set plex_16 sp(16)\n"
        "#:set plex_20 sp(20)\n"
        "\n"
        "<Item@Label>:\n"
        "    font_size:\n"
        "        { \\\n"
        '        "Small": plex_16, \\\n'
        '        "Large": plex_20, \\\n'
        "        }[self.parent.role]\n"
    )
    generated = compiler.compile_source(kv)
    ast.parse(generated)
    assert '{"Small": sp(16), "Large": sp(20)}[self.parent.role]' in generated


def test_a_backslash_inside_a_string_is_left_alone(compiler):
    """Continuations are only stripped when the value will not parse as written."""
    kv = '<Item@Label>:\n    text: "a\\\\nb"\n'
    generated = compiler.compile_source(kv)
    ast.parse(generated)
    assert "\\\\n" in generated
