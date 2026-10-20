import SwiftUI

struct DebugPushTokenReply: Decodable {
    let token: String
}

/// The Firebase registration token the app reported, with a copy button for sending a test push.
struct DebugPushTokenView: View {
    @State var token = ""
    @State var status = ""

    var hasToken: Bool {
        !token.isEmpty && !token.hasPrefix("No FCM token")
    }

    var body: some View {
        List {
            Section("Registration token") {
                Text(verbatim: token.isEmpty ? "Reading..." : token)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(hasToken ? Color.primary : Color.secondary)
            }
            Section {
                if hasToken {
                    Button("Copy the token") {
                        DebugClipboard.copy(token)
                        status = "Token copied."
                    }
                }
                Button("Refresh") { load() }
                if !status.isEmpty {
                    Text(verbatim: status).font(.caption)
                }
            }
            if !hasToken {
                Section {
                    Text(verbatim: "The app reports its token with DebugSwiftAndroidRuntime.reportPushToken(_:) when it learns it. Notification permission and Google services must be available.")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }
        }
        .navigationTitle("Push Token")
        .onAppear { load() }
    }

    func load() {
        if case let .success(reply) = DebugResourceClient.fetch("app.push.token", as: DebugPushTokenReply.self) {
            token = reply.token
        }
    }
}
