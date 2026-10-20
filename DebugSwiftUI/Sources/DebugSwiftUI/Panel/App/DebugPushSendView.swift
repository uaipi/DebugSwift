import SwiftUI

/// Sends one notification now or after a delay.
struct DebugPushSendView: View {
    @State var title = "DebugSwift test"
    @State var message = "A notification from the debugger."
    @State var delay = "0"
    @State var status = ""

    var body: some View {
        Form {
            Section("Notification") {
                TextField("Title", text: $title)
                TextField("Message", text: $message)
                TextField("Delay in seconds", text: $delay)
            }
            Section {
                Button("Send") {
                    // The simulator splits its input on "|", so keep that character out of the text.
                    let clean = { (text: String) in text.replacingOccurrences(of: "|", with: "/") }
                    status = DebugPush.act("notify", "\(clean(title))|\(clean(message))|\(delay)")
                }
            }
            if !status.isEmpty {
                Section("Status") {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle("Send a notification")
    }
}
