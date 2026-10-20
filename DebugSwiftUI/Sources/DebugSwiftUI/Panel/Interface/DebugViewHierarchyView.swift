import SwiftUI

/// The foreground window as an expandable tree. Compose content shows its semantics nodes, so
/// elements can be told apart by text, description and test tag.
struct DebugViewHierarchyView: View {
    @State var tree: DebugViewTree? = nil
    @State var collapsed: Set<String> = []
    @State var hidingInvisible = true
    @State var failure = ""

    var rows: [DebugViewRow] {
        guard let tree else { return [] }
        return DebugViewRows.flatten(tree.root, collapsed: collapsed, hidingInvisible: hidingInvisible)
    }

    var body: some View {
        List {
            Section {
                Toggle("Hide invisible", isOn: $hidingInvisible)
                Button("Refresh") { load() }
                if let tree {
                    Text(verbatim: "\(tree.windowWidth) × \(tree.windowHeight) px, density \(tree.density)")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                    if tree.truncated {
                        Text(verbatim: "Large screen: the tree stops at 2500 elements.")
                            .font(.caption)
                            .foregroundColor(Color.orange)
                    }
                }
            }
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            ForEach(rows) { row in
                DebugViewRowView(
                    row: row,
                    tree: tree,
                    isCollapsed: collapsed.contains(row.id),
                    toggle: { toggle(row.id) },
                )
            }
        }
        .navigationTitle("View Hierarchy")
        .onAppear { load() }
    }

    func toggle(_ id: String) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    func load() {
        switch DebugViewTree.load() {
        case let .success(value):
            tree = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}

struct DebugViewRowView: View {
    let row: DebugViewRow
    let tree: DebugViewTree?
    let isCollapsed: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if !row.node.children.isEmpty {
                Button(isCollapsed ? "▸" : "▾") { toggle() }
                    .buttonStyle(.plain)
                    .frame(width: 22)
            } else {
                Spacer().frame(width: 22)
            }
            NavigationLink {
                if let tree {
                    DebugViewNodeDetailView(node: row.node, tree: tree)
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(verbatim: row.node.name)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(row.node.kind == "compose" ? Color.green : Color.primary)
                        Spacer()
                        if let tree {
                            Text(verbatim: "\(tree.dp(row.node.width)) × \(tree.dp(row.node.height))")
                                .font(.caption2)
                                .foregroundColor(Color.secondary)
                        }
                    }
                    if !row.node.label.isEmpty {
                        Text(verbatim: row.node.label)
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.leading, Double(min(row.depth, 14)) * 10)
    }
}

struct DebugViewNodeDetailView: View {
    let node: DebugViewNode
    let tree: DebugViewTree

    var body: some View {
        List {
            Section {
                Button("Highlight in the app") { debugHighlight([node]) }
            }
            Section("Element") {
                LabeledContent("Kind") { Text(verbatim: node.kind == "compose" ? "Compose semantics" : "Android view") }
                LabeledContent("Type") { Text(verbatim: node.name) }
                if !node.resourceId.isEmpty {
                    LabeledContent(node.kind == "compose" ? "Test tag" : "Id") { Text(verbatim: node.resourceId) }
                }
                if let text = node.text {
                    LabeledContent("Text") { Text(verbatim: text).multilineTextAlignment(.trailing) }
                }
                if let description = node.description {
                    LabeledContent("Description") { Text(verbatim: description).multilineTextAlignment(.trailing) }
                }
            }
            Section("Layout") {
                LabeledContent("Position") { Text(verbatim: "\(tree.dp(node.left)), \(tree.dp(node.top))") }
                LabeledContent("Size") { Text(verbatim: "\(tree.dp(node.width)) × \(tree.dp(node.height))") }
                LabeledContent("In pixels") {
                    Text(verbatim: "\(node.left),\(node.top) to \(node.right),\(node.bottom)")
                }
                LabeledContent("Children") { Text(verbatim: "\(node.children.count)") }
            }
            Section("State") {
                LabeledContent("Visible") { Text(verbatim: node.visible ? "Yes" : "No") }
                LabeledContent("Enabled") { Text(verbatim: node.enabled ? "Yes" : "No") }
                LabeledContent("Clickable") { Text(verbatim: node.clickable ? "Yes" : "No") }
                LabeledContent("Alpha") { Text(verbatim: String(format: "%.2f", node.alpha)) }
            }
            if node.kind == "view" {
                Section("Class") {
                    Text(verbatim: node.className)
                        .font(.system(.footnote, design: .monospaced))
                }
            }
        }
        .navigationTitle(Text(verbatim: node.name))
    }
}
