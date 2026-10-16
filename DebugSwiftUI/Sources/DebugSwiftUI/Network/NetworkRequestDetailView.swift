import DebugSwiftCore
import SwiftUI

struct NetworkRequestDetailView: View {
    let request: NetworkRecordSummary

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") { Text(verbatim: request.statusTitle).foregroundStyle(request.status.color) }
                LabeledContent("Duration") { Text(verbatim: "\(request.durationMilliseconds) ms") }
                Text(verbatim: "\(request.method) \(request.url)").font(.caption)
                ShareLink("Share as cURL", item: request.curlCommand)
                Button("Copy cURL") { DebugClipboard.copy(request.curlCommand) }
            }
            if let failure = request.failureDescription {
                Section("Error") { Text(verbatim: failure).foregroundStyle(.red) }
            }
            NetworkPayloadSection(title: "Request", headers: request.requestHeaders, bodyText: request.requestBody)
            if request.failureDescription == nil {
                NetworkPayloadSection(title: "Response", headers: request.responseHeaders, bodyText: request.responseBody)
            }
        }
        .navigationTitle(Text(verbatim: "\(request.method) \(request.statusTitle)"))
    }
}

struct NetworkPayloadSection: View {
    let title: String
    let headers: [NetworkRecordSummary.Header]
    let bodyText: String?
    @State var isExpanded = false

    var body: some View {
        Section(title) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack {
                    Text(verbatim: "Headers (\(headers.count))").font(.headline)
                    Spacer()
                    Text(verbatim: isExpanded ? "−" : "+")
                }
            }
            .buttonStyle(.plain)
            if isExpanded {
                ForEach(headers) { header in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: header.name).font(.caption)
                        Text(verbatim: header.value)
                    }
                }
            }
            if let bodyText {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Body").font(.caption)
                    Text(verbatim: bodyText)
                }
                Button("Copy body") { DebugClipboard.copy(bodyText) }
            }
        }
    }
}
