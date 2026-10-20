import SwiftUI

/// Pick two elements of the screen and read the distance between them.
struct DebugMeasurementView: View {
    @State var tree: DebugViewTree? = nil
    @State var filter = ""
    @State var first: DebugViewRow? = nil
    @State var second: DebugViewRow? = nil
    @State var failure = ""

    var rows: [DebugViewRow] {
        guard let tree else { return [] }
        return DebugViewRows.meaningful(tree.root, matching: filter)
    }

    var body: some View {
        List {
            Section("Measurement") {
                if let tree, let first, let second {
                    DebugMeasurementResult(tree: tree, a: first.node, b: second.node)
                } else if first != nil {
                    Text(verbatim: "Now choose the second element.")
                        .foregroundColor(Color.secondary)
                } else {
                    Text(verbatim: "Choose two elements below.")
                        .foregroundColor(Color.secondary)
                }
                Button("Start over") {
                    first = nil
                    second = nil
                }
                Button("Refresh") { load() }
            }
            Section {
                TextField("Filter by text, id or type", text: $filter)
            }
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            Section("Elements") {
                ForEach(rows) { row in
                    Button {
                        choose(row)
                    } label: {
                        DebugMeasurementRow(
                            row: row,
                            tree: tree,
                            badge: row.id == first?.id ? "A" : (row.id == second?.id ? "B" : ""),
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Measurement Tool")
        .onAppear { load() }
    }

    func choose(_ row: DebugViewRow) {
        if first == nil || second != nil {
            first = row
            second = nil
            debugHighlight([row.node])
        } else {
            second = row
            if let first { debugHighlight([first.node, row.node]) }
        }
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

struct DebugMeasurementRow: View {
    let row: DebugViewRow
    let tree: DebugViewTree?
    let badge: String

    var body: some View {
        HStack {
            Text(verbatim: badge)
                .font(.headline)
                .foregroundColor(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.node.label.isEmpty ? row.node.name : row.node.label)
                    .lineLimit(1)
                if let tree {
                    Text(verbatim: "\(row.node.name) · \(tree.dp(row.node.width)) × \(tree.dp(row.node.height))")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }
        }
    }
}

struct DebugMeasurementResult: View {
    let tree: DebugViewTree
    let a: DebugViewNode
    let b: DebugViewNode

    /// The empty space between two ranges on one axis; zero when they overlap.
    func gap(_ aStart: Int, _ aEnd: Int, _ bStart: Int, _ bEnd: Int) -> Int {
        if bStart >= aEnd { return bStart - aEnd }
        if aStart >= bEnd { return aStart - bEnd }
        return 0
    }

    var body: some View {
        let horizontal = gap(a.left, a.right, b.left, b.right)
        let vertical = gap(a.top, a.bottom, b.top, b.bottom)
        let centerDX = (b.left + b.right - a.left - a.right) / 2
        let centerDY = (b.top + b.bottom - a.top - a.bottom) / 2
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("A") { Text(verbatim: "\(tree.dp(a.width)) × \(tree.dp(a.height))") }
            LabeledContent("B") { Text(verbatim: "\(tree.dp(b.width)) × \(tree.dp(b.height))") }
            LabeledContent("Horizontal gap") { Text(verbatim: tree.dp(horizontal)) }
            LabeledContent("Vertical gap") { Text(verbatim: tree.dp(vertical)) }
            LabeledContent("Between centers") {
                Text(verbatim: "\(tree.dp(abs(centerDX))) across, \(tree.dp(abs(centerDY))) down")
            }
            LabeledContent("Size difference") {
                Text(verbatim: "\(tree.dp(abs(b.width - a.width))) wide, \(tree.dp(abs(b.height - a.height))) tall")
            }
            if horizontal == 0 && vertical == 0 {
                Text(verbatim: "The two elements overlap.")
                    .font(.caption)
                    .foregroundColor(Color.orange)
            }
        }
    }
}
