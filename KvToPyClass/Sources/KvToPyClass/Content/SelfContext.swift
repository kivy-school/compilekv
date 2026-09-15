/// What KV's `self` refers to right now: the rule root by default, or the
/// child widget whose block is being generated.
final class SelfContext {
    var name = "self"
    var widgetType: String?
}