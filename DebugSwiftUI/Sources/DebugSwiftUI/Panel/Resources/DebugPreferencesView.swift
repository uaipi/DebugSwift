import SwiftUI

/// Every preference store the app owns, with each value editable. `includesKeystore` adds the
/// Keystore aliases below the stores, for the combined persistent data screen.
struct DebugPreferencesView: View {
    let includesKeystore: Bool
    @State var stores: [DebugPreferenceStore] = []
    @State var failure = ""

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
                    ForEach(store.values) { value in
                        NavigationLink {
                            DebugPreferenceEditView(store: store.name, key: value.key, type: value.type, value: value.value)
                        } label: {
                            DebugPreferenceRow(value: value)
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
            if includesKeystore {
                Section {
                    NavigationLink {
                        DebugKeystoreView()
                    } label: {
                        Text(verbatim: "Keystore aliases")
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

    func save() {
        let name = key.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            status = "Enter a key."
            return
        }
        status = DebugSwiftAndroidRuntime.perform(
            featureID: "preferences",
            actionID: "set_preference",
            value: "\(store)|\(name)=\(value)",
        )
    }

    func delete() {
        status = DebugSwiftAndroidRuntime.perform(
            featureID: "preferences",
            actionID: "delete_preference",
            value: "\(store)|\(key)",
        )
        dismiss()
    }
}
