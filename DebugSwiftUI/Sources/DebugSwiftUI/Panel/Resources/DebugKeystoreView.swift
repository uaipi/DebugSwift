import Foundation
import SwiftUI

/// Secure storage: on Android the Keystore aliases with what the system reports about each key (key
/// material is never read); on iOS the app's keychain items, which can be added, edited and deleted.
struct DebugKeystoreView: View {
    @State var aliases: [DebugKeystoreAlias] = []
    @State var editable = false
    @State var failure = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if aliases.isEmpty && failure.isEmpty {
                Text(verbatim: DebugPlatform.isAndroid ? "No keys in the Android Keystore." : "No keychain items.")
                    .foregroundColor(Color.secondary)
            }
            ForEach(aliases) { alias in
                if editable {
                    NavigationLink {
                        DebugKeychainEditView(service: alias.service ?? "", key: alias.alias, value: alias.value, isNew: false)
                    } label: {
                        DebugKeystoreRow(alias: alias)
                    }
                } else {
                    DebugKeystoreRow(alias: alias)
                }
            }
            if editable {
                NavigationLink {
                    DebugKeychainEditView(service: "", key: "", value: "", isNew: true)
                } label: {
                    Text(verbatim: "Add an item").foregroundColor(Color.accentColor)
                }
            }
        }
        .navigationTitle("Secure Storage")
        .onAppear { load() }
    }

    func load() {
        switch DebugResourceClient.fetch("keystore.list", as: DebugKeystoreListing.self) {
        case let .success(value):
            aliases = value.aliases
            editable = value.editable == true
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
        if let service = alias.service, !service.isEmpty { parts.append(service) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: alias.alias)
            if let value = alias.value {
                Text(verbatim: value)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(2)
            }
            if !details.isEmpty {
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
        }
    }
}

/// Adds, edits or deletes one keychain item (iOS).
struct DebugKeychainEditView: View {
    let service: String
    @State var key: String
    @State var value: String
    let isNew: Bool
    /// False for a stored value that isn't text: it is shown read-only, so saving can't replace it.
    let readable: Bool
    @State var status = ""
    @Environment(\.dismiss) var dismiss

    /// The keychain actions take JSON, so a key with "=" or a service with "|" stays whole. A nil
    /// service, for a new item, means the app's default one.
    static func payload(service: String?, key: String, value: String?) -> String {
        var object = ["key": key]
        if let service { object["service"] = service }
        if let value { object["value"] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    init(service: String, key: String, value: String?, isNew: Bool) {
        self.service = service
        _key = State(initialValue: key)
        _value = State(initialValue: value ?? "")
        self.isNew = isNew
        readable = isNew || value != nil
    }

    var body: some View {
        Form {
            if !service.isEmpty {
                Section("Service") { Text(verbatim: service) }
            }
            Section("Key") {
                if isNew {
                    TextField("key", text: $key)
                } else {
                    Text(verbatim: key)
                }
            }
            Section("Value") {
                if readable {
                    TextField("value", text: $value)
                } else {
                    Text(verbatim: "This value isn't text, so it can't be shown or edited here.")
                        .foregroundColor(Color.secondary)
                }
            }
            Section {
                if readable {
                    Button("Save") {
                        status = DebugSwiftRuntime.perform(featureID: "keychain", actionID: "set_keychain_item", value: Self.payload(service: isNew ? nil : service, key: key, value: value))
                    }
                }
                if !isNew {
                    Button("Delete", role: .destructive) {
                        status = DebugSwiftRuntime.perform(featureID: "keychain", actionID: "delete_keychain_item", value: Self.payload(service: service, key: key, value: nil))
                        // Stay open on failure, so the message shows and Delete can be tried again.
                        if status.hasPrefix("Deleted") { dismiss() }
                    }
                }
                if !status.isEmpty {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle(Text(verbatim: isNew ? "New item" : key))
    }
}
