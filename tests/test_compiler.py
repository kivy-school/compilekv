"""Tests for the file level API: discovery, reading, writing, regeneration."""

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
    """Compiling over previously generated output must not change it."""
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
    """A broken file surfaces the parser error rather than being skipped."""
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
    """Files are read and written as UTF-8 regardless of the platform default."""
    kv = tmp_path / "greeting.kv"
    kv.write_text("<Greeting@Label>:\n    text: 'héllo — 日本語'\n", encoding="utf-8")

    written = compile_file(kv, compiler=compiler)

    assert "héllo — 日本語" in written.read_text(encoding="utf-8")


def test_compile_tree_returns_paths_in_discovery_order(project, compiler):
    written = compile_tree(project, compiler=compiler)
    assert written == [output_path_for(p) for p in find_kv_files(project)]


def test_compile_file_overwrites_a_stale_generated_file(tmp_path, compiler):
    """Removing a rule from the .kv must drop its class from the output."""
    kv = tmp_path / "two.kv"
    kv.write_text(SIMPLE_KV + "\n<Extra@Label>:\n    text: 'gone soon'\n")
    target = compile_file(kv, compiler=compiler)
    assert "class Extra(Label):" in target.read_text()

    kv.write_text(SIMPLE_KV)
    compile_file(kv, compiler=compiler)

    assert "class Extra(Label):" not in target.read_text()
