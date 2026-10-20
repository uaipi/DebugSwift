import SwiftUI

struct NetworkInspectorView: View {
    @State var model: NetworkInspectorModel

    var body: some View {
        Group {
            if !model.hasLoaded {
                ProgressView()
            } else if model.requests.isEmpty {
                VStack {
                    Text(verbatim: "No requests yet").font(.headline)
                    Text(verbatim: "Use the app and requests appear here.").font(.caption)
                }
            } else {
                List {
                    Section {
                        ForEach(model.filteredRequests) { request in
                            NavigationLink {
                                NetworkRequestDetailView(request: request)
                            } label: {
                                NetworkRequestRow(request: request)
                            }
                        }
                    } footer: {
                        Text(verbatim: "Requests sent by this build, newest first. Credentials are masked.")
                    }
                }
                .searchable(
                    text: Binding(get: { model.query }, set: { model.query = $0 }),
                    prompt: Text(verbatim: "Search method, URL or status")
                )
            }
        }
        .navigationTitle("Network inspector")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") { model.clear() }.disabled(model.requests.isEmpty)
            }
        }
        .task { model.start() }
    }
}
