"""Compile Kivy KV files into Python classes.

This is a library, meant to be imported by other Python code::

    import compilekv
    compilekv.compile_file("ui/style.kv")

The conversion is a Swift package compiled to WebAssembly rather than a native
binary, so the wheel is architecture independent and importable on any platform
Python runs on. The wasm module is compiled and instantiated once per process
and shared by every caller -- see `default_compiler`.

``python -m compilekv`` exists as a convenience wrapper; it is not the interface.
"""

from .compiler import compile_file, compile_tree, find_kv_files, output_path_for
from .runtime import KvCompileError, KvCompiler, default_compiler

__all__ = [
    "KvCompileError",
    "KvCompiler",
    "compile_file",
    "compile_tree",
    "default_compiler",
    "find_kv_files",
    "output_path_for",
]
