# KvToPyClass

Convert Kivy language (KV) files to equivalent Python class definitions.

## Overview

Kivy's Builder dynamically applies KV rules to widgets at runtime. `KvToPyClass` instead generates equivalent Python class code that produces the same widget tree and bindings **without requiring the Builder**.

This approach has several benefits:
- **Better IDE support**: Static Python classes work with autocomplete, type checking
- **Easier debugging**: Generated code is readable Python, not runtime interpretation
- **Performance**: No runtime KV parsing overhead
- **Understanding**: See exactly what KV rules translate to in Python

## Example

**Input KV:**
```kv
<MyButton@Button>:
    text: 'Click me'
    size_hint: (0.5, 0.5)
    on_press: print(self.text)
```

**Generated Python:**
```python
from kivy.uix.widget import Widget
from kivy.factory import Factory
from kivy.properties import *

class MyButton(Button):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.text = 'Click me'
        self.size_hint = (0.5, 0.5)
        self.bind(on_press=self._on_press_handler)
    
    def _on_press_handler(self, instance):
        print(self.text)
```

## Usage

### Command Line

```bash
# Convert a KV file
kvtoclass mywidgets.kv

# Specify output file
kvtoclass mywidgets.kv generated_classes.py
```

### As a Library

```swift
import KvToPyClass
import KvParser

let kvSource = """
<MyWidget@BoxLayout>:
    Label:
        text: 'Hello'
"""

let tokenizer = KvTokenizer(source: kvSource)
let tokens = try tokenizer.tokenize()
let parser = KvParser(tokens: tokens)
let module = try parser.parse()

let generator = KvToPyClassGenerator(module: module)
let pythonCode = try generator.generate()

print(pythonCode)
```

## Features

- ✅ Dynamic class definitions (`<MyClass@BaseClass>`)
- ✅ Property assignments
- ✅ Event handler bindings (`on_press`, etc.)
- ✅ Child widget creation
- ✅ Python AST integration for handler code
- 🚧 Property bindings (reactive updates)
- 🚧 Canvas instructions
- 🚧 Templates
- 🚧 KV directives (`#:import`, `#:include`)

## Architecture

```
┌─────────────┐
│  KV Source  │
└──────┬──────┘
       │
       ▼
┌─────────────┐      ┌──────────────┐
│ KvTokenizer │─────▶│  KvParser    │
└─────────────┘      └──────┬───────┘
                            │
                            ▼
                     ┌──────────────┐
                     │  KvModule    │
                     │  (AST)       │
                     └──────┬───────┘
                            │
                            ▼
                  ┌────────────────────┐
                  │ KvToPyClassGenerator│
                  └─────────┬──────────┘
                            │
                            ▼
                     ┌──────────────┐      ┌──────────────┐
                     │  PySwiftAST  │─────▶│ Python Code  │
                     │  (Python AST)│      │  (.py file)  │
                     └──────────────┘      └──────────────┘
```

## Dependencies

- **SwiftyKvLang**: KV language parser
- **PySwiftAST**: Python AST generation and code formatting

## Comparison to Kivy Builder

### Kivy Builder (Runtime)
```python
from kivy.lang import Builder

Builder.load_string('''
<MyButton@Button>:
    text: 'Click'
''')

# Builder dynamically applies rules when widget is created
btn = Factory.MyButton()
```

### KvToPyClass (Generated)
```python
# Pre-generated Python class
class MyButton(Button):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.text = 'Click'

# Direct instantiation, no Builder needed
btn = MyButton()
```

## Development

```bash
cd KvToPyClass
swift build
swift test
swift run kvtoclass ../kivy/kivy/data/style.kv
```

## License

Same as SwiftyKvLang parent project.
