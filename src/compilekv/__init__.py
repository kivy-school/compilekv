"""Compile Kivy KV files into Python classes via a Swift WebAssembly module.

Import this package and call the helpers; the wasm module is compiled and
instantiated once per process and shared by every caller. A thin command line
wrapper is available as ``python -m compilekv``.
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
