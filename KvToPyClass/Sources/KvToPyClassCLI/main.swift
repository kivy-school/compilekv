import Foundation
import KvParser
import KvToPyClass

@main
struct KvToPyClassCLI {
    static func main() async throws {
        let args = CommandLine.arguments
        
        guard args.count >= 2 else {
            print("""
            KvToPyClass - Convert KV language to Python classes
            
            Usage: kvtoclass <input.kv> [output.py]
            
            Converts Kivy language (KV) rules and templates into equivalent
            Python class definitions that can be used without Builder.
            
            Examples:
                kvtoclass style.kv
                kvtoclass widgets.kv output.py
            """)
            return
        }
        
        let inputPath = args[1]
        let outputPath = args.count >= 3 ? args[2] : inputPath.replacingOccurrences(of: ".kv", with: ".py")
        
        print("Converting \(inputPath) to Python classes...")
        
        do {
            // Read KV file
            let kvSource = try String(contentsOfFile: inputPath, encoding: .utf8)
            
            // Parse KV
            let tokenizer = KvTokenizer(source: kvSource)
            let tokens = try tokenizer.tokenize()
            let parser = KvParser(tokens: tokens)
            let module = try parser.parse()
            
            print("Parsed KV file:")
            print("  - \(module.directives.count) directives")
            print("  - \(module.rules.count) rules")
            print("  - \(module.templates.count) templates")
            print("  - \(module.root != nil ? "1" : "0") root widget")
            
            // Generate Python code
            let generator = KvToPyClassGenerator(module: module)
            let pythonCode = try generator.generate()
            
            // Write output
            try pythonCode.write(toFile: outputPath, atomically: true, encoding: .utf8)
            
            print("✓ Generated Python classes in \(outputPath)")
            print("\nGenerated \(pythonCode.split(separator: "\n").count) lines of Python code")
            
        } catch let error as KvParserError {
            print("Error parsing KV file: \(error)")
            Foundation.exit(1)
        } catch {
            print("Error: \(error)")
            Foundation.exit(1)
        }
    }
}
