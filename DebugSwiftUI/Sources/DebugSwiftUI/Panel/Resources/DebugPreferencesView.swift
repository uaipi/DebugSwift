import Foundation
import SwiftUI

/// Every preference store the app owns, with each value editable. `includesKeystore` adds the
/// Keystore aliases below the stores, for the combined persistent data screen.
/// A value with its store, so two stores that use the same key do not share a list identity.
struct DebugPreferenceItem: Identifiable {
    let store: String
    let value: DebugPreferenceValue
    var id: String { store + "|" + value.key }
}

struct DebugPreferencesView: View {
    let includesKeystore: Bool
    @State var stores: [DebugPreferenceStore] = []
    @State var failure = ""
    /// iOS only: whether changes since a snapshot can be shown.
    @State var hasChanges = false

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if stores.isEmpty && failure.isEmpty {
                Text(verbatim: "No preference stores found.")
                    .foregroundColor(Color.secondary)
            }
            ForEach(stores) { store in
                Section {
                    ForEach(store.values.map { DebugPreferenceItem(store: store.name, value: $0) }) { item in
                        NavigationLink {
                            DebugPreferenceEditView(store: item.store, key: item.value.key, type: item.value.type, value: item.value.value)
                        } label: {
                            DebugPreferenceRow(value: item.value)
                        }
                    }
                    NavigationLink {
                        DebugPreferenceEditView(store: store.name, key: "", type: "String", value: "")
                    } label: {
                        Text(verbatim: "Add a value").foregroundColor(Color.accentColor)
                    }
                } header: {
                    Text(verbatim: "\(store.name) (\(store.values.count))")
                }
            }
            if hasChanges {
                Section {
                    NavigationLink {
                        DebugPreferenceChangesView()
                    } label: {
                        Text(verbatim: "Changes since the last snapshot")
                    }
                }
            }
            if includesKeystore {
                Section {
                    NavigationLink {
                        DebugKeystoreView()
                    } label: {
                        Text(verbatim: DebugPlatform.isAndroid ? "Keystore aliases" : "Keychain items")
                    }
                }
            }
        }
        .onAppear { load() }
    }

    func load() {
        switch DebugResourceClient.fetch("prefs.list", as: DebugPreferenceListing.self) {
        case let .success(value):
            stores = value.stores
            failure = ""
        case let .failure(error):
            failure = error.message
        }
        if case .success = DebugResourceClient.fetch("prefs.diff", as: DebugPreferenceChanges.self) {
            hasChanges = true
        }
    }
}

struct DebugPreferenceChange: Decodable, Identifiable {
    let key: String
    let kind: String
    let old: String
    let new: String
    var id: String { key }
}

struct DebugPreferenceChanges: Decodable {
    let changes: [DebugPreferenceChange]
    /// When the snapshot was taken; none means since the app started.
    let snapshotAt: String?
}

/// What changed in the app's preferences since a snapshot, each change with Undo.
struct DebugPreferenceChangesView: View {
    @State var listing: DebugPreferenceChanges? = nil
    @State var status = ""

    var body: some View {
        List {
            Section {
                Text(verbatim: listing?.snapshotAt.map { "Since the snapshot at \($0)" } ?? "Since the app started")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                Button("Take a new snapshot") {
                    status = DebugSwiftRuntime.perform(featureID: "preferences", actionID: "snapshot_preferences")
                    load()
                }
                if !status.isEmpty {
                    Text(verbatim: status).font(.caption)
                }
            }
            Section("Changes") {
                if listing?.changes.isEmpty ?? true {
                    Text(verbatim: "No changes.").foregroundColor(Color.secondary)
                }
                ForEach(listing?.changes ?? []) { change in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(verbatim: change.key)
                            Spacer()
                            Text(verbatim: change.kind).font(.caption).foregroundColor(Color.secondary)
                        }
                        Text(verbatim: "\(change.old.isEmpty ? "—" : change.old) → \(change.new.isEmpty ? "—" : change.new)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Color.secondary)
                            .lineLimit(3)
                        Button("Undo") {
                            status = DebugSwiftRuntime.perform(featureID: "preferences", actionID: "undo_preference_change", value: change.key)
                            load()
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Changes")
        .onAppear { load() }
    }

    func load() {
        if case let .success(value) = DebugResourceClient.fetch("prefs.diff", as: DebugPreferenceChanges.self) {
            listing = value
        }
    }
}

struct DebugPreferenceRow: View {
    let value: DebugPreferenceValue

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: value.key)
                Spacer()
                Text(verbatim: value.type)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
            Text(verbatim: value.value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(Color.secondary)
                .lineLimit(2)
        }
    }
}

/// Edits one value, or adds a new one when `key` starts empty. The type of an existing value is kept.
struct DebugPreferenceEditView: View {
    let store: String
    @State var key: String
    let type: String
    @State var value: String
    @State var status = ""
    @Environment(\.dismiss) var dismiss

    init(store: String, key: String, type: String, value: String) {
        self.store = store
        self.type = type
        _key = State(initialValue: key)
        _value = State(initialValue: value)
        isNew = key.isEmpty
    }

    let isNew: Bool

    var body: some View {
        Form {
            Section("Store") {
                Text(verbatim: store)
            }
            Section("Key") {
                if isNew {
                    TextField("key", text: $key)
                } else {
                    Text(verbatim: key)
                }
            }
            Section("Value (\(type))") {
                TextField("value", text: $value)
            }
            Section {
                Button("Save") { save() }
                if !isNew {
                    Button("Delete", role: .destructive) { delete() }
                }
            }
            if !status.isEmpty {
                Section("Status") {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle(Text(verbatim: isNew ? "New value" : key))
    }

    /// The preference actions take JSON, so a key with "=" or "|" stays whole.
    static func payload(store: String, key: String, value: String?) -> String {
        var object = ["store": store, "key": key]
        if let value { object["value"] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func save() {
        // An existing key is saved exactly as stored; only a newly typed one is trimmed.
        let name = isNew ? key.trimmingCharacters(in: .whitespaces) : key
        guard !name.isEmpty else {
            status = "Enter a key."
            return
        }
        status = DebugSwiftRuntime.perform(
            featureID: "preferences",
            actionID: "set_preference",
            value: Self.payload(store: store, key: name, value: value),
        )
    }

    func delete() {
        status = DebugSwiftRuntime.perform(
            featureID: "preferences",
            actionID: "delete_preference",
            value: Self.payload(store: store, key: key, value: nil),
        )
        dismiss()
    }
}
