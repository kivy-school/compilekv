
# phase 1

configure new package that utilizes KvToPyClass just stick to ref to it relative for now..
just call package inside CompileKvWasm.




# phase 2
write python code that uses the  wasm module
either by

```py
import os
from wasmtime import Engine, Store, Module, Instance

# 1. Get the path to the WASM file on your Desktop
desktop_path = os.path.expanduser("~/Desktop")
wasm_file_path = os.path.join(desktop_path, "your_file.wasm") # Change to your actual file name

# 2. Initialize the Wasmtime engine and store
engine = Engine()
store = Store(engine)

# 3. Load and compile the WASM binary
print(f"Loading {wasm_file_path}...")
module = Module.from_file(engine, wasm_file_path)

# 4. Instantiate the module
instance = Instance(store, module, [])

# 5. Access and call exported functions
# (Replace 'sum' with the actual function exported inside your WASM file)
exports = instance.exports(store)
if "sum" in exports:
    sum_function = exports["sum"]
    result = sum_function(store, 5, 10)
    print(f"Result from WASM: {result}")
else:
    print("Available exports:", list(exports.keys()))
```

or 

```py
import os
from wasmer import engine, wat, Store, Module, Instance
from wasmer_compiler_cranelift import Compiler

# Load the file
desktop_path = os.path.expanduser("~/Desktop")
wasm_bytes = open(os.path.join(desktop_path, "your_file.wasm"), "rb").read()

# Compile and run
store = Store(engine.JIT(Compiler))
module = Module(store, wasm_bytes)
instance = Instance(module)

# Call an exported function
result = instance.exports.sum(5, 10)
print(result)
```
dont know which lib / way is fhe best ?

i assume we just need to make a final package that uses KvToPyClass
same way as KvToPyClass/Sources/KvToPyClassCLI does, but exposed wasm functions by the @export(wasm) or how it is now with swift wasm
so python side just iterate over all .kv files and if it finds matching .py name it will include that in the call (both passed as strings ) and function just returns the generated string which it writes.. soo python handles read and write, and swift-wasm just process and outputs string.


# phase 3

create setup.py

that builds the wasm module and include it as asset in the python wheel.
if helper scripts is needed just make them.

and then our wheel should now just be consider an any platform wheel.

