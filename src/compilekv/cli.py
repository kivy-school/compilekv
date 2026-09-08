"""Argument parsing for `python -m compilekv`. The library is in compiler.py."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .compiler import Project, compile_file, find_kv_files
from .runtime import KvCompileError, default_compiler


def run(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="compilekv",
        description="Compile Kivy KV files into Python classes using the CompileKvWasm module.",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        default=["."],
        help="KV files or directories to compile (defaults to the current directory).",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="Output directory, or a file name when compiling a single KV file. "
        "Defaults to writing next to each .kv.",
    )
    parser.add_argument(
        "--no-recursive",
        action="store_true",
        help="Do not descend into subdirectories.",
    )
    parser.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="Only report errors.",
    )
    args = parser.parse_args(argv)

    roots = [Path(path) for path in args.paths]
    for root in roots:
        if not root.exists():
            print(f"error: {root} does not exist", file=sys.stderr)
            return 1

    # Everything is read before anything is written, so a `#:set` in the last
    # file scanned is still available to the first file generated.
    project = Project.scan(roots, recursive=not args.no_recursive)
    if not project.kv_files:
        print("No .kv files found.", file=sys.stderr)
        return 1

    compiler = default_compiler()
    failures = 0
    for root in roots:
        for kv_path in find_kv_files(root, recursive=not args.no_recursive):
            try:
                written = compile_file(
                    kv_path,
                    _target_for(kv_path, root, args.output),
                    compiler,
                    project.directives,
                )
            except KvCompileError as error:
                print(f"error: {kv_path}: {error}", file=sys.stderr)
                failures += 1
                continue
            if not args.quiet:
                print(f"{kv_path} -> {written}")

    return 1 if failures else 0


def _target_for(kv_path: Path, root: Path, output: str | None) -> Path | None:
    """A directory input means a directory output, mirroring the tree under it."""
    if output is None:
        return None
    if root.is_file():
        return Path(output)
    return Path(output) / kv_path.parent.relative_to(root)
