import SwiftUI

/// Simulates local notifications: send one, run a scripted flow, use templates, and see how each was
/// delivered. It posts real Android notifications, so it needs the notification permission.
struct DebugPushNotificationsView: View {
    @State var state: DebugPushState? = nil
    @State var failure = ""
    @State var status = ""

    let scenarios = [
        DebugPushScenario(id: "scenario-messageflow", title: "Message flow"),
        DebugPushScenario(id: "scenario-newsupdates", title: "News updates"),
        DebugPushScenario(id: "scenario-marketingcampaign", title: "Marketing campaign"),
        DebugPushScenario(id: "scenario-systemalerts", title: "System alerts"),
    ]

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let state {
                Section {
                    Toggle("Simulate push notifications", isOn: Binding(
                        get: { state.enabled },
                        set: { _ in toggle() },
                    ))
                    LabeledContent("Permission") { Text(verbatim: state.permission) }
                    if state.permission != "Allowed" {
                        Button("Open notification settings") {
                            status = DebugPush.act("open_notification_settings")
                        }
                    }
                }
                Section("Send") {
                    NavigationLink {
                        DebugPushSendView()
                    } label: {
                        Text(verbatim: "Send a notification")
                    }
                    ForEach(scenarios) { scenario in
                        Button("Run scenario: " + scenario.title) {
                            status = DebugPush.act("run_scenario", scenario.id.replacingOccurrences(of: "scenario-", with: ""))
                            load()
                        }
                    }
                }
                Section("Templates") {
                    ForEach(state.templates) { template in
                        NavigationLink {
                            DebugPushTemplateView(template: template)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: template.name)
                                Text(verbatim: template.title)
                                    .font(.caption)
                                    .foregroundColor(Color.secondary)
                            }
                        }
                    }
                    NavigationLink {
                        DebugPushNewTemplateView()
                    } label: {
                        Text(verbatim: "Add a template").foregroundColor(Color.accentColor)
                    }
                }
                Section("Behavior") {
                    optionToggle("Show in foreground", "showInForeground", state.showInForeground)
                    optionToggle("Play sound", "playSound", state.playSound)
                    optionToggle("Show badge", "showBadge", state.showBadge)
                    optionToggle("Interact automatically", "autoInteraction", state.autoInteraction)
                    optionToggle("Behave like a real push", "simulateRealPush", state.simulateRealPush)
                    Stepper(
                        "Auto interaction after \(state.interactionDelay) s",
                        onIncrement: { change("interactionDelay", state.interactionDelay + 1) },
                        onDecrement: { change("interactionDelay", max(0, state.interactionDelay - 1)) },
                    )
                    Stepper(
                        "Keep \(state.maxHistory) in history",
                        onIncrement: { change("maxHistoryCount", min(500, state.maxHistory + 10)) },
                        onDecrement: { change("maxHistoryCount", max(10, state.maxHistory - 10)) },
                    )
                }
                Section("History (\(state.history.count))") {
                    if state.history.isEmpty {
                        Text(verbatim: "No simulated notifications yet.")
                            .foregroundColor(Color.secondary)
                    }
                    ForEach(state.history) { record in
                        NavigationLink {
                            DebugPushRecordView(record: record)
                        } label: {
                            DebugPushRecordRow(record: record)
                        }
                    }
                    if !state.history.isEmpty {
                        Button("Clear history", role: .destructive) {
                            status = DebugPush.act("clear_push_history", "CLEAR")
                            load()
                        }
                    }
                }
            }
            if !status.isEmpty {
                Section("Status") {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle("Push Notifications")
        .task {
            while !Task.isCancelled {
                load()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func optionToggle(_ title: String, _ key: String, _ value: Bool) -> some View {
        Toggle(title, isOn: Binding(
            get: { value },
            set: { on in
                status = DebugPush.setOption(key, on ? "true" : "false")
                load()
            },
        ))
    }

    func change(_ key: String, _ value: Int) {
        status = DebugPush.setOption(key, String(value))
        load()
    }

    func toggle() {
        status = DebugPush.act("toggle")
        load()
    }

    func load() {
        switch DebugResourceClient.fetch("app.push.state", as: DebugPushState.self) {
        case let .success(value):
            state = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}

struct DebugPushRecordRow: View {
    let record: DebugPushRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: record.title)
                Spacer()
                Text(verbatim: record.status)
                    .font(.caption)
                    .foregroundColor(record.status == "Interacted" ? Color.green : Color.secondary)
            }
            Text(verbatim: record.body)
                .font(.caption)
                .foregroundColor(Color.secondary)
                .lineLimit(1)
        }
    }
}
