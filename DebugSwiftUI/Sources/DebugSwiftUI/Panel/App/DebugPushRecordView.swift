import SwiftUI

/// One entry of the push history, with the actions that make sense for it.
struct DebugPushRecordView: View {
    let record: DebugPushRecord
    @State var status = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        List {
            Section("Notification") {
                LabeledContent("Title") { Text(verbatim: record.title).multilineTextAlignment(.trailing) }
                LabeledContent("Message") { Text(verbatim: record.body).multilineTextAlignment(.trailing) }
                if let subtitle = record.subtitle {
                    LabeledContent("Subtitle") { Text(verbatim: subtitle) }
                }
                if let badge = record.badge {
                    LabeledContent("Badge") { Text(verbatim: "\(badge)") }
                }
                if let sound = record.sound {
                    LabeledContent("Sound") { Text(verbatim: sound) }
                }
            }
            Section("Delivery") {
                LabeledContent("Status") { Text(verbatim: record.status) }
                LabeledContent("Trigger") { Text(verbatim: record.trigger) }
                LabeledContent("Scheduled") { Text(verbatim: debugDateText(record.scheduled)) }
                if let deliveredMs = record.deliveredMs {
                    LabeledContent("Delivered") { Text(verbatim: debugDateText(Date(timeIntervalSince1970: deliveredMs / 1000))) }
                }
                if let interaction = record.interaction {
                    LabeledContent("Interaction") { Text(verbatim: interaction) }
                }
            }
            if !record.userInfo.isEmpty {
                Section("User info") {
                    ForEach(record.userInfo.keys.sorted(), id: \.self) { key in
                        LabeledContent(key) { Text(verbatim: record.userInfo[key] ?? "") }
                    }
                }
            }
            Section {
                Button("Mark as tapped") { status = DebugPush.act("interact_notification", record.id) }
                Button("Send it again") { status = DebugPush.act("resend_notification", record.id) }
                Button("Remove from history", role: .destructive) {
                    status = DebugPush.act("remove_notification", record.id)
                    dismiss()
                }
                if !status.isEmpty {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle(Text(verbatim: record.title))
    }
}
