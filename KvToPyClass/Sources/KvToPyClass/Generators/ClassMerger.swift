//
//  ClassMerger.swift
//  KvToPyClass
//

import PySwiftAST

/// Folds generated members into a class body the author wrote.
final class ClassMerger {
    
    /// The author's body is the starting point, so properties, annotations,
    /// the docstring, nested classes and anything else stay put. A generated
    /// method replaces the one it shares a name with, except `__init__`, which
    /// is appended to rather than replaced.
    func merge(_ generated: [Statement], into existing: [Statement]) -> [Statement] {
        var generatedFunctions: [String: FunctionDef] = [:]
        for statement in generated {
            if case .functionDef(let function) = statement {
                generatedFunctions[function.name] = function
            }
        }
        
        var result: [Statement] = []
        var replaced = Swift.Set<String>()
        for statement in existing {
            switch statement {
            case .functionDef(let existingFunction):
                guard let generatedFunction = generatedFunctions[existingFunction.name] else {
                    result.append(statement)
                    continue
                }
                replaced.insert(existingFunction.name)
                result.append(.functionDef(
                    existingFunction.name == "__init__"
                        ? mergedInit(existing: existingFunction, generated: generatedFunction)
                        : generatedFunction
                ))
            case .pass:
                // The class has real content now.
                continue
            default:
                result.append(statement)
            }
        }
        
        let bound = StatementQueries.boundNames(in: existing)
        for statement in generated {
            switch statement {
            case .blank:
                continue
            case .functionDef(let function) where replaced.contains(function.name):
                continue
            case .assign(let assign):
                // Never shadow a property the author declared themselves.
                if case .name(let target) = assign.targets.first, bound.contains(target.id) {
                    continue
                }
            default:
                break
            }
            result.append(statement)
        }
        
        if result.isEmpty {
            return [Py.pass]
        }
        return separateNestedClasses(in: openWithBlankLine(result))
    }
    
    /// A class body opens with a blank line, matching what is generated when
    /// there is no existing class to merge into -- otherwise the first run and
    /// the second would differ. A docstring goes flush against the header, and
    /// BlackFormatter puts the blank after it.
    private func openWithBlankLine(_ body: [Statement]) -> [Statement] {
        switch body.first {
        case .blank:
            return body
        case .expr(let expr) where StatementQueries.isStringConstant(expr.value):
            return body
        default:
            return [.blank(1)] + body
        }
    }
    
    /// A blank line before a nested class. BlackFormatter spaces methods but
    /// not classes inside a class body.
    private func separateNestedClasses(in body: [Statement]) -> [Statement] {
        var spaced: [Statement] = []
        for statement in body {
            if case .classDef = statement, let previous = spaced.last {
                if case .blank = previous {} else { spaced.append(.blank(1)) }
            }
            spaced.append(statement)
        }
        return spaced
    }
    
    /// Append the generated __init__ body to the one already there.
    ///
    /// Everything from `self._bindings = []` onwards was written by a previous
    /// run -- nothing else emits that line -- so it is dropped first, which is
    /// what keeps regeneration from stacking copies of the widget tree. The
    /// author's signature and their super() call are the ones that survive.
    private func mergedInit(existing: FunctionDef, generated: FunctionDef) -> FunctionDef {
        var handWritten = existing.body
        if let marker = handWritten.firstIndex(where: StatementQueries.isBindingsInit) {
            handWritten = Array(handWritten[..<marker])
        }
        
        return FunctionDef(
            name: existing.name,
            args: existing.args,
            body: handWritten + generated.body.filter { !StatementQueries.isSuperInit($0) },
            decoratorList: existing.decoratorList,
            returns: existing.returns,
            typeComment: existing.typeComment,
            typeParams: existing.typeParams,
            lineno: existing.lineno, colOffset: existing.colOffset,
            endLineno: existing.endLineno, endColOffset: existing.endColOffset
        )
    }
}
