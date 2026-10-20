import SwiftUI

/// A tool whose snapshot is "Name: value" lines (device info, custom info), shown as rows.
struct DebugKeyValueView: View {
    let featureID: String
    let title: String
    @State var rows: [DebugKeyValueRow] = []

    var body: some View {
        List {
            if rows.isEmpty {
                Text(verbatim: "Nothing to show.")
                    .foregroundColor(Color.secondary)
            }
            ForEach(0..<rows.count, id: \.self) { index in
                if rows[index].value.isEmpty {
                    Text(verbatim: rows[index].name)
                } else {
                    LabeledContent(rows[index].name) {
                        Text(verbatim: rows[index].value)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .onAppear { load() }
    }

    func load() {
        rows = DebugSwiftAndroidRuntime.snapshot(featureID: featureID)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                guard let separator = line.range(of: ": ") else { return DebugKeyValueRow(name: String(line), value: "") }
                return DebugKeyValueRow(
                    name: String(line[line.startIndex..<separator.lowerBound]),
                    value: String(line[separator.upperBound...]),
                )
            }
    }
}

struct DebugKeyValueRow {
    let name: String
    let value: String
}
