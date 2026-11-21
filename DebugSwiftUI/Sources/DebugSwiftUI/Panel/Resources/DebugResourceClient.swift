import Foundation
#if os(iOS)
@_spi(DebugSwiftUI) import DebugSwift
#endif

/// Why a resource read failed; shown as is in the screens.
struct DebugResourceFailure: Error {
    let message: String
}

/// Typed access to the tools' data: the Kotlin resource API (`DebugSwiftResourceAPI`) on Android,
/// DebugSwift's `SharedPanelData` on iOS. Both answer every operation with a JSON object; a failure
/// comes back as `{"error": "..."}`.
enum DebugResourceClient {
    private struct ErrorBody: Decodable {
        let error: String?
    }

    static func fetch<T: Decodable>(
        _ operation: String,
        _ arguments: [String: String] = [:],
        as _: T.Type = T.self,
    ) -> Result<T, DebugResourceFailure> {
        #if os(Android)
            let encoded = (try? JSONEncoder().encode(arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let raw = DebugSwiftNativeBridge.resource(operation, encoded)
        #else
            // DebugSwift answers the same operations on iOS, in the same shapes. The screens read
            // from SwiftUI, on the main thread.
            let raw = MainActor.assumeIsolated { SharedPanelData.resource(operation, arguments) }
        #endif
        guard let data = raw.data(using: .utf8) else {
            return .failure(DebugResourceFailure(message: "The tool returned unreadable data."))
        }
        if let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error {
            return .failure(DebugResourceFailure(message: message))
        }
        do {
            return try .success(JSONDecoder().decode(T.self, from: data))
        } catch {
            return .failure(DebugResourceFailure(message: "The tool returned data this screen cannot read."))
        }
    }
}

struct DebugFileEntry: Decodable, Identifiable {
    let name: String
    let isDirectory: Bool
    let size: Int
    var id: String { name }
}

struct DebugFileListing: Decodable {
    let path: String
    let entries: [DebugFileEntry]
}

struct DebugFileContent: Decodable {
    let path: String
    let size: Int
    let isText: Bool
    let text: String?
    let note: String?
}

struct DebugFileDeletion: Decodable {
    let ok: Bool
    let message: String
}

struct DebugPreferenceValue: Decodable, Identifiable {
    let key: String
    let type: String
    let value: String
    var id: String { key }
}

struct DebugPreferenceStore: Decodable, Identifiable {
    let name: String
    let values: [DebugPreferenceValue]
    var id: String { name }
}

struct DebugPreferenceListing: Decodable {
    let stores: [DebugPreferenceStore]
}

struct DebugKeystoreAlias: Decodable, Identifiable {
    let alias: String
    let algorithm: String?
    let size: Int?
    let insideSecureHardware: Bool?
    let requiresUserAuthentication: Bool?
    /// iOS only: the keychain service the item belongs to, and its value.
    let service: String?
    let value: String?
    /// The service's length first, so no two service and key pairs give the same ID, whatever
    /// characters they hold.
    var id: String {
        let owner = service ?? ""
        return "\(owner.count):\(owner)|\(alias)"
    }
}

struct DebugKeystoreListing: Decodable {
    let aliases: [DebugKeystoreAlias]
    /// iOS only: keychain items can be added, edited and deleted here.
    let editable: Bool?
}

struct DebugDatabaseInfo: Decodable, Identifiable {
    let name: String
    let size: Int
    var id: String { name }
}

struct DebugDatabaseListing: Decodable {
    let databases: [DebugDatabaseInfo]
}

struct DebugTableInfo: Decodable, Identifiable {
    let name: String
    let rows: Int
    var id: String { name }
}

struct DebugTableListing: Decodable {
    let db: String
    let tables: [DebugTableInfo]
}

struct DebugTableData: Decodable {
    let columns: [String]
    let rows: [[String?]]
    let total: Int?
    let offset: Int?
    let message: String?
}

struct DebugCookie: Decodable, Identifiable {
    let name: String
    let value: String
    var id: String { name }
}

struct DebugCookieHost: Decodable, Identifiable {
    let host: String
    let cookies: [DebugCookie]
    var id: String { host }
}

struct DebugCookieListing: Decodable {
    let hosts: [DebugCookieHost]
}

func debugByteCount(_ bytes: Int) -> String {
    switch bytes {
    case 1_000_000...: String(format: "%.1f MB", Double(bytes) / 1_000_000)
    case 1_000...: String(format: "%.1f KB", Double(bytes) / 1_000)
    default: "\(bytes) B"
    }
}
