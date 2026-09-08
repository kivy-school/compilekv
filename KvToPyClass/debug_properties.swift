import Foundation
import KvParser

let kvSource = """
<MyButton@Button>:
    text: 'Hello World'
    size_hint: 0.5, 0.5
"""

let tokenizer = KvTokenizer(source: kvSource)
let tokens = try tokenizer.tokenize()
let parser = KvParser(tokens: tokens)
let module = try parser.parse()

for rule in module.rules {
    print("Rule: \(rule.selector)")
    for prop in rule.properties {
        print("  Property: \(prop.name)")
        print("    value: '\(prop.value)'")
        print("    compiledValue: \(prop.compiledValue)")
    }
}
