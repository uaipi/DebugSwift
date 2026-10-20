/// A titled group of buttons that run host code, for example "Clear user data".
public struct DebugActionGroup: Identifiable {
    public struct Action: Identifiable {
        public let id: String
        public let title: String
        let run: @MainActor () -> Void

        public init(title: String, run: @escaping @MainActor () -> Void) {
            id = title
            self.title = title
            self.run = run
        }
    }

    public let id: String
    public let title: String
    public let actions: [Action]

    public init(title: String, actions: [Action]) {
        id = title
        self.title = title
        self.actions = actions
    }
}
