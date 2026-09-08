"""Find .kv files, run them through wasm, write the .py."""

from __future__ import annotations

import re
from collections.abc import Iterable
from dataclasses import dataclass
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


# `#: set` with a space is as valid as `#:set`.
SHARED_DIRECTIVE = re.compile(r"^#:\s*(set|import)\s+\S+\s+\S.*$")


def collect_directives(paths: Iterable[str | Path]) -> str:
    """The `#:set` and `#:import` lines from every given file.

    KV puts both in one namespace shared by everything Builder loads -- a
    theme file defines the constants, one widget file imports a helper another
    one uses -- so compiling any file needs the directives from all of them.

    Python files are worth reading for the same reason: KV passed to
    `Builder.load_string()` carries directives that the .kv files rely on.
    """
    lines: list[str] = []
    for path in paths:
        try:
            source = Path(path).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for line in source.splitlines():
            stripped = line.strip()
            if SHARED_DIRECTIVE.match(stripped) and stripped not in lines:
                lines.append(stripped)
    return "\n".join(lines)


@dataclass(frozen=True)
class Project:
    """The .kv files to compile, and everything they share.

    Gathered in full before anything is generated, so a file can use a
    `#:set` from a file that comes later in the walk -- a theme file is
    usually last alphabetically and always needed first.
    """

    kv_files: tuple[Path, ...]
    directives: str

    @classmethod
    def scan(cls, roots: str | Path | Iterable[str | Path], recursive: bool = True) -> "Project":
        if isinstance(roots, (str, Path)):
            roots = [roots]
        roots = [Path(root) for root in roots]

        kv_files: list[Path] = []
        for root in roots:
            for path in find_kv_files(root, recursive=recursive):
                if path not in kv_files:
                    kv_files.append(path)

        # Python files can hold KV too, inside Builder.load_string(), and the
        # directives in it are shared with every .kv file.
        sources = list(kv_files)
        pattern = "**/*.py" if recursive else "*.py"
        for root in roots:
            directory = root if root.is_dir() else root.parent
            sources.extend(sorted(p for p in directory.glob(pattern) if p.is_file()))

        return cls(tuple(kv_files), collect_directives(sources))


def compile_file(
    kv_path: str | Path,
    output: str | Path | None = None,
    compiler: KvCompiler | None = None,
    directives: str = "",
) -> Path:
    """Compile one .kv, extending the .py next to it. Returns the file written."""
    kv_path = Path(kv_path)
    target = output_path_for(kv_path, output)
    compiler = compiler or default_compiler()

    source = source_path_for(kv_path)
    py_source = source.read_text(encoding="utf-8") if source.is_file() else ""

    generated = compiler.compile_source(
        kv_path.read_text(encoding="utf-8"), py_source, directives
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

    # Scan the whole tree before writing anything.
    project = Project.scan(root, recursive=recursive)

    written = []
    for kv_path in project.kv_files:
        target = None
        if output_dir is not None:
            # Mirror the tree under root so same-named .kv files cannot collide.
            relative = kv_path.parent.relative_to(root) if root.is_dir() else Path()
            target = Path(output_dir) / relative
        written.append(compile_file(kv_path, target, compiler, project.directives))
    return written
