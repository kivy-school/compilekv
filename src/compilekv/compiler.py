"""Find .kv files, run them through wasm, write the .py."""

from __future__ import annotations

import re
from collections.abc import Iterable
from pathlib import Path

from .runtime import KvCompiler, default_compiler


def output_path_for(kv_path: str | Path, output: str | Path | None = None) -> Path:
    """Where `kv_path` is written. `output` may be a directory or a file name."""
    kv_path = Path(kv_path)
    if output is None:
        return kv_path.with_suffix(".py")
    output = Path(output)
    if output.is_dir() or not output.suffix:
        return output / kv_path.with_suffix(".py").name
    return output


def source_path_for(kv_path: str | Path) -> Path:
    """The hand written .py beside the .kv, whose contents get extended."""
    return Path(kv_path).with_suffix(".py")


SET_DIRECTIVE = re.compile(r"^#:set\s+\S+\s+\S.*$")


def collect_constants(paths: Iterable[str | Path]) -> str:
    """The `#:set` lines from every given .kv file.

    KV shares these across a project -- a theme file defines them and every
    other file uses them -- so compiling one file needs the others' directives.
    """
    lines = []
    for path in paths:
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            if SET_DIRECTIVE.match(line.strip()):
                lines.append(line.strip())
    return "\n".join(lines)


def compile_file(
    kv_path: str | Path,
    output: str | Path | None = None,
    compiler: KvCompiler | None = None,
    constants: str = "",
) -> Path:
    """Compile one .kv, extending the .py next to it. Returns the file written."""
    kv_path = Path(kv_path)
    target = output_path_for(kv_path, output)
    compiler = compiler or default_compiler()

    source = source_path_for(kv_path)
    py_source = source.read_text(encoding="utf-8") if source.is_file() else ""

    generated = compiler.compile_source(
        kv_path.read_text(encoding="utf-8"), py_source, constants
    )

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(generated, encoding="utf-8")
    return target


def find_kv_files(root: str | Path, recursive: bool = True) -> list[Path]:
    """The .kv files under `root`, or `root` itself if it is one."""
    root = Path(root)
    if root.is_file():
        return [root]
    pattern = "**/*.kv" if recursive else "*.kv"
    return sorted(p for p in root.glob(pattern) if p.is_file())


def compile_tree(
    root: str | Path,
    output_dir: str | Path | None = None,
    recursive: bool = True,
    compiler: KvCompiler | None = None,
) -> list[Path]:
    """Compile every .kv under `root` into `output_dir`. Returns what was written."""
    root = Path(root)
    compiler = compiler or default_compiler()

    # A `#:set` in any file in the tree is visible to all of them.
    kv_files = find_kv_files(root, recursive=recursive)
    constants = collect_constants(kv_files)

    written = []
    for kv_path in kv_files:
        target = None
        if output_dir is not None:
            # Mirror the tree under root so same-named .kv files cannot collide.
            relative = kv_path.parent.relative_to(root) if root.is_dir() else Path()
            target = Path(output_dir) / relative
        written.append(compile_file(kv_path, target, compiler, constants))
    return written
