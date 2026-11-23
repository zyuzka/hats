enum PopoverSettle {
    static func run(
        isShown: Bool,
        close: () -> Void,
        later: (@escaping () -> Void) -> Void,
        work: @escaping () -> Void
    ) {
        guard isShown else { return work() }
        close()
        later(work)
    }
}
