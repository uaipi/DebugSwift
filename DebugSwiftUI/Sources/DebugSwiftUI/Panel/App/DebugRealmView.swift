import SwiftUI

struct DebugRealmProvider: Decodable {
    let name: String
    let snapshot: String
}

struct DebugRealmState: Decodable {
    let providers: [DebugRealmProvider]
}

/// Realm schemas and data the host app registered. Realm lives on the JVM, so the host describes what
/// to show; without a registration there is nothing to read.
struct DebugRealmView: View {
    @State var providers: [DebugRealmProvider] = []
    @State var failure = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if providers.isEmpty && failure.isEmpty {
                Section {
                    Text(verbatim: "No Realm database is registered.")
                        .foregroundColor(Color.secondary)
                    Text(verbatim: "Register one from Kotlin with DebugSwiftRealmRegistry.register(name) { ... }, returning the schema or rows to show.")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(Color.secondary)
                }
            }
            if !providers.isEmpty {
                Section("Registered databases") {
                    ForEach(0..<providers.count, id: \.self) { index in
                        NavigationLink {
                            DebugTextDetailView(title: providers[index].name, text: providers[index].snapshot)
                        } label: {
                            Text(verbatim: providers[index].name)
                        }
                    }
                }
            }
            Section {
                Button("Refresh") { load() }
            }
        }
        .navigationTitle("Realm Browser")
        .onAppear { load() }
    }

    func load() {
        switch DebugResourceClient.fetch("app.realm", as: DebugRealmState.self) {
        case let .success(value):
            providers = value.providers
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
