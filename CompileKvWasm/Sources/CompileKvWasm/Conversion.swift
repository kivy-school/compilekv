import Foundation
import KvParser
import KvToPyClass

/// Convert KV source to Python. `pySource` is the existing .py, or empty.
/// `constantsSource` holds `#:set` directives gathered from other KV files.
func convert(kvSource: String, pySource: String, constantsSource: String = "") throws -> String {
    let module = try parse(kvSource)

    let existing = pySource.isEmpty
        ? PythonModuleInfo(body: [], classes: [])
        : PythonClassParser(source: pySource).parseModule()

    // Directives the file declares itself win over the shared ones.
    let shared = constantsSource.isEmpty ? [] : (try? parse(constantsSource))?.directives ?? []

    return try KvToPyClassGenerator(
        module: module,
        existing: existing,
        sharedDirectives: shared
    ).generate()
}

private func parse(_ source: String) throws -> KvModule {
    let tokens = try KvTokenizer(source: source).tokenize()
    return try KvParser(tokens: tokens).parse()
}
