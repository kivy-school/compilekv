"""Compile Kivy KV files into Python classes.

A library, meant to be imported:

    import compilekv
    compilekv.compile_file("ui/style.kv")

The conversion is a Swift package compiled to WebAssembly, so the wheel is
platform independent. `python -m compilekv` exists but is not the interface.
"""

from .compiler import (
    Project,
    collect_directives,
    compile_file,
    compile_tree,
    find_kv_files,
    output_path_for,
    source_path_for,
)
from .runtime import KvCompileError, KvCompiler, default_compiler

__all__ = [
    "Project",
    "KvCompileError",
    "KvCompiler",
    "collect_directives",
    "compile_file",
    "compile_tree",
    "default_compiler",
    "find_kv_files",
    "output_path_for",
    "source_path_for",
]
