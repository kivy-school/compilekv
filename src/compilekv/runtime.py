"""Wrapper around the CompileKvWasm module. Strings in, strings out."""

from __future__ import annotations

import threading
from functools import lru_cache
from importlib import resources
from pathlib import Path

from wasmtime import Engine, Instance, Linker, Module, Store, WasiConfig

WASM_FILENAME = "compilekv.wasm"

_default_compiler: "KvCompiler | None" = None
_default_lock = threading.Lock()


def default_compiler() -> "KvCompiler":
    """The process-wide compiler shared by every caller."""
    global _default_compiler
    with _default_lock:
        if _default_compiler is None:
            _default_compiler = KvCompiler()
        return _default_compiler


class KvCompileError(RuntimeError):
    """Raised when the wasm module fails to convert a KV source string."""


def _default_wasm_path() -> Path:
    return Path(str(resources.files(__package__).joinpath(WASM_FILENAME)))


@lru_cache(maxsize=None)
def _compile_module(path: str, fingerprint: tuple[int, int]) -> tuple[Engine, Module]:
    """Compile once per process; `fingerprint` is (mtime, size) to catch rebuilds."""
    del fingerprint
    engine = Engine()
    return engine, Module.from_file(engine, path)


class KvCompiler:
    """One wasm instance with its own linear memory."""

    def __init__(self, wasm_path: str | Path | None = None) -> None:
        path = Path(wasm_path) if wasm_path is not None else _default_wasm_path()
        if not path.is_file():
            raise FileNotFoundError(
                f"wasm module not found at {path}. "
                "Build it with `python setup.py build_wasm` or reinstall compilekv."
            )
        self.wasm_path = path
        self._lock = threading.Lock()

        stat = path.stat()
        engine, module = _compile_module(str(path), (stat.st_mtime_ns, stat.st_size))

        self._store = Store(engine)
        self._store.set_wasi(WasiConfig())

        linker = Linker(engine)
        linker.define_wasi()
        self._instance: Instance = linker.instantiate(self._store, module)

        exports = self._instance.exports(self._store)
        self._memory = exports["memory"]
        self._alloc = exports["kv_alloc"]
        self._dealloc = exports["kv_dealloc"]
        self._convert = exports["kv_convert"]
        self._result_ptr = exports["kv_result_ptr"]
        self._result_len = exports["kv_result_len"]
        self._result_free = exports["kv_result_free"]

        # A reactor is initialized explicitly, not through `_start`.
        exports["_initialize"](self._store)

    def _write(self, data: bytes) -> tuple[int, int]:
        if not data:
            return 0, 0
        pointer = self._alloc(self._store, len(data))
        self._memory.write(self._store, data, pointer)
        return pointer, len(data)

    def _take_result(self) -> str:
        pointer = self._result_ptr(self._store)
        length = self._result_len(self._store)
        if not length:
            return ""
        return bytes(self._memory.read(self._store, pointer, pointer + length)).decode("utf-8")

    def compile_source(
        self, kv_source: str, py_source: str = "", directives: str = ""
    ) -> str:
        """Convert KV source to Python.

        `py_source` is the existing .py, if any. `directives` holds `#:set`
        and `#:import` lines from other KV files, which KV shares across a
        project.
        """
        with self._lock:
            kv_ptr, kv_len = self._write(kv_source.encode("utf-8"))
            py_ptr, py_len = self._write(py_source.encode("utf-8"))
            const_ptr, const_len = self._write(directives.encode("utf-8"))
            try:
                status = self._convert(
                    self._store, kv_ptr, kv_len, py_ptr, py_len, const_ptr, const_len
                )
                output = self._take_result()
                self._result_free(self._store)
            finally:
                for pointer, length in (
                    (kv_ptr, kv_len),
                    (py_ptr, py_len),
                    (const_ptr, const_len),
                ):
                    if length:
                        self._dealloc(self._store, pointer, length)

        if status != 0:
            raise KvCompileError(output or "unknown error")
        return output
