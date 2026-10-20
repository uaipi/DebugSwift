import SwiftUI

/// Cookies the WebViews of the host app hold, grouped by domain.
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
                    ForEach(host.cookies) { cookie in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: cookie.name)
                            Text(verbatim: cookie.value)
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
