/// A titled group of read-only rows, for example the API URL and the app version.
public struct DebugInfoGroup: Identifiable {
    public struct Item: Identifiable {
        public let id: String
        public let title: String
        public let value: String

        public init(title: String, value: String) {
            id = title
            self.title = title
            self.value = value
        }
    }

    public let id: String
    public let title: String
    public let items: [Item]

    public init(title: String, items: [Item]) {
        id = title
        self.title = title
        self.items = items
    }
}
