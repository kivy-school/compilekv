import Foundation
import PySwiftAST

/// Information about a Python class parsed from source code using AST
public struct PythonClassInfo {
    public let name: String
    public let baseClasses: [String]
    public let methods: [Statement]  // Store actual AST nodes for methods (excluding __init__)
    public let classDefAST: ClassDef  // Store the entire class AST
    
    public init(name: String, baseClasses: [String], methods: [Statement], classDefAST: ClassDef) {
        self.name = name
        self.baseClasses = baseClasses
        self.methods = methods
        self.classDefAST = classDefAST
    }
}

/// Parser to extract class information from Python source code using PySwiftAST
public struct PythonClassParser {
    
    private let source: String
    
    public init(source: String) {
        self.source = source
    }
    
    /// Parse the Python source and extract class definitions using PySwiftAST
    public func parse() -> [PythonClassInfo] {
        var classes: [PythonClassInfo] = []
        
        do {
            // Parse the Python source code into an AST
            let astModule = try parsePython(source)
           
            // Extract class definitions from the statements
            for statement in astModule.body {
                if case .classDef(let classDef) = statement {
                    let classInfo = extractClassInfo(from: classDef)
                    classes.append(classInfo)
                }
            }
        } catch {
            print("Error parsing Python code: \(error)")
            // Return empty array if parsing fails
        }
        
        return classes
    }
    
    /// Extract class information from a ClassDef AST node
    private func extractClassInfo(from classDef: ClassDef) -> PythonClassInfo {
        let className = classDef.name
        
        // Extract base class names from the AST
        let baseClasses = classDef.bases.compactMap { expr -> String? in
            if case .name(let name) = expr {
                return name.id
            }
            return nil
        }
        
        // Extract method definitions (exclude __init__ since we'll generate it)
        let methods = classDef.body.filter { statement in
            if case .functionDef(let funcDef) = statement {
                return funcDef.name != "__init__"
            }
            return false
        }
        
        return PythonClassInfo(
            name: className,
            baseClasses: baseClasses,
            methods: methods,
            classDefAST: classDef
        )
    }
}
