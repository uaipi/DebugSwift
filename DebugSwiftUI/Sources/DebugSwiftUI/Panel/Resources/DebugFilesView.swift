import SwiftUI

/// Browses the app's private storage (files, cache, databases) one directory at a time.
struct DebugFilesView: View {
    let path: String
    @State var listing: DebugFileListing? = nil
    @State var failure = ""
    @State var confirmsDelete = false
    @Environment(\.dismiss) var dismiss

    /// A folder inside a storage root; the roots themselves can't be deleted.
    var isDeletable: Bool { path.contains("/") }

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure)
                    .foregroundColor(Color.red)
            }
            if let listing {
                if listing.entries.isEmpty {
                    Text(verbatim: "This directory is empty.")
                        .foregroundColor(Color.secondary)
                }
                ForEach(listing.entries) { entry in
                    DebugFileRow(parent: path, entry: entry)
                }
            }
            if isDeletable {
                Section {
                    Button("Delete this folder", role: .destructive) { confirmsDelete = true }
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .onAppear { load() }
        .alert("Delete this folder and everything in it?", isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { delete() }
        }
    }

    func delete() {
        switch DebugResourceClient.fetch("files.delete", ["path": path], as: DebugFileDeletion.self) {
        case let .success(result):
            if result.ok { dismiss() } else { failure = result.message }
        case let .failure(error):
            failure = error.message
        }
    }

    var title: String {
        path.isEmpty ? "Files" : String(path.split(separator: "/").last ?? "Files")
    }

    func load() {
        switch DebugResourceClient.fetch("files.list", ["path": path], as: DebugFileListing.self) {
        case let .success(value):
            listing = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}

struct DebugFileRow: View {
    let parent: String
    let entry: DebugFileEntry

    var childPath: String {
        parent.isEmpty ? entry.name : parent + "/" + entry.name
    }

    var body: some View {
        NavigationLink {
            if entry.isDirectory {
                DebugFilesView(path: childPath)
            } else {
                DebugFilePreviewView(path: childPath)
            }
        } label: {
            HStack {
                Text(verbatim: entry.isDirectory ? entry.name + "/" : entry.name)
                Spacer()
                if !entry.isDirectory {
                    Text(verbatim: debugByteCount(entry.size))
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }
        }
    }
}

#if !os(Android)
#Preview("Files") {
    NavigationStack {
        DebugFilesView(
            path: "files",
            listing: DebugFileListing(path: "files", entries: [
                DebugFileEntry(name: "logs", isDirectory: true, size: 0),
                DebugFileEntry(name: "session.json", isDirectory: false, size: 2_048),
            ]),
        )
    }
}
#endif
