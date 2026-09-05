"""The file level API: discovery, reading, writing, regeneration."""

import pytest

from compilekv import (
    KvCompileError,
    compile_file,
    compile_tree,
    find_kv_files,
    output_path_for,
)

from conftest import CHILDREN_KV, SIMPLE_KV


def test_output_path_for_swaps_the_suffix(tmp_path):
    assert output_path_for(tmp_path / "style.kv") == tmp_path / "style.py"


def test_compile_file_writes_beside_the_kv(tmp_path, compiler):
    kv = tmp_path / "simple.kv"
    kv.write_text(SIMPLE_KV)

    written = compile_file(kv, compiler=compiler)

    assert written == tmp_path / "simple.py"
    assert "class MyButton(Button):" in written.read_text()


def test_compile_file_honours_an_explicit_output(tmp_path, compiler):
    kv = tmp_path / "simple.kv"
    kv.write_text(SIMPLE_KV)
    target = tmp_path / "elsewhere" / "generated.py"
    target.parent.mkdir()

    written = compile_file(kv, target, compiler=compiler)

    assert written == target
    assert "class MyButton(Button):" in target.read_text()


def test_regenerating_is_idempotent(tmp_path, compiler):
    """Compiling over generated output must not change it."""
    kv = tmp_path / "children.kv"
    kv.write_text(CHILDREN_KV)

    target = compile_file(kv, compiler=compiler)
    first = target.read_text()
    compile_file(kv, compiler=compiler)
    second = target.read_text()
    compile_file(kv, compiler=compiler)
    third = target.read_text()

    assert first == second == third


def test_regenerating_does_not_duplicate_generated_methods(tmp_path, compiler):
    kv = tmp_path / "children.kv"
    kv.write_text(CHILDREN_KV)

    target = compile_file(kv, compiler=compiler)
    compile_file(kv, compiler=compiler)

    assert target.read_text().count("def __del__") == 1
    assert target.read_text().count("def __init__") == 1


def test_hand_written_methods_are_preserved(tmp_path, compiler):
    kv = tmp_path / "simple.kv"
    kv.write_text(SIMPLE_KV)
    (tmp_path / "simple.py").write_text(
        "class MyButton(Button):\n"
        "    def on_release(self):\n"
        "        return 'kept'\n"
    )

    target = compile_file(kv, compiler=compiler)
    output = target.read_text()

    assert "def on_release" in output
    assert "return 'kept'" in output or 'return "kept"' in output
    assert "class MyButton(Button):" in output


def test_hand_written_methods_survive_repeated_runs(tmp_path, compiler):
    kv = tmp_path / "simple.kv"
    kv.write_text(SIMPLE_KV)
    (tmp_path / "simple.py").write_text(
        "class MyButton(Button):\n"
        "    def on_release(self):\n"
        "        return 'kept'\n"
    )

    target = compile_file(kv, compiler=compiler)
    for _ in range(3):
        compile_file(kv, compiler=compiler)

    assert target.read_text().count("def on_release") == 1


def test_find_kv_files_recurses_by_default(project):
    found = {p.name for p in find_kv_files(project)}
    assert found == {"simple.kv", "children.kv", "canvas.kv"}


def test_find_kv_files_can_stay_shallow(project):
    found = {p.name for p in find_kv_files(project, recursive=False)}
    assert found == {"simple.kv", "children.kv"}


def test_find_kv_files_accepts_a_single_file(project):
    kv = project / "simple.kv"
    assert find_kv_files(kv) == [kv]


def test_compile_tree_writes_every_file(project, compiler):
    written = compile_tree(project, compiler=compiler)

    assert {p.name for p in written} == {"simple.py", "children.py", "canvas.py"}
    assert all(p.is_file() and p.read_text().strip() for p in written)


def test_compile_tree_can_stay_shallow(project, compiler):
    written = compile_tree(project, recursive=False, compiler=compiler)

    assert {p.name for p in written} == {"simple.py", "children.py"}
    assert not (project / "nested" / "canvas.py").exists()


def test_compile_file_reports_a_missing_kv(tmp_path, compiler):
    with pytest.raises(FileNotFoundError):
        compile_file(tmp_path / "absent.kv", compiler=compiler)


def test_compile_tree_raises_on_invalid_kv(tmp_path, compiler):
    """A broken file surfaces the parser error."""
    (tmp_path / "bad.kv").write_text("<Broken\n    bad ::: syntax\n")

    with pytest.raises(KvCompileError, match="Line 1"):
        compile_tree(tmp_path, compiler=compiler)


def test_compile_tree_on_an_empty_directory(tmp_path, compiler):
    assert compile_tree(tmp_path, compiler=compiler) == []


def test_find_kv_files_on_an_empty_directory(tmp_path):
    assert find_kv_files(tmp_path) == []


def test_find_kv_files_on_a_missing_directory(tmp_path):
    assert find_kv_files(tmp_path / "absent") == []


def test_find_kv_files_ignores_other_suffixes(tmp_path):
    (tmp_path / "style.kv").write_text(SIMPLE_KV)
    (tmp_path / "notes.txt").write_text("x")
    (tmp_path / "style.py").write_text("x")

    assert [p.name for p in find_kv_files(tmp_path)] == ["style.kv"]


def test_find_kv_files_returns_a_stable_order(project):
    assert find_kv_files(project) == find_kv_files(project)


def test_non_ascii_survives_the_file_layer(tmp_path, compiler):
    """Read and written as UTF-8 regardless of platform default."""
    kv = tmp_path / "greeting.kv"
    kv.write_text("<Greeting@Label>:\n    text: 'héllo — 日本語'\n", encoding="utf-8")

    written = compile_file(kv, compiler=compiler)

    assert "héllo — 日本語" in written.read_text(encoding="utf-8")


def test_compile_tree_returns_paths_in_discovery_order(project, compiler):
    written = compile_tree(project, compiler=compiler)
    assert written == [output_path_for(p) for p in find_kv_files(project)]


def test_writing_in_place_keeps_a_class_whose_rule_was_removed(tmp_path, compiler):
    """In place, the file is extended, so nothing is deleted from it.

    Once generated output and hand written source are the same file there is
    no way to tell a class we emitted last run from one the author added, so
    dropping a rule leaves its class behind. Compile into a separate output
    directory to get a file that only ever reflects the current .kv.
    """
    kv = tmp_path / "two.kv"
    kv.write_text(SIMPLE_KV + "\n<Extra@Label>:\n    text: 'gone soon'\n")
    target = compile_file(kv, compiler=compiler)
    assert "class Extra(Label):" in target.read_text()

    kv.write_text(SIMPLE_KV)
    compile_file(kv, compiler=compiler)

    assert "class Extra(Label):" in target.read_text()


def test_output_directory_drops_a_class_whose_rule_was_removed(tmp_path, compiler):
    """With a separate output dir the source .py is untouched, so nothing lingers."""
    kv = tmp_path / "two.kv"
    out = tmp_path / "build"
    kv.write_text(SIMPLE_KV + "\n<Extra@Label>:\n    text: 'gone soon'\n")
    target = compile_file(kv, out, compiler=compiler)
    assert "class Extra(Label):" in target.read_text()

    kv.write_text(SIMPLE_KV)
    compile_file(kv, out, compiler=compiler)

    assert "class Extra(Label):" not in target.read_text()


# --- Output directories ---------------------------------------------------


def test_output_path_for_treats_a_suffixless_path_as_a_directory(tmp_path):
    assert output_path_for(tmp_path / "a.kv", tmp_path / "build") == tmp_path / "build" / "a.py"


def test_output_path_for_keeps_an_explicit_file_name(tmp_path):
    assert output_path_for(tmp_path / "a.kv", tmp_path / "out.py") == tmp_path / "out.py"


def test_output_directory_names_each_file_after_its_kv(tmp_path, compiler):
    (tmp_path / "abc.kv").write_text(SIMPLE_KV)
    (tmp_path / "xyz.kv").write_text(CHILDREN_KV)
    out = tmp_path / "build"

    written = compile_tree(tmp_path, out, compiler=compiler)

    assert sorted(p.name for p in written) == ["abc.py", "xyz.py"]
    assert all(p.parent == out for p in written)


def test_output_directory_mirrors_nested_layout(project, compiler):
    out = project / "build"
    written = compile_tree(project, out, compiler=compiler)
    relative = sorted(str(p.relative_to(out)) for p in written)
    assert relative == sorted(
        str(kv.relative_to(project).with_suffix(".py")) for kv in find_kv_files(project)
    )


def test_output_directory_is_created(tmp_path, compiler):
    (tmp_path / "a.kv").write_text(SIMPLE_KV)
    target = compile_file(tmp_path / "a.kv", tmp_path / "deep" / "nested", compiler=compiler)
    assert target == tmp_path / "deep" / "nested" / "a.py"
    assert target.is_file()


def test_output_directory_leaves_the_source_py_alone(tmp_path, compiler):
    (tmp_path / "a.kv").write_text(SIMPLE_KV)
    source = tmp_path / "a.py"
    source.write_text("MARKER = 1\n")

    compile_file(tmp_path / "a.kv", tmp_path / "build", compiler=compiler)

    assert source.read_text() == "MARKER = 1\n"


def test_the_kv_neighbour_is_the_source_even_with_an_output_dir(tmp_path, compiler):
    """abc.py next to abc.kv is what gets extended, not whatever is in the output."""
    (tmp_path / "abc.kv").write_text(SIMPLE_KV)
    (tmp_path / "abc.py").write_text("MARKER = 1\n")

    target = compile_file(tmp_path / "abc.kv", tmp_path / "build", compiler=compiler)

    assert target.name == "abc.py"
    assert "MARKER = 1" in target.read_text()


# --- Extending the existing module ---------------------------------------


EXISTING_PY = '''"""Docstring."""

import os
from kivy.uix.boxlayout import BoxLayout

MAX = 10


def helper():
    return os.getcwd()


class Other:
    pass


class UserProfile(BoxLayout):
    def save_profile(self):
        return MAX
'''

EXISTING_KV = """\
<UserProfile>:
    orientation: 'vertical'
    Label:
        text: 'hi'
"""


@pytest.fixture
def extended(tmp_path, compiler):
    (tmp_path / "app.kv").write_text(EXISTING_KV)
    (tmp_path / "app.py").write_text(EXISTING_PY)
    return compile_file(tmp_path / "app.kv", tmp_path / "build", compiler=compiler).read_text()


@pytest.mark.parametrize(
    "fragment",
    ["import os", "MAX = 10", "def helper():", "return os.getcwd()", "class Other:"],
)
def test_module_level_code_is_preserved(extended, fragment):
    assert fragment in extended


def test_base_class_comes_from_the_existing_python(extended):
    assert "class UserProfile(BoxLayout):" in extended


def test_existing_imports_are_not_duplicated(extended):
    assert extended.count("from kivy.uix.boxlayout import BoxLayout") == 1


def test_needed_imports_are_added(extended):
    assert "from kivy.uix.label import Label" in extended


def test_the_result_is_valid_python(extended):
    import ast

    ast.parse(extended)


def test_a_widget_base_is_imported(tmp_path, compiler):
    """<Name>: with no Python class falls back to Widget, which must be imported."""
    (tmp_path / "a.kv").write_text("<Orphan>:\n    Label:\n        text: 'x'\n")
    generated = compile_file(tmp_path / "a.kv", compiler=compiler).read_text()
    assert "class Orphan(Widget):" in generated
    assert "from kivy.uix.widget import Widget" in generated
