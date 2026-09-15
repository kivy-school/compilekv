//
//  DelMethodGenerator.swift
//  KvToPyClass
//

import PySwiftAST

/// `__del__`: tear down the conditional blocks, unbind every tracked
/// callback and drop the children, so the tree this class built does not
/// outlive it.
final class DelMethodGenerator {
    
    func delMethod(resets: [String]) -> Statement {
        var body: [Statement] = []
        
        // Whatever the conditional blocks built goes first, while the
        // widgets it hangs off still exist.
        for reset in resets {
            body.append(Py.expr(Py.method("self", reset)))
        }
        
        // for obj, prop, callback in self._bindings:
        //     try:
        //         obj.unbind(**{prop: callback})
        //     except:
        //         pass
        body.append(Py.for(
            Py.tuple([Py.name("obj"), Py.name("prop"), Py.name("callback")], ctx: .store),
            in: Py.selfAttr("_bindings"),
            [Py.try([Py.expr(Py.method("obj", "unbind", keywords: [
                Py.keyword(nil, Py.dict([Py.name("prop")], [Py.name("callback")]))
            ]))], [Py.pass])]
        ))
        
        // try:
        //     self.clear_widgets()
        // except:
        //     pass
        body.append(Py.try([Py.expr(Py.method("self", "clear_widgets"))], [Py.pass]))
        
        return Py.def("__del__", params: ["self"], body: body)
    }
}
