# compilekv

**An importable Python module.** `import compilekv` and call it from your own
code — a build step, an editor plugin, a test fixture, whatever. It compiles
Kivy `.kv` files into plain Python classes, so widgets can be built without
`Builder`.

## Why WebAssembly

The conversion is [KvToPyClass](KvToPyClass/), a Swift package. Shipping that
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

compile_tree("ui/")                    # every .kv under a directory, in place
compile_tree("ui/", "build/")          # ... or into a separate tree
compile_file("ui/style.kv")            # one file
compile_file("ui/style.kv", "build/")  # ... written to build/style.py
```

Each `style.kv` compiles to `style.py`. Give an output directory and the tree
under the input is mirrored into it, so `ui/panels/style.kv` becomes
`build/panels/style.py` and same-named files in different directories cannot
collide. Pass a path with a suffix instead and it is used verbatim as the file
name.

### Extending, not replacing

The `.py` **next to the `.kv`** is the source. It is read whether or not you
compile into a separate output directory, and the result is that file with the
generated code folded in: imports the rules need are added to the ones already
there, a class the KV defines is merged with the same-named class in place, and
rules with no matching class are appended. Everything else -- module docstring,
constants, helper functions, unrelated classes -- stays where you put it.

Inside a class the author's body is the starting point, so properties,
annotations, the class docstring, nested classes and hand written methods all
survive. A generated method replaces the one it shares a name with, with one
exception: `__init__` is **appended to**, not replaced. Your setup runs first,
then the widget tree:

```python
def __init__(self, **kwargs):
    super().__init__(**kwargs)
    self.counter = 0          # yours
    self._bindings = []       # generated from here down
    self.orientation = "vertical"
    ...
```

Your signature and your `super()` call are the ones kept. Everything from
`self._bindings = []` onwards is treated as output from a previous run and
replaced, which is what keeps regenerating from stacking copies of the tree.

A `<Name>:` rule styles a class that already exists, so its bases come from
your Python; `<Name@Base>:` declares them inline. With neither, it falls back
to `Widget`.

Output is deterministic and regenerating is idempotent -- compiling twice
leaves the files byte for byte identical, which keeps generated code reviewable
in version control.

One consequence of extending rather than replacing: compiling **in place**,
where the source and the output are the same file, cannot tell a class it
emitted last run from one you wrote, so deleting a rule leaves its class
behind. Compile into an output directory for a file that only ever reflects
the current `.kv`.

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

`-o` is a directory when the input is one, mirroring its layout, and may be a
file name when compiling a single `.kv`.

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
`KvToPyClass/` is vendored in this repo and referenced by relative path, so no
extra checkout is needed.

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

### `root`, `self`, and bindings

`root` in KV is the widget the rule applies to, so it becomes `self`:

```kv
<Card>:
    Label:
        text: root.title
```

```python
label_1.text = self.title
self.bind(title=label_1.setter("text"))
```

`self` is the widget whose block the value was written in, so under a child
it is that child, not the rule:

```kv
<Card>:
    Label:
        height: self.texture_size[1]
```

```python
label_1.height = label_1.texture_size[1]
label_1.bind(texture_size=_callback_0)
```

The `bind` call is only emitted when the attribute is a Kivy property of
whichever object it is read from. That is answered by the widget registry for
anything Kivy ships, by the rule for a widget another rule defines, and by the
class itself for one in your `.py` -- `title = StringProperty("")` binds,
`title = "x"` does not, because `bind()` on a non-property raises. A widget
from outside the module cannot be checked, so it is assumed bindable. In a
mixed expression the bindable names are bound and the rest are read once.

### Directives

KV's `#:set` directives are substituted into the generated code, since there is
no Builder at runtime to resolve them:

```kv
#:set plex_16 sp(16)

<Item>:
    font_size: plex_16
```

```python
from kivy.metrics import sp
...
self.font_size = sp(16)
```

The file that declares a `#:set` also publishes it, so `.kv` files loaded at
runtime still resolve the name -- Builder only knows the directives from files
it has already parsed:

```python
from kivy.lang.parser import global_idmap

global_idmap["plex_16"] = sp(16)
```

Only the declaring file does this; one that merely uses the constant gets the
substituted value and nothing else.

`#:import` becomes a real import, but only for the names the generated code
actually reads:

```kv
#:import get_font_name carbonkivy.utils.get_font_name
```

```python
from carbonkivy.utils import get_font_name
```

`#:from` is the same thing spelled the Python way, alias included:

```kv
#:from kivy.metrics import sp as scaled
```

```python
from kivy.metrics import sp as scaled
```

`#:mode default|carbonkivy|nucleant|swiftui` tags a file with a generator
dialect. It is read (`KvToPyClassGenerator.mode`) but nothing branches on it
yet; it is per file and not shared between files.

KV puts `#:set`, `#:import` and `#:from` in one namespace shared by everything Builder loads, so the
whole project is read before anything is written. `Project.scan(roots)` walks
every `.kv` -- and every `.py`, since KV passed to `Builder.load_string()`
carries directives the `.kv` files rely on -- and `compile_tree` and
`python -m compilekv` both go through it. Nothing depends on which file is
walked first. A `#:set` in the file itself wins over a shared one.
`collect_directives(paths)` exposes the gathering, and
`compile_file(..., directives=...)` takes the result.

### Declared property types

A bare unquoted word normally becomes a string, but not when the property it is
assigned to cannot hold one. `font_size: SOME_GLOBAL` on a `NumericProperty`
emits the name, not `"SOME_GLOBAL"`. The type comes from the widget registry or
from the property your class declares, so `my_size = NumericProperty()` in your
`.py` is taken into account.

### Canvas

A canvas layer becomes a `with` block, the way it is written by hand:

```kv
<Card>:
    canvas.before:
        Color:
            rgba: (1, 0, 0, 1)
        Rectangle:
            pos: self.pos
            size: self.size
```

```python
with self.canvas.before:
    Color(rgba=(1, 0, 0, 1))
    self.rectangle_1 = Rectangle(pos=self.pos, size=self.size)
self.bind(pos=_callback_1, size=_callback_2)
```

An instruction whose properties track something is named so the bindings have
an object to update; the rest stay anonymous. Child widgets get their own
canvas blocks, where `self` is that child.

### Conditional blocks

`if`/`else` and `try`/`expect` blocks are an extension to KV: a branch holds
anything a rule body can, and applies only while its condition holds.

```kv
<MyWidget@BoxLayout>:
    if self.disabled:
        Label:
            text: "no press"
    else:
        Button:
            text: "press me"
    try:
        Button:
            text: "success"
    expect:
        Label:
            text: "failed"
```

Each block becomes a method that builds the branch that applies, and a reset
that takes the previous one down again. `__init__` evaluates it once and binds
it to whatever the condition watches, so it re-runs when that changes:

```python
def __init__(self, **kwargs):
    ...
    self._conditional_0(self)
    _callback_0 = lambda *args: self._conditional_0(self)
    self.bind(disabled=_callback_0)

def _conditional_0(self, parent, *args):
    self._conditional_0_reset()
    if self.disabled:
        label_1 = Label(text="no press")
        parent.add_widget(label_1)
        self._conditional_0_widgets.append(label_1)
    else:
        ...

def _conditional_0_reset(self):
    # remove the widgets, unbind the callbacks and drop the canvas
    # groups the previous evaluation added
```

`parent` is the widget the block sits in, so a block inside a child widget's
body adds to that child and watches that child's `self`. A `try` branch that
raises while building is cleared before the `expect` branch goes in. A name
the condition watches on the rule root that is not a Kivy property --
`if self.compact:` -- is declared as an `ObjectProperty`, since a plain
attribute cannot be bound. Branch canvas instructions go into an
`InstructionGroup` so they can be removed as one.

Properties set in a branch (`opacity: 0.5` under `if self.disabled:`) are
applied when the branch is taken and left as they are when it is not; KV has
no notion of un-setting a property.

### Code blocks

`name: |` opens a block, the way a multi-line command does in a GitHub Actions
workflow: the indented lines below are Python statements, not an expression.
A handler block becomes a function body; a value block becomes a function
whose return value is the property, re-run whenever a watched key changes.

```kv
<StatusLabel@Label>:
    error: False
    text: |
        if self.error:
            return "failed"
        return "ok"
    on_error: |
        if self.error:
            self.font_size = 18
        else:
            self.font_size = 14
```

```python
def __init__(self, **kwargs):
    ...
    def _value_1():
        if self.error:
            return "failed"
        return "ok"

    self.text = _value_1()
    _callback_0 = lambda *args: setattr(self, "text", _value_1())
    self.bind(error=_callback_0)
    self.bind(on_error=self._on_error_handler)

def _on_error_handler(self, instance):
    if self.error:
        self.font_size = 18
    else:
        self.font_size = 14
```

A handler block on a child widget becomes a nested function in `__init__`,
bound on that child. Inside any block `root`, `self`, ids, `app` and `#:set`
names resolve as they do in an expression. A block that is not valid Python
is an error, not a `pass`.

A name a rule assigns and then watches -- `error: False` above, or
`if self.compact:` -- is declared as an `ObjectProperty`, which is what
Builder's `create_property` would have made of it; a plain attribute cannot
be bound. Names a rule only reads are left to the hand written class.

### Factory registration

Every generated class is registered, so other KV files and `Builder` can
resolve it by name:

```python
Factory.register("MyButton", cls=MyButton)
```

Existing registrations in your `.py` are left alone rather than duplicated.

A widget the KV references that Kivy does not ship and this module does not
define is assumed to be a custom widget registered elsewhere, so it is taken
off the Factory instead of guessed at with a `kivy.uix` import:

```python
MyWidget = Factory.MyWidget
```

This is a plain constant, not `type MyWidget = Factory.MyWidget`. The PEP 695
form resolves lazily, which would be nicer, but a `TypeAliasType` is not
callable and the generated code has to construct the widget. The constant is
read at import time, so the widget must be registered by then.
