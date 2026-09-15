final class NameCounter {
    private var next = 0

    func take() -> Int {
        next += 1
        return next
    }

    func reset() {
        next = 0
    }
}