//
//  Py.swift
//  KvToPyClass
//
//  Builders for the PySwiftAST nodes the generators emit. Position fields
//  are meaningless for generated code, so every node sits at line 1.

import PySwiftAST

/// Foundation also has an `Expression`; ours is the Python one.
typealias Expression = PySwiftAST.Expression

enum Py {
    
    // MARK: Expressions
    
    static func name(_ id: String, ctx: ExprContext = .load) -> Expression {
        .name(Name(id: id, ctx: ctx, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func constant(_ value: ConstantValue) -> Expression {
        .constant(Constant(value: value, kind: nil, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func string(_ value: String) -> Expression { constant(.string(value)) }
    
    static var none: Expression { constant(.none) }
    
    static func attr(_ value: Expression, _ name: String, ctx: ExprContext = .load) -> Expression {
        .attribute(Attribute(value: value, attr: name, ctx: ctx, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    /// `object.name`
    static func attr(_ object: String, _ name: String, ctx: ExprContext = .load) -> Expression {
        attr(Py.name(object), name, ctx: ctx)
    }
    
    /// `self.name`
    static func selfAttr(_ name: String, ctx: ExprContext = .load) -> Expression {
        attr("self", name, ctx: ctx)
    }
    
    static func call(_ function: Expression, _ args: [Expression] = [], keywords: [Keyword] = []) -> Expression {
        .call(Call(fun: function, args: args, keywords: keywords, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    /// `function(args)`
    static func call(_ function: String, _ args: [Expression] = [], keywords: [Keyword] = []) -> Expression {
        call(name(function), args, keywords: keywords)
    }
    
    /// `object.method(args)`
    static func method(_ object: Expression, _ method: String, _ args: [Expression] = [], keywords: [Keyword] = []) -> Expression {
        call(attr(object, method), args, keywords: keywords)
    }
    
    static func method(_ object: String, _ method: String, _ args: [Expression] = [], keywords: [Keyword] = []) -> Expression {
        call(attr(object, method), args, keywords: keywords)
    }
    
    static func keyword(_ arg: String?, _ value: Expression) -> Keyword {
        Keyword(arg: arg, value: value)
    }
    
    static func item(_ value: Expression, _ slice: Expression, ctx: ExprContext = .load) -> Expression {
        .subscriptExpr(Subscript(value: value, slice: slice, ctx: ctx, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func list(_ elts: [Expression] = []) -> Expression {
        .list(List(elts: elts, ctx: .load, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func tuple(_ elts: [Expression], ctx: ExprContext = .load) -> Expression {
        .tuple(Tuple(elts: elts, ctx: ctx, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func dict(_ keys: [Expression], _ values: [Expression]) -> Expression {
        .dict(Dict(keys: keys, values: values, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func compare(_ left: Expression, _ op: CmpOp, _ right: Expression) -> Expression {
        .compare(Compare(left: left, ops: [op], comparators: [right], lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func lambda(_ params: [String] = [], vararg: String? = nil, body: Expression) -> Expression {
        .lambda(Lambda(args: arguments(params, vararg: vararg), body: body, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func arguments(_ params: [String], vararg: String? = nil, kwarg: String? = nil) -> Arguments {
        Arguments(
            posonlyArgs: [],
            args: params.map { Arg(arg: $0, annotation: nil, typeComment: nil) },
            vararg: vararg.map { Arg(arg: $0, annotation: nil, typeComment: nil) },
            kwonlyArgs: [],
            kwDefaults: [],
            kwarg: kwarg.map { Arg(arg: $0, annotation: nil, typeComment: nil) },
            defaults: []
        )
    }
    
    // MARK: Statements
    
    static func expr(_ value: Expression) -> Statement {
        .expr(Expr(value: value, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func assign(_ target: Expression, _ value: Expression) -> Statement {
        .assign(Assign(targets: [target], value: value, typeComment: nil, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    /// `name = value`
    static func assign(_ name: String, _ value: Expression) -> Statement {
        assign(Py.name(name, ctx: .store), value)
    }
    
    /// `object.attribute = value`
    static func assign(_ object: String, _ attribute: String, _ value: Expression) -> Statement {
        assign(attr(object, attribute, ctx: .store), value)
    }
    
    static var pass: Statement {
        .pass(Pass(lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func def(_ name: String, params: [String], vararg: String? = nil, kwarg: String? = nil, body: [Statement]) -> Statement {
        .functionDef(FunctionDef(
            name: name,
            args: arguments(params, vararg: vararg, kwarg: kwarg),
            body: body,
            decoratorList: [],
            returns: nil,
            typeComment: nil,
            typeParams: [],
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        ))
    }
    
    static func `if`(_ test: Expression, _ body: [Statement], orElse: [Statement] = []) -> Statement {
        .ifStmt(If(test: test, body: body, orElse: orElse, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func `for`(_ target: Expression, in iter: Expression, _ body: [Statement]) -> Statement {
        .forStmt(For(target: target, iter: iter, body: body, orElse: [], typeComment: nil, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    /// `try: body except type: handler`; a nil type catches everything.
    static func `try`(_ body: [Statement], except type: Expression? = nil, _ handler: [Statement]) -> Statement {
        .tryStmt(Try(
            body: body,
            handlers: [ExceptHandler(type: type, name: nil, body: handler)],
            orElse: [],
            finalBody: [],
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        ))
    }
    
    static func with(_ context: Expression, _ body: [Statement]) -> Statement {
        .withStmt(With(
            items: [WithItem(contextExpr: context, optionalVars: nil)],
            body: body,
            typeComment: nil,
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        ))
    }
    
    static func importFrom(_ module: String, _ names: [Alias], lineno: Int = 1) -> Statement {
        .importFrom(ImportFrom(module: module, names: names, level: 0, lineno: lineno, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func `import`(_ names: [Alias]) -> Statement {
        .importStmt(Import(names: names, lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil))
    }
    
    static func classDef(_ name: String, bases: [String], body: [Statement]) -> Statement {
        .classDef(ClassDef(
            name: name,
            bases: bases.map { Py.name($0) },
            keywords: [],
            body: body,
            decoratorList: [],
            typeParams: [],
            lineno: 1, colOffset: 0, endLineno: nil, endColOffset: nil
        ))
    }
}
