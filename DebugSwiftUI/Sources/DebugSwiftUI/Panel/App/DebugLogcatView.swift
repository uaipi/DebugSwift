import SwiftUI

/// This process's Logcat, filterable by minimum level and by text in the tag or message.
struct DebugLogcatView: View {
    @State var entries: [DebugLogEntry] = []
    @State var filter = ""
    @State var level = "V"
    @State var failure = ""

    let levels = ["V", "D", "I", "W", "E"]

    var body: some View {
        List {
            Section {
                TextField("Filter tag or message", text: $filter)
                HStack(spacing: 8) {
                    ForEach(levels, id: \.self) { candidate in
                        Button(candidate) {
                            level = candidate
                            load()
                        }
                        .foregroundColor(level == candidate ? Color.accentColor : Color.secondary)
                    }
                    Spacer()
                    Button("Refresh") { load() }
                }
            }
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            ForEach(0..<entries.count, id: \.self) { index in
                DebugLogRow(entry: entries[index])
            }
        }
        .navigationTitle("System Log")
        .onAppear { load() }
    }

    func load() {
        let result = DebugResourceClient.fetch("app.logcat", ["filter": filter, "level": level], as: DebugLogListing.self)
        switch result {
        case let .success(value):
            entries = value.entries
            failure = value.entries.isEmpty ? "No matching Logcat records." : ""
        case let .failure(error):
            failure = error.message
        }
    }
}

struct DebugLogRow: View {
    let entry: DebugLogEntry

    var color: Color {
        switch entry.level {
        case "E", "F": Color.red
        case "W": Color.orange
        case "V", "D": Color.secondary
        default: Color.primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "\(entry.time)  \(entry.level)  \(entry.tag)")
                .font(.caption)
                .foregroundColor(Color.secondary)
            Text(verbatim: entry.message)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
