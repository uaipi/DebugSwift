import SwiftUI

/// Android Keystore aliases with what the system reports about each key. Key material is never read.
struct DebugKeystoreView: View {
    @State var aliases: [DebugKeystoreAlias] = []
    @State var failure = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if aliases.isEmpty && failure.isEmpty {
                Text(verbatim: "No keys in the Android Keystore.")
                    .foregroundColor(Color.secondary)
            }
            ForEach(aliases) { alias in
                DebugKeystoreRow(alias: alias)
            }
        }
        .navigationTitle("Secure Storage")
        .onAppear { load() }
    }

    func load() {
        switch DebugResourceClient.fetch("keystore.list", as: DebugKeystoreListing.self) {
        case let .success(value):
            aliases = value.aliases
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}

struct DebugKeystoreRow: View {
    let alias: DebugKeystoreAlias

    var details: String {
        var parts: [String] = []
        if let algorithm = alias.algorithm, !algorithm.isEmpty { parts.append(algorithm) }
        if let size = alias.size { parts.append("\(size) bits") }
        if alias.insideSecureHardware == true { parts.append("hardware-backed") }
        if alias.requiresUserAuthentication == true { parts.append("needs authentication") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: alias.alias)
            if !details.isEmpty {
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
        }
    }
}
