import Foundation
import KvParser
import KvToPyClass

/// Core conversion routine shared by every entry point of this package.
///
/// Both sides are plain strings: `kvSource` is the contents of a `.kv` file and
/// `pySource` is the contents of the sibling `.py` file when one exists (empty
/// otherwise). Existing Python classes are fed to the generator so hand written
/// methods survive a regeneration.
///
/// Reading and writing files is deliberately left to the host (Python), so this
/// module needs no filesystem access at all.
func convert(kvSource: String, pySource: String) throws -> String {
    let tokenizer = KvTokenizer(source: kvSource)
    let tokens = try tokenizer.tokenize()
    let parser = KvParser(tokens: tokens)
    let module = try parser.parse()

    let pythonClasses = pySource.isEmpty ? [] : PythonClassParser(source: pySource).parse()

    let generator = KvToPyClassGenerator(module: module, pythonClasses: pythonClasses)
    return try generator.generate()
}
