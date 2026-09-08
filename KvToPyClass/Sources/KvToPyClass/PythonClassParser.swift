import Foundation
import PySwiftAST

/// Information about a Python class parsed from source code using AST
public struct PythonClassInfo {
    public let name: String
    public let baseClasses: [String]
    public let methods: [Statement]  // Store actual AST nodes for methods (excluding __init__)
    public let classDefAST: ClassDef  // Store the entire class AST
    /// Class level Kivy properties by name, e.g. `name: "StringProperty"`.
    /// These are bindable, unlike a plain attribute, and the type says what
    /// kind of value the property can hold.
    public let kivyProperties: [String: String]
    
    public init(
        name: String,
        baseClasses: [String],
        methods: [Statement],
        classDefAST: ClassDef,
        kivyProperties: [String: String] = [:]
    ) {
        self.name = name
        self.baseClasses = baseClasses
        self.methods = methods
        self.classDefAST = classDefAST
        self.kivyProperties = kivyProperties
    }
}

/// A parsed Python file: its whole module body plus the classes in it.
public struct PythonModuleInfo {
    public let body: [Statement]
    public let classes: [PythonClassInfo]

    public init(body: [Statement], classes: [PythonClassInfo]) {
        self.body = body
        self.classes = classes
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
        parseModule().classes
    }

    /// Parse the source, keeping the module body so the generator can extend
    /// the original file instead of replacing it.
    public func parseModule() -> PythonModuleInfo {
        do {
            let astModule = try parsePython(source)
            var classes: [PythonClassInfo] = []
            for statement in astModule.body {
                if case .classDef(let classDef) = statement {
                    classes.append(extractClassInfo(from: classDef))
                }
            }
            return PythonModuleInfo(body: astModule.body, classes: classes)
        } catch {
            print("Error parsing Python code: \(error)")
            return PythonModuleInfo(body: [], classes: [])
        }
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
            classDefAST: classDef,
            kivyProperties: extractKivyProperties(from: classDef)
        )
    }
    
    /// Class level assignments of a Kivy property, e.g. `name = StringProperty("")`.
    private func extractKivyProperties(from classDef: ClassDef) -> [String: String] {
        var properties: [String: String] = [:]
        for statement in classDef.body {
            guard case .assign(let assign) = statement,
                  case .call(let call) = assign.value,
                  case .name(let callee) = call.fun,
                  callee.id.hasSuffix("Property")
            else { continue }
            for target in assign.targets {
                if case .name(let name) = target {
                    properties[name.id] = callee.id
                }
            }
        }
        return properties
    }
}
