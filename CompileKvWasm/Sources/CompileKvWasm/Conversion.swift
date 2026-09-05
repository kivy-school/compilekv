import Foundation
import KvParser
import KvToPyClass

/// Convert KV source to Python. `pySource` is the existing .py, or empty.
func convert(kvSource: String, pySource: String) throws -> String {
    let tokenizer = KvTokenizer(source: kvSource)
    let tokens = try tokenizer.tokenize()
    let parser = KvParser(tokens: tokens)
    let module = try parser.parse()

    let existing = pySource.isEmpty
        ? PythonModuleInfo(body: [], classes: [])
        : PythonClassParser(source: pySource).parseModule()

    return try KvToPyClassGenerator(module: module, existing: existing).generate()
}
