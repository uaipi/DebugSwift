import SwiftUI

/// Shows the last link the app received and opens any URI as a link intent, to test link handling.
struct DebugDeepLinksView: View {
    @State var uri = ""
    @State var lastLink = ""
    @State var status = ""

    var body: some View {
        Form {
            Section("Last link received") {
                Text(verbatim: lastLink)
                    .font(.system(.footnote, design: .monospaced))
            }
            Section("Open a link") {
                TextField("https://example.com/path", text: $uri)
                Button("Open") { open() }
            }
            if !status.isEmpty {
                Section("Status") {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle("Deep Links")
        .onAppear { lastLink = DebugSwiftAndroidRuntime.snapshot(featureID: "deep_links") }
    }

    func open() {
        switch DebugResourceClient.fetch("app.deeplink.open", ["uri": uri], as: DebugActionReply.self) {
        case let .success(reply):
            status = reply.message ?? "Opened."
        case let .failure(error):
            status = error.message
        }
    }
}
