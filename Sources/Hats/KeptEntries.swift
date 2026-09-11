extension Dictionary where Key == String {
    func kept(for ids: Set<String>) -> [String: Value] {
        filter { ids.contains($0.key) }
    }
}
