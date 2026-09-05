"""Thin wrapper around the CompileKvWasm WebAssembly module.

The Swift side is a WASI *reactor*: it exposes a handful of functions and never
runs an entry point of its own. All file access lives on the Python side -- the
wasm module only ever receives and returns strings, which is what keeps the
package importable on any platform rather than tied to a native build.
"""

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
    """The process-wide compiler shared by the module level helpers.

    Every importer of compilekv ends up on this one instance, so the wasm module
    is compiled and instantiated once no matter how many modules use the package
    or how often they call it. It is safe to share: conversions are serialized
    on the instance's own lock.
    """
    global _default_compiler
    with _default_lock:
        if _default_compiler is None:
            _default_compiler = KvCompiler()
        return _default_compiler


class KvCompileError(RuntimeError):
    """Raised when the wasm module fails to convert a KV source string."""


def _default_wasm_path() -> Path:
    """Locate the wasm asset shipped inside the wheel."""
    return Path(str(resources.files(__package__).joinpath(WASM_FILENAME)))


@lru_cache(maxsize=None)
def _compile_module(path: str, fingerprint: tuple[int, int]) -> tuple[Engine, Module]:
    """Compile the wasm file once per process.

    Compiling the module to native code takes a couple of seconds, while
    instantiating an already compiled one takes milliseconds. Engines and
    compiled modules are shareable, so the cost is paid once even when several
    KvCompilers are created; each still gets its own Store and linear memory.

    `fingerprint` is the file's (mtime, size), so rebuilding the module during a
    long lived process picks up the new file instead of the cached one.
    """
    del fingerprint  # only present to key the cache
    engine = Engine()
    return engine, Module.from_file(engine, path)


class KvCompiler:
    """Loads the wasm module once and converts KV sources with it.

    Instantiating is the expensive part, so reuse a single compiler when
    converting a whole tree of ``.kv`` files.
    """

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

        # Reactors are initialized explicitly rather than through `_start`.
        exports["_initialize"](self._store)

    def _write(self, data: bytes) -> tuple[int, int]:
        """Copy `data` into wasm linear memory, returning (pointer, length)."""
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
        data = self._memory.read(self._store, pointer, pointer + length)
        return bytes(data).decode("utf-8")

    def compile_source(self, kv_source: str, py_source: str = "") -> str:
        """Convert a KV source string into Python class source.

        `py_source` is the current contents of the matching ``.py`` file, so
        hand written methods on the existing classes are preserved.
        """
        with self._lock:
            kv_ptr, kv_len = self._write(kv_source.encode("utf-8"))
            py_ptr, py_len = self._write(py_source.encode("utf-8"))
            try:
                status = self._convert(self._store, kv_ptr, kv_len, py_ptr, py_len)
                output = self._take_result()
                self._result_free(self._store)
            finally:
                if kv_len:
                    self._dealloc(self._store, kv_ptr, kv_len)
                if py_len:
                    self._dealloc(self._store, py_ptr, py_len)

        if status != 0:
            raise KvCompileError(output or "unknown error")
        return output
