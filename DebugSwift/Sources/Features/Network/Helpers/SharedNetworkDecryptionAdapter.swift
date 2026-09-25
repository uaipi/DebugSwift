//
// SharedNetworkDecryptionAdapter.swift
// DebugSwift
//

import Foundation

public extension DebugSwift.Network {
    /// Settings exposed to the shared SwiftUI response decryption panel.
    @MainActor
    func sharedDecryptionSettingsJSON() -> String {
        let snapshot: [String: Any] = [
            "isEnabled": isDecryptionEnabled,
            "patterns": registeredDecryptionKeyPatterns
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"isEnabled\":false,\"patterns\":[]}"
        }
        return json
    }

    /// Performs native key and toggle actions requested by the shared SwiftUI panel.
    @MainActor
    func performSharedDecryptionAction(actionID: String, value: String = "") -> String {
        switch actionID {
        case "set_enabled":
            guard value == "true" || value == "false" else {
                return "Set response decryption to true or false."
            }
            setDecryptionEnabled(value == "true")
            return "Response decryption \(value == "true" ? "enabled" : "disabled"). New captured responses use this setting."
        case "register_key":
            guard let separator = value.lastIndex(of: ":") else {
                return "Enter a URL regex followed by ':' and a base64 AES key."
            }
            let pattern = String(value[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let encodedKey = String(value[value.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty,
                  (try? NSRegularExpression(pattern: pattern)) != nil,
                  let key = Data(base64Encoded: encodedKey, options: .ignoreUnknownCharacters),
                  [16, 24, 32].contains(key.count) else {
                return "Enter a valid URL regex and a base64 AES key containing 16, 24, or 32 bytes."
            }
            registerDecryptionKey(for: pattern, key: key)
            return "AES-GCM key registered for URL regex '\(pattern)'."
        case "clear_keys":
            clearDecryptionKeys()
            return "Response decryption keys cleared from this process."
        default:
            return "Unknown response decryption action: \(actionID)."
        }
    }
}
