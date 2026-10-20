import SwiftUI

/// One template: send it now or after a delay, or remove it (the built-in ones stay).
struct DebugPushTemplateView: View {
    let template: DebugPushTemplate
    @State var delay = "0"
    @State var status = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Form {
            Section("Template") {
                LabeledContent("Name") { Text(verbatim: template.name) }
                LabeledContent("Title") { Text(verbatim: template.title).multilineTextAlignment(.trailing) }
                LabeledContent("Message") { Text(verbatim: template.body).multilineTextAlignment(.trailing) }
                if let subtitle = template.subtitle {
                    LabeledContent("Subtitle") { Text(verbatim: subtitle) }
                }
            }
            Section("Send") {
                TextField("Delay in seconds", text: $delay)
                Button("Send now") {
                    status = DebugPush.act("simulate_template", "\(template.name)|\(delay)")
                }
            }
            if !template.isDefault {
                Section {
                    Button("Remove this template", role: .destructive) {
                        status = DebugPush.act("remove_template", template.name)
                        dismiss()
                    }
                }
            }
            if !status.isEmpty {
                Section("Status") {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle(Text(verbatim: template.name))
    }
}

struct DebugPushNewTemplateView: View {
    @State var name = ""
    @State var title = ""
    @State var message = ""
    @State var status = ""

    var body: some View {
        Form {
            Section("New template") {
                TextField("Name", text: $name)
                TextField("Title", text: $title)
                TextField("Message", text: $message)
            }
            Section {
                Button("Save") {
                    let clean = { (text: String) in text.replacingOccurrences(of: "|", with: "/") }
                    status = DebugPush.act("add_template", "\(clean(name))|\(clean(title))|\(clean(message))")
                }
            }
            if !status.isEmpty {
                Section("Status") {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle("Add a template")
    }
}
