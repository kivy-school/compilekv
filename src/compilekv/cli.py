"""Argument parsing for `python -m compilekv`. The library is in compiler.py."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .compiler import compile_file, find_kv_files
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
        help="Output file, only valid when compiling a single KV file.",
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

    kv_files: list[Path] = []
    for path in args.paths:
        target = Path(path)
        if not target.exists():
            print(f"error: {target} does not exist", file=sys.stderr)
            return 1
        kv_files.extend(find_kv_files(target, recursive=not args.no_recursive))

    if not kv_files:
        print("No .kv files found.", file=sys.stderr)
        return 1

    if args.output and len(kv_files) != 1:
        print("error: --output requires exactly one KV file", file=sys.stderr)
        return 1

    compiler = default_compiler()
    failures = 0
    for kv_path in kv_files:
        try:
            written = compile_file(kv_path, args.output, compiler=compiler)
        except KvCompileError as error:
            print(f"error: {kv_path}: {error}", file=sys.stderr)
            failures += 1
            continue
        if not args.quiet:
            print(f"{kv_path} -> {written}")

    return 1 if failures else 0
