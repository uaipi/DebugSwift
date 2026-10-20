import Foundation

/// One element of the foreground window: an Android view, or a node of Compose's semantics tree.
struct DebugViewNode: Decodable {
    let kind: String
    let name: String
    let className: String
    let resourceId: String
    let left: Int
    let top: Int
    let width: Int
    let height: Int
    let visible: Bool
    let alpha: Double
    let clickable: Bool
    let enabled: Bool
    let text: String?
    let description: String?
    let children: [DebugViewNode]

    var right: Int { left + width }
    var bottom: Int { top + height }

    /// The best short label for a row: its text, description or id, else its type.
    var label: String {
        if let text, !text.isEmpty { return text }
        if let description, !description.isEmpty { return description }
        if !resourceId.isEmpty { return resourceId }
        return ""
    }

    /// Worth choosing when measuring: it has something a person would point at.
    var isMeaningful: Bool {
        visible && width > 0 && height > 0 && (!label.isEmpty || clickable)
    }
}

struct DebugViewTree: Decodable {
    let windowWidth: Int
    let windowHeight: Int
    let density: Double
    let root: DebugViewNode
    let truncated: Bool

    static func load() -> Result<DebugViewTree, DebugResourceFailure> {
        DebugResourceClient.fetch("app.ui.tree", as: DebugViewTree.self)
    }

    func dp(_ pixels: Int) -> String {
        let value = Double(pixels) / max(density, 0.1)
        return value == value.rounded() ? "\(Int(value)) dp" : String(format: "%.1f dp", value)
    }
}

/// A node placed in the flattened list, with how deep it sits.
struct DebugViewRow: Identifiable {
    let id: String
    let depth: Int
    let node: DebugViewNode
}

enum DebugViewRows {
    /// Walks the tree depth first. A collapsed node hides its children; `hidingInvisible` drops
    /// elements that are not shown.
    static func flatten(_ root: DebugViewNode, collapsed: Set<String>, hidingInvisible: Bool) -> [DebugViewRow] {
        var rows: [DebugViewRow] = []
        func walk(_ node: DebugViewNode, path: String, depth: Int) {
            if hidingInvisible && !node.visible { return }
            rows.append(DebugViewRow(id: path, depth: depth, node: node))
            guard !collapsed.contains(path) else { return }
            for index in 0..<node.children.count {
                walk(node.children[index], path: path + "." + String(index), depth: depth + 1)
            }
        }
        walk(root, path: "0", depth: 0)
        return rows
    }

    /// Every meaningful element, regardless of nesting, for choosing one to measure.
    static func meaningful(_ root: DebugViewNode, matching filter: String) -> [DebugViewRow] {
        var rows: [DebugViewRow] = []
        func walk(_ node: DebugViewNode, path: String, depth: Int) {
            if node.isMeaningful {
                let haystack = (node.label + " " + node.name + " " + node.resourceId).lowercased()
                if filter.isEmpty || haystack.contains(filter.lowercased()) {
                    rows.append(DebugViewRow(id: path, depth: depth, node: node))
                }
            }
            for index in 0..<node.children.count {
                walk(node.children[index], path: path + "." + String(index), depth: depth + 1)
            }
        }
        walk(root, path: "0", depth: 0)
        return rows
    }
}

/// Draws a box in the app over the given elements.
func debugHighlight(_ nodes: [DebugViewNode]) {
    let rects = nodes.map { "\($0.left),\($0.top),\($0.right),\($0.bottom)" }.joined(separator: ";")
    _ = DebugResourceClient.fetch("app.ui.highlight", ["rects": rects], as: DebugActionReply.self)
}
