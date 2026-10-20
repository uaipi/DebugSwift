import SwiftUI

/// Shows a text file from app storage, with share and delete.
struct DebugFilePreviewView: View {
    let path: String
    @State var content: DebugFileContent? = nil
    @State var failure = ""
    @State var status = ""
    @State var confirmsDelete = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !failure.isEmpty {
                    Text(verbatim: failure).foregroundColor(Color.red)
                }
                if let content {
                    Text(verbatim: debugByteCount(content.size))
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                    if content.isText {
                        Text(verbatim: content.text ?? "")
                            .font(.system(.footnote, design: .monospaced))
                    } else {
                        Text(verbatim: content.note ?? "No preview available.")
                            .foregroundColor(Color.secondary)
                    }
                }
                Button("Share") { share() }
                Button("Delete", role: .destructive) { confirmsDelete = true }
                if !status.isEmpty {
                    Text(verbatim: status).font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .navigationTitle(Text(verbatim: String(path.split(separator: "/").last ?? "File")))
        .onAppear { load() }
        .alert("Delete this file?", isPresented: $confirmsDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { delete() }
        }
    }

    func load() {
        switch DebugResourceClient.fetch("files.read", ["path": path], as: DebugFileContent.self) {
        case let .success(value):
            content = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }

    func share() {
        _ = DebugSwiftAndroidRuntime.perform(featureID: "files", actionID: "browse_files", value: path)
        status = DebugSwiftAndroidRuntime.perform(featureID: "files", actionID: "export")
    }

    func delete() {
        switch DebugResourceClient.fetch("files.delete", ["path": path], as: DebugFileDeletion.self) {
        case let .success(result):
            if result.ok { dismiss() } else { status = result.message }
        case let .failure(error):
            status = error.message
        }
    }
}
