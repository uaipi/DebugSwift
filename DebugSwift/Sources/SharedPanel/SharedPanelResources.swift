//
//  SharedPanelResources.swift
//  DebugSwift
//

import Foundation
import SQLite3
import Security

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
        case "keystore.list": return keychainItems()
        case "db.list": return databases()
        case "db.tables": return tables(arguments["db"] ?? "")
        case "db.rows": return rows(arguments["db"] ?? "", table: arguments["table"] ?? "", offset: Int(arguments["offset"] ?? "") ?? 0)
        case "db.query": return query(arguments["db"] ?? "", sql: arguments["sql"] ?? "")
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
        case ("keychain", "set_keychain_item"):
            return setKeychainItem(value)
        case ("keychain", "delete_keychain_item"):
            return deleteKeychainItem(value)
        case ("database", "export_database"):
            guard let path = databasePath(value) else { return "No database named \(value)." }
            if Self.isRealm(path) {
                FileSharingManager.share(URL(fileURLWithPath: path))
                return "Sharing \(value)."
            }
            switch Self.sqliteSnapshot(of: path) {
            case let .success(url):
                // The copy is removed once the share sheet closes, shared or not.
                FileSharingManager.share(url) {
                    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                }
                return "Sharing \(value)."
            case let .failure(message):
                return message.text
            }
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

    // MARK: - Keychain

    /// The app's generic-password items, each named service/key so two services can share a key.
    private func keychainItems() -> [String: Any] {
        let items = Keychain.allKeys(.genericPassword)
            .map { (service: $0.0, key: $0.1) }
            .filter { !Self.hiddenDefaults.contains($0.key) }
        return [
            "editable": true,
            "aliases": items.sorted { ($0.service, $0.key) < ($1.service, $1.key) }.map { item -> [String: Any] in
                var entry: [String: Any] = ["alias": item.key, "service": item.service]
                // A value that isn't text is left out, so the editor can't save it back as a blank.
                if let value = Keychain(service: item.service)[string: item.key] { entry["value"] = value }
                return entry
            }
        ]
    }

    /// The editor's JSON, `{"service", "key", "value"}`, so any text fits in each field. A new item
    /// has no service and goes to the app's default one; an existing item keeps its service, even
    /// an empty one.
    private static func keychainPayload(_ value: String) -> (keychain: Keychain, key: String, value: String?)? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(value.utf8))) as? [String: Any],
              let key = object["key"] as? String, !key.isEmpty else { return nil }
        let keychain = (object["service"] as? String).map { Keychain(service: $0) } ?? Keychain()
        return (keychain, key, object["value"] as? String)
    }

    private func setKeychainItem(_ value: String) -> String {
        guard let item = Self.keychainPayload(value), let text = item.value else { return "Enter a key and a value." }
        do {
            try item.keychain.set(text, key: item.key)
            return "Saved \(item.key)."
        } catch {
            return "Could not save \(item.key): \(error.localizedDescription)"
        }
    }

    private func deleteKeychainItem(_ value: String) -> String {
        guard let item = Self.keychainPayload(value) else { return "Enter a key." }
        do {
            try item.keychain.remove(item.key)
            return "Deleted \(item.key)."
        } catch {
            return "Could not delete \(item.key): \(error.localizedDescription)"
        }
    }

    // MARK: - Databases

    /// SQLite files in the sandbox, named by their path under the app's home folder. Includes
    /// Core Data stores and SwiftData's `.store` files, which are SQLite too.
    private func databaseFiles() -> [(name: String, path: String, size: Int)] {
        var files = DatabaseFileManager.shared.discoverDatabaseFiles()
            .map { ($0.path, Int($0.size)) }
        let support = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        if let stores = FileManager.default.enumerator(at: support, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in stores where url.pathExtension == "store" && Self.isSQLite(url) {
                files.append((url.path, (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
            }
        }
        // Each name leads back to one file: the path under the app's home folder, or under an App
        // Group container after the group's identifier, or else the full path.
        let home = NSHomeDirectory() + "/"
        let groups = DebugSwift.Resources.shared.getAccessibleAppGroups()
            .map { (identifier: $0.identifier, prefix: $0.url.standardizedFileURL.path + "/") }
        var seen = Set<String>()
        return files.compactMap { path, size in
            guard seen.insert(path).inserted else { return nil }
            let name: String
            if path.hasPrefix(home) {
                name = String(path.dropFirst(home.count))
            } else if let group = groups.first(where: { path.hasPrefix($0.prefix) }) {
                name = group.identifier + "/" + path.dropFirst(group.prefix.count)
            } else {
                name = path
            }
            return (name, path, size)
        }.sorted { $0.name < $1.name }
    }

    struct ExportFailure: Error { let text: String }

    /// A standalone copy of a SQLite database, written by `VACUUM INTO` so changes still in the
    /// `-wal` file are part of it. It keeps the database's file name.
    static func sqliteSnapshot(of path: String) -> Result<URL, ExportFailure> {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("debugswift-export-\(UUID().uuidString)")
        let target = folder.appendingPathComponent((path as NSString).lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return .failure(ExportFailure(text: "Could not prepare the export: \(error.localizedDescription)"))
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return .failure(ExportFailure(text: "Could not open the database to export it."))
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "VACUUM INTO ?", -1, &statement, nil) == SQLITE_OK else {
            return .failure(ExportFailure(text: "Could not export: \(String(cString: sqlite3_errmsg(db)))"))
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, target.path, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            return .failure(ExportFailure(text: "Could not export: \(String(cString: sqlite3_errmsg(db)))"))
        }
        return .success(target)
    }

    private static func isSQLite(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 16)) == Data("SQLite format 3\0".utf8)
    }

    /// Each name's file from the last listing, so opening a table or a page doesn't search the
    /// sandbox again.
    private var databasePaths: [String: String] = [:]

    /// The file a database name stands for: from the last listing while that file is still there,
    /// otherwise found again.
    private func databasePath(_ name: String) -> String? {
        if let path = databasePaths[name], FileManager.default.fileExists(atPath: path) { return path }
        let files = databaseFiles()
        databasePaths = Dictionary(files.map { ($0.name, $0.path) }, uniquingKeysWith: { first, _ in first })
        return databasePaths[name]
    }

    /// Realm files show their header as one informational table, as the iOS browser did.
    private static func isRealm(_ path: String) -> Bool {
        path.lowercased().hasSuffix(".realm")
    }

    private func databases() -> [String: Any] {
        let files = databaseFiles()
        databasePaths = Dictionary(files.map { ($0.name, $0.path) }, uniquingKeysWith: { first, _ in first })
        return ["databases": files.map { ["name": $0.name, "size": $0.size] }]
    }

    private func tables(_ name: String) -> [String: Any] {
        guard let path = databasePath(name) else { return ["error": "No database named \(name)."] }
        return [
            "db": name,
            "tables": (Self.isRealm(path) ? RealmManager.shared.getTables(from: path) : SQLiteManager.shared.getTables(from: path))
                .map { ["name": $0.name, "rows": $0.rowCount] }
        ]
    }

    private static let pageSize = 500

    private func rows(_ name: String, table: String, offset: Int) -> [String: Any] {
        guard let path = databasePath(name) else { return ["error": "No database named \(name)."] }
        if Self.isRealm(path) {
            let data = RealmManager.shared.getTableData(from: path, table: table)
            return ["columns": data.columns, "rows": data.rows.map(Self.texts), "offset": 0, "total": data.rows.count]
        }
        // Counts only this table: listing every table would count each of them on every page.
        let quoted = "\"" + table.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        var total: Int?
        if case let .select(_, rows, _) = SQLiteManager.shared.executeQuery(path: path, query: "SELECT COUNT(*) FROM \(quoted)", maxRows: 1) {
            total = (rows.first?.first as? Int64).map(Int.init)
        }
        let data = SQLiteManager.shared.getTableData(from: path, table: table, limit: Self.pageSize, offset: max(0, offset))
        var result: [String: Any] = ["columns": data.columns, "rows": data.rows.map(Self.texts), "offset": max(0, offset)]
        if let total { result["total"] = total }
        return result
    }

    private func query(_ name: String, sql: String) -> [String: Any] {
        guard let path = databasePath(name) else { return ["error": "No database named \(name)."] }
        guard !Self.isRealm(path) else { return ["error": "SQL runs on SQLite databases, not Realm files."] }
        guard !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return ["error": "Enter a SQL statement."] }
        switch SQLiteManager.shared.executeQuery(path: path, query: sql, maxRows: Self.pageSize) {
        case let .select(columns, rows, hasMore):
            // Reading stops after one page, so a long result doesn't hold up the screen.
            guard hasMore else { return ["columns": columns, "rows": rows.map(Self.texts), "total": rows.count] }
            return ["columns": columns, "rows": rows.map(Self.texts), "message": "Showing the first \(rows.count) rows."]
        case let .update(affected):
            return ["columns": [String](), "rows": [[String]](), "message": affected == 1 ? "1 row changed." : "\(affected) rows changed."]
        case let .error(message):
            return ["error": message]
        }
    }

    /// A row's values as text; NULL stays null.
    private static func texts(_ row: [Any?]) -> [Any] {
        row.map { value -> Any in
            guard let value, !(value is NSNull) else { return NSNull() }
            if let data = value as? Data { return "<\(data.count) bytes>" }
            return "\(value)"
        }
    }

    // MARK: - Cookies

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
