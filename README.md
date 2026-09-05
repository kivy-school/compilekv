# compilekv

Compile Kivy `.kv` files into plain Python classes, so widgets can be built
without `Builder`.

The conversion itself is [KvToPyClass](../KvToPyClass), a Swift package, compiled
to a WebAssembly module. Python drives it: it walks the tree, reads the files,
and writes the results. The wasm module only ever sees strings, which keeps the
wheel architecture independent — one `py3-none-any` wheel runs everywhere.

## Usage

```console
$ compilekv                     # compile every .kv under the current directory
$ compilekv ui/ widgets/        # specific directories
$ compilekv style.kv -o out.py  # a single file
$ compilekv . --no-recursive
```

Each `style.kv` compiles to `style.py` beside it. When that `.py` already
exists its contents are handed to the generator so existing classes carry over.

As a library:

```python
from compilekv import KvCompiler, compile_file, compile_tree

compile_tree("ui/")                     # walk a directory
compile_file("ui/style.kv")             # one file

compiler = KvCompiler()                 # reuse for many conversions
python_source = compiler.compile_source(kv_source, existing_py_source)
```

Loading the wasm module is the expensive part, so reuse one `KvCompiler` when
converting more than a single file. `compile_source` raises `KvCompileError`
with the parser's message when the KV is invalid.

## Building from source

The wheel bundles a prebuilt `compilekv.wasm`. Rebuilding it needs a Swift
toolchain plus a matching [Swift SDK for WebAssembly](https://www.swift.org/documentation/articles/wasm-getting-started.html),
and a checkout of `KvToPyClass` as a sibling of this directory (the Swift
package refers to it by relative path for now).

```console
$ python scripts/build_wasm.py    # just the wasm module
$ python -m build --wheel         # wasm + wheel
```

The build picks a wasm SDK matching the active toolchain, falling back to
`swiftly run +<version>` when the default toolchain is a different version.
Override with `COMPILEKV_SWIFT`, `COMPILEKV_WASM_SDK`, or set
`COMPILEKV_SKIP_WASM_BUILD=1` to reuse the module already in `src/compilekv/`.

The module is ~46 MB because Swift's Foundation is statically linked (about
36 MB of that is Foundation's data tables); the wheel compresses to ~18 MB.

## Wasm ABI

The Swift package builds as a WASI reactor exporting:

| Export | Purpose |
| --- | --- |
| `kv_alloc(size) -> ptr` | allocate an input buffer in linear memory |
| `kv_dealloc(ptr, size)` | release one |
| `kv_convert(kv_ptr, kv_len, py_ptr, py_len) -> status` | convert; 0 on success, 1 on error |
| `kv_result_ptr()` / `kv_result_len()` | the generated source, or the error message |
| `kv_result_free()` | release the result buffer |
