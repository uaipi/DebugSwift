import SwiftUI

/// The last position the app reported, and a mock position for the GPS and network providers.
struct DebugLocationView: View {
    @State var current = ""
    @State var latitude = ""
    @State var longitude = ""
    @State var isMocking = false
    @State var status = ""

    var body: some View {
        Form {
            Section("Last reported location") {
                Text(verbatim: current)
                    .font(.system(.footnote, design: .monospaced))
            }
            Section("Mock location") {
                TextField("Latitude, for example -23.5505", text: $latitude)
                TextField("Longitude, for example -46.6333", text: $longitude)
                Button("Set location") { set() }
                if isMocking {
                    Button("Stop mocking", role: .destructive) { stop() }
                }
            }
            if !status.isEmpty {
                Section("Status") {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle("Location")
        .onAppear { refresh() }
    }

    func refresh() {
        current = DebugSwiftAndroidRuntime.snapshot(featureID: "location")
        if case let .success(reply) = DebugResourceClient.fetch("app.location.state", as: DebugActionReply.self) {
            isMocking = reply.mocking ?? false
        }
    }

    func set() {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespaces)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespaces))
        else {
            status = "Enter the latitude and longitude as numbers."
            return
        }
        report(DebugResourceClient.fetch(
            "app.location.mock",
            ["latitude": String(lat), "longitude": String(lon)],
            as: DebugActionReply.self,
        ))
    }

    func stop() {
        report(DebugResourceClient.fetch("app.location.stop", as: DebugActionReply.self))
    }

    func report(_ result: Result<DebugActionReply, DebugResourceFailure>) {
        switch result {
        case let .success(reply):
            status = reply.message ?? ""
            isMocking = reply.mocking ?? isMocking
        case let .failure(error):
            status = error.message
        }
        refresh()
    }
}
