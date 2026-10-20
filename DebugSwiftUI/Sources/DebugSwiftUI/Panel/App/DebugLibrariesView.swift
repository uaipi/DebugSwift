import SwiftUI

struct DebugLibrary: Decodable, Identifiable {
    let path: String
    let name: String
    let size: Int
    let origin: String

    /// Prefixed so a path that is both a split and a mapped file stays unique in one list.
    var id: String { "library-" + path }
}

struct DebugCodePath: Identifiable {
    let path: String
    var id: String { "split-" + path }
}

struct DebugAppLibrary: Decodable, Identifiable {
    let name: String
    let size: Int
    var id: String { "packed-" + name }
}

struct DebugLibrariesInfo: Decodable {
    let appLibraries: [DebugAppLibrary]
    let packageName: String
    let abis: String
    let nativeDirectory: String
    let sourceDirectory: String
    let splits: [String]
    let classLoader: String
    let nativeHeap: Int
    let libraries: [DebugLibrary]
}

/// The app and its native libraries as the process has them mapped now: what is loaded, from where,
/// and how much address space each takes.
struct DebugLibrariesView: View {
    @State var info: DebugLibrariesInfo? = nil
    @State var filter = ""
    @State var origin = "All"
    @State var failure = ""

    let origins = ["All", "App", "System"]

    var visible: [DebugLibrary] {
        guard let info else { return [] }
        return info.libraries.filter { library in
            (origin == "All" || library.origin == origin)
                && (filter.isEmpty || library.name.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let info {
                Section("App") {
                    LabeledContent("Package") { Text(verbatim: info.packageName) }
                    LabeledContent("Supported ABIs") { Text(verbatim: info.abis).multilineTextAlignment(.trailing) }
                    LabeledContent("Native heap") { Text(verbatim: debugByteCount(info.nativeHeap)) }
                    LabeledContent("Class loader") { Text(verbatim: info.classLoader).multilineTextAlignment(.trailing) }
                }
                Section("Code") {
                    Text(verbatim: info.sourceDirectory)
                        .font(.system(.footnote, design: .monospaced))
                    ForEach(info.splits.map { DebugCodePath(path: $0) }) { split in
                        Text(verbatim: split.path)
                            .font(.system(.footnote, design: .monospaced))
                    }
                    Text(verbatim: "Native: " + info.nativeDirectory)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(Color.secondary)
                }
                Section("Native libraries in the app (\(info.appLibraries.count))") {
                    ForEach(info.appLibraries) { library in
                        HStack {
                            Text(verbatim: library.name)
                            Spacer()
                            Text(verbatim: debugByteCount(library.size))
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                        }
                    }
                }
                Section {
                    TextField("Filter by name", text: $filter)
                    HStack(spacing: 14) {
                        ForEach(origins, id: \.self) { candidate in
                            Button(candidate) { origin = candidate }
                                .foregroundColor(origin == candidate ? Color.accentColor : Color.secondary)
                        }
                        Spacer()
                        Text(verbatim: "\(visible.count) of \(info.libraries.count)")
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                }
                Section("Mapped libraries and code files") {
                    ForEach(visible) { library in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(verbatim: library.name)
                                Spacer()
                                Text(verbatim: debugByteCount(library.size))
                                    .font(.caption)
                                    .foregroundColor(Color.secondary)
                            }
                            Text(verbatim: library.origin + " · " + library.path)
                                .font(.caption2)
                                .foregroundColor(Color.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            Section {
                Button("Refresh") { load() }
            }
        }
        .navigationTitle("Installed Libraries")
        .onAppear { load() }
    }

    func load() {
        switch DebugResourceClient.fetch("app.libraries", as: DebugLibrariesInfo.self) {
        case let .success(value):
            info = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
