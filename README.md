# compilekv

**An importable Python module.** `import compilekv` and call it from your own
code — a build step, an editor plugin, a test fixture, whatever. It compiles
Kivy `.kv` files into plain Python classes, so widgets can be built without
`Builder`.

## Why WebAssembly

The conversion is [KvToPyClass](../KvToPyClass), a Swift package. Shipping that
as a native binary would mean a wheel per platform, built on a machine with a
Swift toolchain, and no wheel at all for anything you did not build for — which
is fine for a command line tool you install yourself, and useless for a module
other people import.

Compiled to wasm instead, the conversion is just data: one
`compilekv-0.1.0-py3-none-any.whl` that installs and imports anywhere Python
runs. Python owns the filesystem — it walks the tree, reads the `.kv` and any
existing `.py`, and writes the result. The wasm module only ever sees and
returns strings, so nothing in it is platform specific.

The one native piece is the `wasmtime` runtime, which publishes wheels for
macOS (x86_64, arm64), Linux (x86_64, aarch64; glibc and musl), Windows
(amd64, arm64) and Android.

## Usage

compilekv is a library. Import it and call the helpers:

```python
from compilekv import compile_file, compile_tree, find_kv_files

compile_tree("ui/")            # every .kv under a directory
compile_file("ui/style.kv")    # one file
```

Each `style.kv` compiles to `style.py` beside it. When that `.py` already
exists its contents are handed to the generator, so hand written methods carry
over. Output is deterministic and regenerating is idempotent -- compiling twice
leaves the files byte for byte identical, which keeps generated code reviewable
in version control.

For direct control over the strings, skipping the file layer entirely:

```python
from compilekv import default_compiler

python_source = default_compiler().compile_source(kv_source, existing_py_source)
```

`compile_source` raises `KvCompileError` with the parser's message when the KV
is invalid.

### One wasm module per process

Compiling the wasm module takes a few seconds against ~3 ms per conversion, so
it happens once. `default_compiler()` returns a process-wide instance shared by
every caller, so any number of modules can import compilekv and convert as often
as they like without reloading:

```python
# module_a.py                      # module_b.py
from compilekv import compile_file  import compilekv
compile_file("a.kv")                compilekv.compile_file("b.kv")
# ^ pays the load                   # ^ ~1 ms, same instance
```

Conversions are serialized on the instance's own lock, so sharing it across
threads is safe. `KvCompiler()` still builds an isolated instance with its own
linear memory when you want one; the compiled module is cached either way.

### Command line

Secondary, for one-off runs. No console script is installed.

```console
$ python -m compilekv [paths...] [-o OUT] [--no-recursive] [-q]
```

## Tests

```console
$ COMPILEKV_SKIP_WASM_BUILD=1 uv run --group dev pytest
```

Drop the environment variable to rebuild the wasm module first. The suite covers
the wasm ABI, the file walking layer, and the CLI, and finishes with a round trip
that prints both inputs and the generated output.

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
