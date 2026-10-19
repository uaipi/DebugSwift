import DebugSwiftCore
import SwiftUI

/// The debug panel: built-in tools, the host's own tools, actions and info in one list. It is plain
/// SwiftUI, so the same code runs on iOS and, through Skip Fuse, on Android.
public struct DebugPanel: View {
    let title: String
    let tools: [DebugTool]
    let actions: [DebugActionGroup]
    let info: [DebugInfoGroup]
    let recorder: NetworkRecorder
    let showsNetworkInspector: Bool
    let onDone: (@MainActor () -> Void)?

    public init(
        title: String = "Debug",
        tools: [DebugTool] = [],
        actions: [DebugActionGroup] = [],
        info: [DebugInfoGroup] = [],
        recorder: NetworkRecorder = .shared,
        showsNetworkInspector: Bool = true,
        onDone: (@MainActor () -> Void)? = nil
    ) {
        self.title = title
        self.tools = tools
        self.actions = actions
        self.info = info
        self.recorder = recorder
        self.showsNetworkInspector = showsNetworkInspector
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    if showsNetworkInspector {
                        NavigationLink {
                            NetworkInspectorView(model: NetworkInspectorModel(recorder: recorder))
                        } label: {
                            Text(verbatim: "Network inspector")
                        }
                    }
                    if DebugAndroidTools.isAvailable {
                        NavigationLink {
                            AndroidToolSnapshotView(featureID: "device_info", title: "Device info")
                        } label: {
                            Text(verbatim: "Device info")
                        }
                    }
                    ForEach(tools) { tool in
                        NavigationLink {
                            tool.makeContent()
                        } label: {
                            DebugToolRow(tool: tool)
                        }
                    }
                }
                ForEach(actions) { group in
                    Section(group.title) {
                        ForEach(group.actions) { action in
                            Button(action.title) { action.run() }
                        }
                    }
                }
                ForEach(info) { group in
                    Section(group.title) {
                        ForEach(group.items) { item in
                            LabeledContent(item.title) { Text(verbatim: item.value) }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                if let onDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onDone() }
                    }
                }
            }
        }
    }
}

struct DebugToolRow: View {
    let tool: DebugTool

    var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: tool.title)
            if let subtitle = tool.subtitle {
                Text(verbatim: subtitle).font(.caption)
            }
        }
    }
}
