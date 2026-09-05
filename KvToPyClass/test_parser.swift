import Foundation
import KvParser

let kvSource = """
<MyDrawingWidget@Widget>:
    canvas:
        Color:
            rgba: 1, 1, 1, 1
        Rectangle:
            pos: self.pos
            size: self.size
"""

do {
    let module = try KvParser.parse(kvSource)
    print("Parsed module:")
    print("Rules: \(module.rules.count)")
    
    for (index, rule) in module.rules.enumerated() {
        print("\nRule \(index + 1): \(rule.selector.primaryName)")
        print("  Properties: \(rule.properties.count)")
        print("  Children: \(rule.children.count)")
        print("  Canvas before: \(rule.canvasBefore != nil ? "\(rule.canvasBefore!.instructions.count) instructions" : "nil")")
        print("  Canvas: \(rule.canvas != nil ? "\(rule.canvas!.instructions.count) instructions" : "nil")")
        print("  Canvas after: \(rule.canvasAfter != nil ? "\(rule.canvasAfter!.instructions.count) instructions" : "nil")")
        
        if let canvas = rule.canvas {
            print("  Canvas instructions:")
            for (i, instr) in canvas.instructions.enumerated() {
                print("    \(i + 1). \(instr.instructionType) (\(instr.properties.count) properties)")
            }
        }
    }
} catch {
    print("Error: \(error)")
}
