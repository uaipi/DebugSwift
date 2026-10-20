import SwiftUI

/// A screen the host app adds to the debug panel, for example its feature flag editor.
public struct DebugTool: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    let makeContent: @MainActor () -> AnyView

    public init<Content: View>(
        id: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping @MainActor () -> Content
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        makeContent = { AnyView(content()) }
    }
}
