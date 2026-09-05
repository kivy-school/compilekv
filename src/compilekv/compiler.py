"""File level helpers: find ``.kv`` files, feed them through wasm, write ``.py``."""

from __future__ import annotations

from pathlib import Path

from .runtime import KvCompiler, default_compiler


def output_path_for(kv_path: Path) -> Path:
    """The ``.py`` file a given ``.kv`` file compiles to."""
    return kv_path.with_suffix(".py")


def compile_file(
    kv_path: str | Path,
    output_path: str | Path | None = None,
    compiler: KvCompiler | None = None,
) -> Path:
    """Compile a single ``.kv`` file and write the generated Python next to it.

    When the target ``.py`` already exists its contents are handed to the
    generator so existing classes and their methods are carried over.
    """
    kv_path = Path(kv_path)
    target = Path(output_path) if output_path is not None else output_path_for(kv_path)
    compiler = compiler or default_compiler()

    kv_source = kv_path.read_text(encoding="utf-8")
    py_source = target.read_text(encoding="utf-8") if target.is_file() else ""

    generated = compiler.compile_source(kv_source, py_source)
    target.write_text(generated, encoding="utf-8")
    return target


def find_kv_files(root: str | Path, recursive: bool = True) -> list[Path]:
    """List the ``.kv`` files under `root`, or `root` itself if it is one."""
    root = Path(root)
    if root.is_file():
        return [root]
    pattern = "**/*.kv" if recursive else "*.kv"
    return sorted(p for p in root.glob(pattern) if p.is_file())


def compile_tree(
    root: str | Path,
    recursive: bool = True,
    compiler: KvCompiler | None = None,
) -> list[Path]:
    """Compile every ``.kv`` file under `root`, returning the files written."""
    compiler = compiler or default_compiler()
    return [
        compile_file(kv_path, compiler=compiler)
        for kv_path in find_kv_files(root, recursive=recursive)
    ]
