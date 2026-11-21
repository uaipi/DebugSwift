//
//  SharedPanelResources.swift
//  DebugSwift
//

import Foundation

/// The Resources area of the shared panel on iOS: the app's files, its UserDefaults and HTTP
/// cookies, in the shapes the Android runtime returns its files, SharedPreferences and cookies.
@MainActor
final class SharedPanelResources {
    static let shared = SharedPanelResources()

    private static let previewLimit = 1_000_000
    private static let previewCharacters = 200_000
    /// The panel's own keys (the simulated location) are not the app's preferences.
    private static let hiddenDefaults: Set<String> = [
        LocationToolkit.Constants.simulatedLatitude, LocationToolkit.Constants.simulatedLongitude
    ]
    private static let standardStore = "Standard"

    private let defaultsDiff = UserDefaultsDiffAdapter.shared
    private var snapshotAt: Date?
    /// The file the preview chose, for Share.
    private var selectedFile: String?

    private init() {}

    // MARK: - Operations

    func resource(_ operation: String, _ arguments: [String: String]) -> [String: Any]? {
        switch operation {
        case "files.list": return listFiles(arguments["path"] ?? "")
        case "files.read": return readFile(arguments["path"] ?? "")
        case "files.delete": return deleteFile(arguments["path"] ?? "")
        case "prefs.list": return preferences()
        case "prefs.diff": return preferenceChanges()
        case "cookies.list": return cookies()
        case "cookies.delete": return deleteCookie(host: arguments["host"] ?? "", name: arguments["name"] ?? "")
        case "cookies.clear":
            let all = HTTPCookieStorage.shared.cookies ?? []
            all.forEach(HTTPCookieStorage.shared.deleteCookie)
            return ["message": all.count == 1 ? "Deleted 1 cookie." : "Deleted \(all.count) cookies."]
        default: return nil
        }
    }

    func perform(featureID: String, actionID: String, value: String) -> String? {
        switch (featureID, actionID) {
        case ("files", "browse_files"):
            selectedFile = value
            return "Selected \(value)."
        case ("files", "export"):
            guard let path = selectedFile, let url = resolve(path), FileManager.default.fileExists(atPath: url.path) else {
                return "Choose a file first."
            }
            FileSharingManager.share(url)
            return "Sharing \(url.lastPathComponent)."
        case ("preferences", "set_preference"), ("persistent_data", "set_preference"), ("user_defaults", "set_preference"):
            return setPreference(value)
        case ("preferences", "delete_preference"), ("persistent_data", "delete_preference"), ("user_defaults", "delete_preference"):
            return deletePreference(value)
        case ("preferences", "snapshot_preferences"):
            defaultsDiff.snapshotNow()
            snapshotAt = Date()
            return "Snapshot taken."
        case ("preferences", "undo_preference_change"):
            guard let change = defaultsDiff.changes().first(where: { $0.key == value }) else { return "No change to \(value)." }
            defaultsDiff.undo(change)
            return "Restored \(value)."
        default:
            return nil
        }
    }

    // MARK: - Files

    /// The sandbox folders the browser starts from, then each App Group container set with
    /// `DebugSwift.Resources.shared.configureAppGroups(_:)`, named by its identifier.
    private func roots() -> [(name: String, url: URL)] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let sandbox = ["Documents", "Library", "tmp"].map { (name: $0, url: home.appendingPathComponent($0)) }
        let groups = DebugSwift.Resources.shared.getAccessibleAppGroups()
            .filter { group in !group.identifier.isEmpty && !group.identifier.contains("/") && !sandbox.contains { $0.name == group.identifier } }
            .map { (name: $0.identifier, url: $0.url) }
        return (sandbox + groups).map { (name: $0.name, url: $0.url.standardizedFileURL) }
    }

    /// A path inside one of the roots, or nil for anything outside them.
    ///
    /// The check uses the location with symbolic links resolved, so a link inside a root can't
    /// reach outside it; a link to somewhere else in the same root is followed. The URL returned
    /// keeps the link itself, so deleting a link removes the link, not what it points to.
    private func resolve(_ path: String) -> URL? {
        let parts = path.split(separator: "/").map(String.init)
        guard let name = parts.first, let base = roots().first(where: { $0.name == name })?.url else { return nil }
        let target = parts.dropFirst().reduce(base) { $0.appendingPathComponent($1) }.standardizedFileURL
        let resolvedBase = base.resolvingSymlinksInPath().path
        let resolvedTarget = target.resolvingSymlinksInPath().path
        guard resolvedTarget == resolvedBase || resolvedTarget.hasPrefix(resolvedBase + "/") else { return nil }
        return target
    }

    private func listFiles(_ path: String) -> [String: Any] {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmed.isEmpty {
            return [
                "path": "",
                "entries": roots().map { ["name": $0.name, "isDirectory": true, "size": 0, "modified": 0] }
            ]
        }
        guard let directory = resolve(trimmed) else {
            return ["error": "The file browser is limited to the app's Documents, Library and tmp folders and its configured App Groups."]
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else {
            return ["error": "Not a directory: \(trimmed)"]
        }
        let entries: [[String: Any]] = items.compactMap { url in
            // A link is described by what it points to, so a link to a folder opens as a folder.
            guard let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: Set(keys))
                ?? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let isDirectory = values.isDirectory ?? false
            return [
                "name": url.lastPathComponent,
                "isDirectory": isDirectory,
                "size": isDirectory ? 0 : (values.fileSize ?? 0),
                "modified": Int((values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000)
            ]
        }
        .sorted { lhs, rhs in
            let leftDirectory = lhs["isDirectory"] as? Bool ?? false
            let rightDirectory = rhs["isDirectory"] as? Bool ?? false
            if leftDirectory != rightDirectory { return leftDirectory }
            return (lhs["name"] as? String ?? "").lowercased() < (rhs["name"] as? String ?? "").lowercased()
        }
        // Every entry: the screen's list draws rows as they scroll into view.
        return ["path": trimmed, "entries": entries]
    }

    private func readFile(_ path: String) -> [String: Any] {
        // `resolve` already checked that a link stays inside its root; read what it points to.
        guard let url = resolve(path)?.resolvingSymlinksInPath(),
              let size = (try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]))
                .flatMap({ $0.isRegularFile == true ? $0.fileSize : nil }) else {
            return ["error": "File not found: \(path)"]
        }
        var result: [String: Any] = ["path": path, "size": size]
        guard size <= Self.previewLimit else {
            result["isText"] = false
            result["note"] = "Preview is limited to 1 MB."
            return result
        }
        guard let data = try? Data(contentsOf: url) else { return ["error": "The file could not be read."] }
        if data.prefix(8_000).contains(0) {
            result["isText"] = false
            result["note"] = "Binary file, no text preview."
            return result
        }
        result["isText"] = true
        result["text"] = String(String(decoding: data, as: UTF8.self).prefix(Self.previewCharacters))
        return result
    }

    private func deleteFile(_ path: String) -> [String: Any] {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = resolve(trimmed) else { return ["error": "Path is outside the app's private storage."] }
        // Compare the resolved URL: "tmp/." or "Documents/child/.." name a root too.
        let rootPaths = roots().map(\.url.path)
        guard !rootPaths.contains(url.path) else { return ["error": "Cannot delete a storage root."] }
        guard FileManager.default.fileExists(atPath: url.path) else { return ["error": "Path not found: \(path)"] }
        do {
            try FileManager.default.removeItem(at: url)
            return ["ok": true, "message": "Deleted \(url.lastPathComponent)."]
        } catch {
            return ["ok": false, "message": "Could not delete \(url.lastPathComponent): \(error.localizedDescription)"]
        }
    }

    // MARK: - UserDefaults

    private static func typeName(_ value: Any) -> String {
        // A stored 0 or 1 bridges to Bool too: only a CFBoolean is a Boolean.
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return CFNumberIsFloatType(number) ? "Double" : "Int"
        }
        return switch value {
        case is Bool: "Boolean"
        case is Date: "Date"
        case is Data: "Data"
        case is [Any]: "Array"
        case is [String: Any]: "Dictionary"
        default: "String"
        }
    }

    private func preferences() -> [String: Any] {
        let defaults = UserDefaults.standard.dictionaryRepresentation()
        let values: [[String: Any]] = defaults.keys.sorted().filter { !Self.hiddenDefaults.contains($0) }.map { key in
            let value = defaults[key] ?? ""
            let type = Self.typeName(value)
            // A Boolean prints as 1 or 0; show true or false, which is what saving accepts.
            let text = type == "Boolean" ? String((value as? Bool) ?? false) : "\(value)"
            return ["key": key, "type": type, "value": text]
        }
        return ["stores": [["name": Self.standardStore, "values": values]]]
    }

    /// "store|key=value". The value keeps the type the key already has (String for a new key).
    /// The shared editor's JSON, `{"store", "key", "value"}`, so a key may hold "=" or "|". Plain
    /// `store|key=value` text still works for keys without them.
    static func preferencePayload(_ value: String) -> (key: String, value: String?)? {
        guard value.hasPrefix("{") else { return nil }
        guard let object = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any],
              let key = object["key"] as? String else { return ("", nil) }
        return (key, object["value"] as? String)
    }

    private func setPreference(_ value: String) -> String {
        let key: String
        let text: String
        if let payload = Self.preferencePayload(value) {
            guard !payload.key.isEmpty, let entered = payload.value else { return "Enter a key and a value." }
            (key, text) = (payload.key, entered)
        } else {
            let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return "Enter store|key=value." }
            let pair = parts[1].split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard pair.count == 2, !pair[0].isEmpty else { return "Enter key=value." }
            (key, text) = (pair[0], pair[1])
        }
        let defaults = UserDefaults.standard
        switch defaults.object(forKey: key).map(Self.typeName) {
        case "Boolean":
            guard let flag = Bool(text.lowercased()) else { return "\(key) is a Boolean: enter true or false." }
            defaults.set(flag, forKey: key)
        case "Int":
            guard let number = Int(text) else { return "\(key) is a whole number." }
            defaults.set(number, forKey: key)
        case "Double":
            guard let number = Double(text) else { return "\(key) is a number." }
            defaults.set(number, forKey: key)
        case "Date", "Data", "Array", "Dictionary":
            return "\(key) holds a value this screen can't edit as text."
        default:
            defaults.set(text, forKey: key)
        }
        return "Saved \(key)."
    }

    /// "store|key".
    private func deletePreference(_ value: String) -> String {
        let key: String
        if let payload = Self.preferencePayload(value) {
            key = payload.key
        } else {
            let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
            key = parts.count == 2 ? parts[1] : ""
        }
        guard !key.isEmpty else { return "Enter store|key." }
        UserDefaults.standard.removeObject(forKey: key)
        return "Deleted \(key)."
    }

    private func preferenceChanges() -> [String: Any] {
        var result: [String: Any] = [
            "changes": defaultsDiff.changes().filter { !Self.hiddenDefaults.contains($0.key) }.map { change in
                [
                    "key": change.key,
                    "kind": "\(change.kind)",
                    "old": change.oldValue.map { "\($0)" } ?? "",
                    "new": change.newValue.map { "\($0)" } ?? ""
                ]
            }
        ]
        if let snapshotAt { result["snapshotAt"] = SharedPanelData.timeFormatter.string(from: snapshotAt) }
        return result
    }

    // MARK: - Cookies

    /// Every cookie with this name on this domain, whatever its path.
    private func deleteCookie(host: String, name: String) -> [String: Any] {
        let matches = (HTTPCookieStorage.shared.cookies ?? []).filter { $0.domain == host && $0.name == name }
        guard !matches.isEmpty else { return ["error": "No cookie \(name) for \(host)."] }
        matches.forEach(HTTPCookieStorage.shared.deleteCookie)
        return ["message": "Deleted \(name)."]
    }

    private func cookies() -> [String: Any] {
        let all = HTTPCookieStorage.shared.cookies ?? []
        let hosts = Dictionary(grouping: all, by: \.domain).keys.sorted().map { host in
            [
                "host": host,
                "cookies": all.filter { $0.domain == host }.sorted { $0.name < $1.name }.map { ["name": $0.name, "value": $0.value] }
            ] as [String: Any]
        }
        return ["hosts": hosts]
    }
}
