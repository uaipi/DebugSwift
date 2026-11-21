import SwiftUI

/// Cookies the WebViews of the host app hold, grouped by domain.
/// A cookie with its host, so the same cookie name on two domains stays distinct in the list.
struct DebugCookieItem: Identifiable {
    let host: String
    let cookie: DebugCookie
    var id: String { host + "|" + cookie.name }
}

struct DebugCookiesView: View {
    @State var hosts: [DebugCookieHost] = []
    @State var failure = ""
    @State var status = ""
    @State var confirmsClear = false

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if hosts.isEmpty && failure.isEmpty {
                Text(verbatim: "No cookies for the domains the app's WebViews reported.")
                    .foregroundColor(Color.secondary)
            }
            ForEach(hosts) { host in
                Section {
                    ForEach(host.cookies.map { DebugCookieItem(host: host.host, cookie: $0) }) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: item.cookie.name)
                                Text(verbatim: item.cookie.value)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundColor(Color.secondary)
                                    .lineLimit(3)
                            }
                            Spacer()
                            Button("Delete", role: .destructive) { delete(item) }
                                .buttonStyle(.borderless)
                        }
                    }
                } header: {
                    Text(verbatim: host.host)
                }
            }
            if !hosts.isEmpty {
                Section {
                    Button("Delete all cookies", role: .destructive) { confirmsClear = true }
                    if !status.isEmpty {
                        Text(verbatim: status).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("HTTP Cookies")
        .onAppear { load() }
        .alert("Delete all cookies?", isPresented: $confirmsClear) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { clear() }
        }
    }

    func delete(_ item: DebugCookieItem) {
        act("cookies.delete", ["host": item.host, "name": item.cookie.name])
    }

    func clear() {
        act("cookies.clear", [:])
    }

    func act(_ operation: String, _ arguments: [String: String]) {
        switch DebugResourceClient.fetch(operation, arguments, as: DebugActionReply.self) {
        case let .success(reply): status = reply.message ?? ""
        case let .failure(error): status = error.message
        }
        load()
    }

    func load() {
        switch DebugResourceClient.fetch("cookies.list", as: DebugCookieListing.self) {
        case let .success(value):
            hosts = value.hosts
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
