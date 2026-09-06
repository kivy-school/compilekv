"""`#:import`, ids, and the parse repairs a real project needed."""

import ast

import pytest

from compilekv import Project, collect_directives


def generated(compiler, kv, py="", directives=""):
    out = compiler.compile_source(kv, py, directives)
    ast.parse(out)
    return out


# --- #:import -------------------------------------------------------------


def test_an_import_directive_becomes_an_import(compiler):
    kv = (
        "#:import get_font_name carbonkivy.utils.get_font_name\n"
        "\n<Item@Label>:\n    font_name: get_font_name(1, 2)\n"
    )
    assert "from carbonkivy.utils import get_font_name" in generated(compiler, kv)


def test_a_spaced_import_directive_is_read(compiler):
    kv = "#: import helper pkg.mod.helper\n\n<Item@Label>:\n    text: helper()\n"
    assert "from pkg.mod import helper" in generated(compiler, kv)


def test_an_aliased_import_keeps_the_alias(compiler):
    kv = "#:import shortcut pkg.mod.long_name\n\n<Item@Label>:\n    text: shortcut()\n"
    assert "from pkg.mod import long_name as shortcut" in generated(compiler, kv)


def test_a_top_level_module_import(compiler):
    kv = "#:import os os\n\n<Item@Label>:\n    text: os.sep\n"
    assert "import os" in generated(compiler, kv)


def test_an_unused_import_directive_is_not_emitted(compiler):
    kv = "#:import unused pkg.mod.unused\n\n<Item@Label>:\n    text: 'x'\n"
    assert "pkg.mod" not in generated(compiler, kv)


def test_an_import_directive_from_another_file(compiler):
    """The directive lives elsewhere; KV shares one namespace."""
    kv = "<Item@Label>:\n    font_name: get_font_name(1, 2)\n"
    out = generated(compiler, kv, "", "#:import get_font_name carbonkivy.utils.get_font_name")
    assert "from carbonkivy.utils import get_font_name" in out


def test_directives_are_read_from_python_files(tmp_path):
    """KV inside Builder.load_string() carries directives the .kv files use."""
    (tmp_path / "behavior.py").write_text(
        'from kivy.lang import Builder\n\n'
        'Builder.load_string("""\n'
        "#:import RelativeLayout kivy.uix.relativelayout.RelativeLayout\n"
        '""")\n'
    )
    (tmp_path / "widget.kv").write_text("<Item@Label>:\n    text: 'x'\n")

    project = Project.scan(tmp_path)

    assert "#:import RelativeLayout kivy.uix.relativelayout.RelativeLayout" in project.directives
    assert len(project.kv_files) == 1


def test_collect_directives_does_not_repeat_a_line(tmp_path):
    for name in ("a.kv", "b.kv"):
        (tmp_path / name).write_text("#:set shared 1\n")
    assert collect_directives(sorted(tmp_path.iterdir())) == "#:set shared 1"


# --- ids ------------------------------------------------------------------


def test_an_id_is_published_as_a_dict_entry(compiler):
    """`self.ids.x = y` does not survive; hand written code reads the dict."""
    kv = "<Item@BoxLayout>:\n    Label:\n        id: title\n"
    out = generated(compiler, kv)
    assert 'self.ids["title"] = title' in out


def test_generated_code_refers_to_the_local_name(compiler):
    kv = "<Item@BoxLayout>:\n    width: title.width\n    Label:\n        id: title\n"
    out = generated(compiler, kv)
    assert "self.width = title.width" in out
    assert "self.ids.title" not in out


# --- Binding the rule's own properties -----------------------------------


def test_a_computed_rule_property_binds_through_a_callback(compiler):
    """A setter would assign the watched value itself, which is the wrong type."""
    kv = "<Item@BoxLayout>:\n    size_hint: (None, 0.9) if self.opacity else (1, 1)\n"
    out = generated(compiler, kv)
    assert 'self.setter("size_hint")' not in out
    assert "lambda instance, self_opacity: setattr(self, \"size_hint\"" in out


def test_a_plain_rule_property_still_uses_a_setter(compiler):
    kv = "<Item@BoxLayout>:\n    width: self.height\n"
    assert 'self.bind(height=self.setter("width"))' in generated(compiler, kv)


# --- Values the parser needed help with ----------------------------------


def test_a_float_written_with_a_trailing_dot(compiler):
    kv = "<Item@Label>:\n    canvas:\n        Rectangle:\n            pos: int(self.center_x / 2.), 0\n"
    out = generated(compiler, kv)
    assert "int((self.center_x / 2.0))" in out
    assert '"int' not in out


def test_a_value_that_reads_self_is_not_quoted(compiler):
    kv = "<Item@Label>:\n    canvas:\n        Rectangle:\n            size: self.texture_size\n"
    out = generated(compiler, kv)
    assert "size=self.texture_size" in out
