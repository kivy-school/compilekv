/// The rule currently being generated: which class, and which of its
/// properties can be bound to.
final class RuleContext {
    var className = ""
    var baseClasses: [String] = []
    var selfProperties = Swift.Set<String>()
    /// Every id the rule's own widget tree declares, at any depth.
    var ids = Swift.Set<String>()
    /// Methods the conditional blocks of this rule produced, in order.
    var conditionalMethods: [Statement] = []
    /// Reset methods of those blocks, so `__del__` can tear them down.
    var conditionalResets: [String] = []
    /// Function name of each `name: |` value block, keyed by line and name.
    var blockFunctions: [String: String] = [:]
    private var conditionalCount = 0

    func nextConditionalIndex() -> Int {
        defer { conditionalCount += 1 }
        return conditionalCount
    }

    func reset() {
        ids = []
        conditionalMethods = []
        conditionalResets = []
        blockFunctions = [:]
        conditionalCount = 0
    }
}