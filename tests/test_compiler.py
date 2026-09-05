"""Tests for the file level API: discovery, reading, writing, regeneration."""

from compilekv import compile_file, compile_tree, find_kv_files, output_path_for

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
