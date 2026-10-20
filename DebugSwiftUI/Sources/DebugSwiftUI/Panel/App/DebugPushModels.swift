import Foundation

struct DebugPushTemplate: Decodable, Identifiable {
    let name: String
    let title: String
    let body: String
    let subtitle: String?
    let isDefault: Bool

    /// Prefixed so it cannot match a history entry in the same list.
    var id: String { "template-" + name }
}

struct DebugPushScenario: Identifiable {
    let id: String
    let title: String
}

struct DebugPushRecord: Decodable, Identifiable {
    let id: String
    let title: String
    let body: String
    let subtitle: String?
    let badge: Int?
    let sound: String?
    let status: String
    let trigger: String
    let scheduledMs: Double
    let deliveredMs: Double?
    let interaction: String?
    let userInfo: [String: String]

    var scheduled: Date { Date(timeIntervalSince1970: scheduledMs / 1000) }
}

struct DebugPushState: Decodable {
    let enabled: Bool
    let permission: String
    let channel: String
    let showInForeground: Bool
    let playSound: Bool
    let showBadge: Bool
    let autoInteraction: Bool
    let interactionDelay: Int
    let simulateRealPush: Bool
    let maxHistory: Int
    let templates: [DebugPushTemplate]
    let history: [DebugPushRecord]
}

/// Runs one of the push simulator's actions and answers its message.
@MainActor
enum DebugPush {
    static func act(_ actionID: String, _ value: String = "") -> String {
        DebugSwiftAndroidRuntime.perform(featureID: "push_simulator", actionID: actionID, value: value)
    }

    static func setOption(_ key: String, _ value: String) -> String {
        act("set_notification_config", "\(key)=\(value)")
    }
}
