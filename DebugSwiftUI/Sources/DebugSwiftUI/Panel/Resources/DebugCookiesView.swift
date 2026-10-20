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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: item.cookie.name)
                            Text(verbatim: item.cookie.value)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundColor(Color.secondary)
                                .lineLimit(3)
                        }
                    }
                } header: {
                    Text(verbatim: host.host)
                }
            }
        }
        .navigationTitle("HTTP Cookies")
        .onAppear { load() }
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
