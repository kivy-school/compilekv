//
//  ExpressionRewriting.swift
//  KvToPyClass
//
//  Tree walks over PySwiftAST expressions and statements: renaming, name
//  collection, and the watched-key visitor.

import PySwiftAST

// MARK: - Name Mapping

/// Walk an expression tree, replacing Name nodes the transform answers for.
func mapNames(in expr: Expression, _ transform: (Name) -> Expression?) -> Expression {
    switch expr {
    case .name(let node):
        return transform(node) ?? expr
        
    case .attribute(let node):
        return .attribute(Attribute(
            value: mapNames(in: node.value, transform),
            attr: node.attr,
            ctx: node.ctx,
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .joinedStr(let node):
        return .joinedStr(JoinedStr(
            values: node.values.map { mapNames(in: $0, transform) },
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .formattedValue(let node):
        return .formattedValue(FormattedValue(
            value: mapNames(in: node.value, transform),
            conversion: node.conversion,
            formatSpec: node.formatSpec,
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .call(let node):
        return .call(Call(
            fun: mapNames(in: node.fun, transform),
            args: node.args.map { mapNames(in: $0, transform) },
            keywords: node.keywords.map { Keyword(arg: $0.arg, value: mapNames(in: $0.value, transform)) },
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .subscriptExpr(let node):
        return .subscriptExpr(Subscript(
            value: mapNames(in: node.value, transform),
            slice: mapNames(in: node.slice, transform),
            ctx: node.ctx,
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .unaryOp(let node):
        return .unaryOp(UnaryOp(op: node.op, operand: mapNames(in: node.operand, transform), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .boolOp(let node):
        return .boolOp(BoolOp(op: node.op, values: node.values.map { mapNames(in: $0, transform) }, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .compare(let node):
        return .compare(Compare(
            left: mapNames(in: node.left, transform),
            ops: node.ops,
            comparators: node.comparators.map { mapNames(in: $0, transform) },
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .dict(let node):
        return .dict(Dict(
            keys: node.keys.map { $0.map { mapNames(in: $0, transform) } },
            values: node.values.map { mapNames(in: $0, transform) },
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
        
    case .tuple(let node):
        return .tuple(Tuple(elts: node.elts.map { mapNames(in: $0, transform) }, ctx: node.ctx, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .list(let node):
        return .list(List(elts: node.elts.map { mapNames(in: $0, transform) }, ctx: node.ctx, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .binOp(let node):
        return .binOp(BinOp(left: mapNames(in: node.left, transform), op: node.op, right: mapNames(in: node.right, transform), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .ifExp(let node):
        return .ifExp(IfExp(test: mapNames(in: node.test, transform), body: mapNames(in: node.body, transform), orElse: mapNames(in: node.orElse, transform), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    default:
        return expr
    }
}

/// `mapNames(in:)` over a statement: every expression it holds, through
/// nested blocks. Statement kinds a KV block is unlikely to contain
/// (class and function definitions, imports) pass through untouched.
func mapNames(inStatement statement: Statement, _ transform: (Name) -> Expression?) -> Statement {
    func map(_ expr: Expression) -> Expression { mapNames(in: expr, transform) }
    func map(_ statements: [Statement]) -> [Statement] { statements.map { mapNames(inStatement: $0, transform) } }
    
    switch statement {
    case .expr(let node):
        return .expr(Expr(value: map(node.value), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
    case .assign(let node):
        return .assign(Assign(targets: node.targets.map(map), value: map(node.value), typeComment: node.typeComment, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
    case .augAssign(let node):
        return .augAssign(AugAssign(target: map(node.target), op: node.op, value: map(node.value), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
    case .annAssign(let node):
        return .annAssign(AnnAssign(target: map(node.target), annotation: node.annotation, value: node.value.map(map), simple: node.simple, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
    case .returnStmt(let node):
        return .returnStmt(Return(value: node.value.map(map), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
    case .ifStmt(let node):
        return .ifStmt(If(test: map(node.test), body: map(node.body), orElse: map(node.orElse), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
    case .whileStmt(let node):
        return .whileStmt(While(test: map(node.test), body: map(node.body), orElse: map(node.orElse), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
    case .forStmt(let node):
        return .forStmt(For(target: map(node.target), iter: map(node.iter), body: map(node.body), orElse: map(node.orElse), typeComment: node.typeComment, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
    case .withStmt(let node):
        return .withStmt(With(
            items: node.items.map { WithItem(contextExpr: map($0.contextExpr), optionalVars: $0.optionalVars.map(map)) },
            body: map(node.body), typeComment: node.typeComment,
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
    case .tryStmt(let node):
        return .tryStmt(Try(
            body: map(node.body),
            handlers: node.handlers.map { ExceptHandler(type: $0.type.map(map), name: $0.name, body: map($0.body)) },
            orElse: map(node.orElse), finalBody: map(node.finalBody),
            lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
        ))
    case .raise(let node):
        return .raise(Raise(exc: node.exc.map(map), cause: node.cause.map(map), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
    case .assertStmt(let node):
        return .assertStmt(Assert(test: map(node.test), msg: node.msg.map(map), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
    default:
        return statement
    }
}

/// Resolve KV's two implicit objects in an expression tree.
///
/// `root` is the widget the rule applies to, which is `self` in the generated
/// __init__. `self` is the widget whose block the value was written in, which
/// is the rule root at the top level but a child's variable inside a child
/// block -- `height: self.texture_size[1]` under a Label means that Label.
///
/// Both are mapped in one pass so a `root` rewritten to `self` is not then
/// rewritten again into the child's variable.
func resolveKvObjects(_ expr: Expression, selfName: String) -> Expression {
    mapNames(in: expr) { name in
        let resolved: String
        switch name.id {
        case "root": resolved = "self"
        case "self": resolved = selfName
        default: return nil
        }
        return .name(Name(id: resolved, ctx: name.ctx, lineno: name.lineno, colOffset: name.colOffset, endLineno: name.endLineno, endColOffset: name.endColOffset))
    }
}

// MARK: - Attribute Replacement

/// Replace `object.attr` with a plain name, for a callback that receives the
/// new value as a parameter. Only the node kinds a bound value is likely to
/// be are descended into.
func replaceAttribute(_ key: BindableKey, withName replacement: String, in expr: Expression) -> Expression {
    let object = key.source.name
    let attr = key.property
    switch expr {
    case .attribute(let node):
        if case .name(let nameNode) = node.value, nameNode.id == object, node.attr == attr {
            return Py.name(replacement)
        }
        return expr
        
    case .joinedStr(let node):
        let values = node.values.map { replaceAttribute(key, withName: replacement, in: $0) }
        return .joinedStr(JoinedStr(values: values, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .formattedValue(let node):
        let value = replaceAttribute(key, withName: replacement, in: node.value)
        return .formattedValue(FormattedValue(value: value, conversion: node.conversion, formatSpec: node.formatSpec, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .call(let node):
        let fun = replaceAttribute(key, withName: replacement, in: node.fun)
        let args = node.args.map { replaceAttribute(key, withName: replacement, in: $0) }
        return .call(Call(fun: fun, args: args, keywords: node.keywords, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    default:
        return expr
    }
}

/// Replace every `self.*` with `instance.*`, for a canvas callback that
/// should read the instance it was called with.
func replaceSelfWithInstance(in expr: Expression) -> Expression {
    switch expr {
    case .attribute(let node):
        if case .name(let nameNode) = node.value, nameNode.id == "self" {
            return .attribute(Attribute(
                value: Py.name("instance"),
                attr: node.attr,
                ctx: node.ctx,
                lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset
            ))
        }
        return expr
        
    case .tuple(let node):
        return .tuple(Tuple(elts: node.elts.map(replaceSelfWithInstance), ctx: node.ctx, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .list(let node):
        return .list(List(elts: node.elts.map(replaceSelfWithInstance), ctx: node.ctx, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .binOp(let node):
        return .binOp(BinOp(left: replaceSelfWithInstance(in: node.left), op: node.op, right: replaceSelfWithInstance(in: node.right), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .call(let node):
        return .call(Call(fun: replaceSelfWithInstance(in: node.fun), args: node.args.map(replaceSelfWithInstance), keywords: node.keywords, lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    case .ifExp(let node):
        return .ifExp(IfExp(test: replaceSelfWithInstance(in: node.test), body: replaceSelfWithInstance(in: node.body), orElse: replaceSelfWithInstance(in: node.orElse), lineno: node.lineno, colOffset: node.colOffset, endLineno: node.endLineno, endColOffset: node.endColOffset))
        
    default:
        return expr
    }
}

// MARK: - Name Collection

/// Every Name an expression reads.
func namesUsed(in expr: Expression) -> Swift.Set<String> {
    var names = Swift.Set<String>()
    func walk(_ expr: Expression) {
        switch expr {
        case .name(let node):
            names.insert(node.id)
        case .attribute(let node):
            walk(node.value)
        case .call(let node):
            walk(node.fun)
            node.args.forEach(walk)
            node.keywords.forEach { walk($0.value) }
        case .binOp(let node):
            walk(node.left); walk(node.right)
        case .unaryOp(let node):
            walk(node.operand)
        case .boolOp(let node):
            node.values.forEach(walk)
        case .compare(let node):
            walk(node.left); node.comparators.forEach(walk)
        case .ifExp(let node):
            walk(node.test); walk(node.body); walk(node.orElse)
        case .tuple(let node):
            node.elts.forEach(walk)
        case .list(let node):
            node.elts.forEach(walk)
        case .set(let node):
            node.elts.forEach(walk)
        case .dict(let node):
            node.keys.forEach { $0.map(walk) }
            node.values.forEach(walk)
        case .joinedStr(let node):
            node.values.forEach(walk)
        case .formattedValue(let node):
            walk(node.value)
        case .subscriptExpr(let node):
            walk(node.value); walk(node.slice)
        default:
            break
        }
    }
    walk(expr)
    return names
}

func namesUsed(inStatement statement: Statement) -> Swift.Set<String> {
    var names = Swift.Set<String>()
    forEachExpression(in: statement) { names.formUnion(namesUsed(in: $0)) }
    return names
}

/// Visit every expression a statement holds, nested statements included.
func forEachExpression(in statement: Statement, _ visit: (Expression) -> Void) {
    switch statement {
    case .expr(let node): visit(node.value)
    case .assign(let node): node.targets.forEach(visit); visit(node.value)
    case .augAssign(let node): visit(node.target); visit(node.value)
    case .annAssign(let node): visit(node.target); node.value.map(visit)
    case .returnStmt(let node): node.value.map(visit)
    case .ifStmt(let node):
        visit(node.test)
        (node.body + node.orElse).forEach { forEachExpression(in: $0, visit) }
    case .whileStmt(let node):
        visit(node.test)
        (node.body + node.orElse).forEach { forEachExpression(in: $0, visit) }
    case .forStmt(let node):
        visit(node.target); visit(node.iter)
        (node.body + node.orElse).forEach { forEachExpression(in: $0, visit) }
    case .withStmt(let node):
        node.items.forEach { visit($0.contextExpr) }
        node.body.forEach { forEachExpression(in: $0, visit) }
    case .tryStmt(let node):
        (node.body + node.orElse + node.finalBody).forEach { forEachExpression(in: $0, visit) }
        node.handlers.forEach { handler in
            handler.type.map(visit)
            handler.body.forEach { forEachExpression(in: $0, visit) }
        }
    case .raise(let node): node.exc.map(visit); node.cause.map(visit)
    case .assertStmt(let node): visit(node.test); node.msg.map(visit)
    default: break
    }
}

// MARK: - Watched Keys

/// Collects every `obj.attr` a value expression reads, f-strings included.
final class WatchedKeyVisitor: ExpressionVisitor {
    typealias ExpressionResult = Void
    
    /// `[object, attribute]` pairs, in the order they were met.
    var watchedKeys: [[String]] = []
    
    func visitAttribute(_ node: Attribute) {
        if case .name(let name) = node.value {
            watchedKeys.append([name.id, node.attr])
        }
        visitExpression(node.value)
    }
    
    func visitJoinedStr(_ node: JoinedStr) {
        for value in node.values {
            visitExpression(value)
        }
    }
    
    func visitFormattedValue(_ node: FormattedValue) {
        visitExpression(node.value)
    }
    
    func visitCall(_ node: Call) {
        // Covers str(app.prop) and any other wrapping call.
        visitExpression(node.fun)
        for arg in node.args {
            visitExpression(arg)
        }
    }
    
    func visitConstant(_ node: Constant) {}
    func visitList(_ node: List) {
        for element in node.elts {
            visitExpression(element)
        }
    }
    func visitTuple(_ node: Tuple) {
        for element in node.elts {
            visitExpression(element)
        }
    }
    func visitDict(_ node: Dict) {}
    func visitSet(_ node: Set) {}
    func visitName(_ node: Name) {}
    func visitSubscript(_ node: Subscript) {
        // self.texture_size[1] still watches texture_size
        visitExpression(node.value)
        visitExpression(node.slice)
    }
    func visitStarred(_ node: Starred) {}
    func visitBinOp(_ node: BinOp) {
        visitExpression(node.left)
        visitExpression(node.right)
    }
    func visitUnaryOp(_ node: UnaryOp) {
        visitExpression(node.operand)
    }
    func visitBoolOp(_ node: BoolOp) {
        for value in node.values {
            visitExpression(value)
        }
    }
    func visitCompare(_ node: Compare) {
        visitExpression(node.left)
        for comparator in node.comparators {
            visitExpression(comparator)
        }
    }
    func visitLambda(_ node: Lambda) {}
    func visitListComp(_ node: ListComp) {}
    func visitSetComp(_ node: SetComp) {}
    func visitDictComp(_ node: DictComp) {}
    func visitGeneratorExp(_ node: GeneratorExp) {}
    func visitIfExp(_ node: IfExp) {
        visitExpression(node.test)
        visitExpression(node.body)
        visitExpression(node.orElse)
    }
    func visitNamedExpr(_ node: NamedExpr) {}
    func visitYield(_ node: Yield) {}
    func visitYieldFrom(_ node: YieldFrom) {}
    func visitAwait(_ node: Await) {}
    func visitSlice(_ node: Slice) {}
}
