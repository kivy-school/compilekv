"""Tests for the wasm module and its string-passing ABI."""

import pytest

from compilekv import KvCompiler, KvCompileError
from compilekv.runtime import WASM_FILENAME, _default_wasm_path

from conftest import ALL_KV, CHILDREN_KV, SIMPLE_KV


def test_wasm_asset_ships_with_the_package():
    path = _default_wasm_path()
    assert path.is_file(), f"{WASM_FILENAME} missing from the installed package"
    assert path.read_bytes()[:4] == b"\0asm"


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
    """A failed conversion must leave the module usable for the next call."""
    expected = compiler.compile_source(SIMPLE_KV)
    with pytest.raises(KvCompileError):
        compiler.compile_source("<Broken\n    bad ::: syntax\n")
    assert compiler.compile_source(SIMPLE_KV) == expected


def test_empty_source_is_not_an_error(compiler):
    assert compiler.compile_source("") == ""


def test_non_ascii_survives_the_boundary(compiler):
    """Strings cross as UTF-8 bytes, so multi-byte characters must round trip."""
    output = compiler.compile_source("<Greeting@Label>:\n    text: 'héllo wörld — 日本語'\n")
    assert "héllo wörld — 日本語" in output


def test_repeated_calls_are_stable(compiler):
    """Exercise alloc/free repeatedly to catch leaks or memory reuse bugs."""
    first = compiler.compile_source(CHILDREN_KV)
    for _ in range(50):
        assert compiler.compile_source(CHILDREN_KV) == first


def test_large_input(compiler):
    """A source big enough to force linear memory to grow."""
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
    """Generated variable names must not change between runs.

    They used to come from `UUID()`, which rewrote every file on every run.
    """
    assert compiler.compile_source(CHILDREN_KV) == compiler.compile_source(CHILDREN_KV)


def test_generated_names_are_stable_across_instances():
    """Two fresh modules must agree, not just two calls into one."""
    assert KvCompiler().compile_source(CHILDREN_KV) == KvCompiler().compile_source(CHILDREN_KV)


def test_generated_names_are_numbered_not_random(compiler):
    output = compiler.compile_source(CHILDREN_KV)
    assert "label_1 = Label(" in output
    assert "button_2 = Button(" in output
