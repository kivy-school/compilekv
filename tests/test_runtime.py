"""The wasm module and its string-passing ABI."""

import pytest

from compilekv import KvCompiler, KvCompileError
from compilekv.runtime import WASM_FILENAME, _default_wasm_path

from conftest import ALL_KV, CHILDREN_KV, SIMPLE_KV


def test_wasm_asset_ships_with_the_package():
    path = _default_wasm_path()
    assert path.is_file(), f"{WASM_FILENAME} missing from the installed package"
    assert path.read_bytes()[:4] == b"\0asm"


def test_distribution_is_platform_independent():
    """One pure-Python wheel for every platform -- the reason for wasm."""
    from importlib.metadata import PackageNotFoundError, distribution

    try:
        wheel = distribution("compilekv").read_text("WHEEL")
    except PackageNotFoundError:  # pragma: no cover - running from a source tree
        pytest.skip("compilekv is not installed as a distribution")
    if wheel is None:  # pragma: no cover - editable install
        pytest.skip("no WHEEL metadata available")

    assert "Root-Is-Purelib: true" in wheel
    assert "Tag: py3-none-any" in wheel


def test_no_compiled_extensions_are_shipped():
    """Nothing compiled for a host arch."""
    package_dir = _default_wasm_path().parent
    suffixes = {p.suffix for p in package_dir.iterdir() if p.is_file()}

    assert not suffixes & {".so", ".dylib", ".dll", ".pyd"}


def test_missing_wasm_raises_a_useful_error(tmp_path):
    with pytest.raises(FileNotFoundError, match="wasm module not found"):
        KvCompiler(tmp_path / "nope.wasm")


def test_generates_a_class_per_rule(compiler):
    output = compiler.compile_source(SIMPLE_KV)
    assert "class MyButton(Button):" in output
    assert 'self.text = "Hello World"' in output
    assert "from kivy.uix.button import Button" in output


def test_generates_bindings_for_children(compiler):
    output = compiler.compile_source(CHILDREN_KV)
    assert "class MyWidget(BoxLayout):" in output
    assert "app = App.get_running_app()" in output
    assert "app.bind(some_prop=" in output
    assert "app.handle_click()" in output


@pytest.mark.parametrize("name", sorted(ALL_KV))
def test_every_fixture_compiles(compiler, name):
    output = compiler.compile_source(ALL_KV[name])
    assert output.strip()
    assert "class " in output


def test_invalid_kv_raises_with_the_parser_message(compiler):
    with pytest.raises(KvCompileError) as excinfo:
        compiler.compile_source("<Broken\n    bad ::: syntax\n")
    assert "Line 1" in str(excinfo.value)


def test_error_does_not_poison_the_instance(compiler):
    """A failure must leave the module usable."""
    expected = compiler.compile_source(SIMPLE_KV)
    with pytest.raises(KvCompileError):
        compiler.compile_source("<Broken\n    bad ::: syntax\n")
    assert compiler.compile_source(SIMPLE_KV) == expected


def test_empty_source_is_not_an_error(compiler):
    assert compiler.compile_source("") == ""


def test_non_ascii_survives_the_boundary(compiler):
    """Strings cross as UTF-8 bytes."""
    output = compiler.compile_source("<Greeting@Label>:\n    text: 'héllo wörld — 日本語'\n")
    assert "héllo wörld — 日本語" in output


def test_repeated_calls_are_stable(compiler):
    """Exercise alloc/free repeatedly."""
    first = compiler.compile_source(CHILDREN_KV)
    for _ in range(50):
        assert compiler.compile_source(CHILDREN_KV) == first


def test_large_input(compiler):
    """Big enough to grow linear memory."""
    source = "".join(
        f"<Widget{i}@BoxLayout>:\n    orientation: 'vertical'\n    spacing: {i}\n\n"
        for i in range(500)
    )
    output = compiler.compile_source(source)
    assert "class Widget0(BoxLayout):" in output
    assert "class Widget499(BoxLayout):" in output


def test_instances_are_independent():
    """Each KvCompiler owns its own store and memory."""
    a, b = KvCompiler(), KvCompiler()
    assert a.compile_source(SIMPLE_KV) == b.compile_source(SIMPLE_KV)


def test_output_is_deterministic(compiler):
    """Names used to come from UUID(), rewriting every file on every run."""
    assert compiler.compile_source(CHILDREN_KV) == compiler.compile_source(CHILDREN_KV)


def test_generated_names_are_stable_across_instances():
    """Two fresh modules must agree, not just two calls into one."""
    assert KvCompiler().compile_source(CHILDREN_KV) == KvCompiler().compile_source(CHILDREN_KV)


def test_generated_names_are_numbered_not_random(compiler):
    output = compiler.compile_source(CHILDREN_KV)
    assert "label_1 = Label(" in output
    assert "button_2 = Button(" in output


def test_compiled_module_is_cached_across_instances():
    """Compiling the wasm must happen once per process."""
    from compilekv.runtime import _compile_module

    KvCompiler()
    before = _compile_module.cache_info()
    KvCompiler()
    after = _compile_module.cache_info()

    assert after.hits == before.hits + 1
    assert after.misses == before.misses


def test_default_compiler_is_shared():
    """Every importer lands on one instance."""
    from compilekv import default_compiler

    assert default_compiler() is default_compiler()


def test_module_helpers_reuse_the_default_compiler(tmp_path, monkeypatch):
    """compile_file must not build a fresh compiler per call."""
    import compilekv.runtime as runtime
    from compilekv import compile_file, default_compiler

    default_compiler()  # ensure it exists before we start counting
    built = 0
    real = runtime.KvCompiler

    def counting(*args, **kwargs):
        nonlocal built
        built += 1
        return real(*args, **kwargs)

    monkeypatch.setattr(runtime, "KvCompiler", counting)

    for name in ("a", "b", "c"):
        kv = tmp_path / f"{name}.kv"
        kv.write_text(SIMPLE_KV)
        compile_file(kv)

    assert built == 0
