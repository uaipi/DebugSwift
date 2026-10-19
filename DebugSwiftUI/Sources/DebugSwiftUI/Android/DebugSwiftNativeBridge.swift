#if os(Android)
import SkipFuse

/// JNI access to the Kotlin tools that have no Swift equivalent on Android. The functions mirror the
/// Kotlin `DebugSwiftNativeBridge` object one to one, so the panel reads the same on both platforms.
///
/// Each return type is spelled out in its own function: the generic `callStatic` picks its JNI call
/// from the static type, and an optional or generic one lands on the object variant, which the VM
/// aborts on for a primitive return.
enum DebugSwiftNativeBridge {
    private static let className = "debug/swift/android/DebugSwiftNativeBridge"
    private static let stringType = "Ljava/lang/String;"

    /// Installs the Kotlin runtime once, from the running process.
    static func install() -> Bool {
        withMethod("installFromProcess", signature: "()Z") { javaClass, id in
            let installed: Bool = try javaClass.callStatic(method: id, options: [], args: [])
            return installed
        } ?? false
    }

    static func snapshot(_ featureID: String) -> String { string("snapshot", featureID) }
    static func securityAuditSnapshot() -> String { string("securityAuditSnapshot") }
    static func networkInspectorSnapshot(_ featureID: String) -> String { string("networkInspectorSnapshot", featureID) }

    static func webSocketInspectorSnapshot(_ connectionID: String, _ query: String, _ direction: String) -> String {
        string("webSocketInspectorSnapshot", connectionID, query, direction)
    }

    static func performWebSocketInspectorAction(
        _ actionID: String,
        _ connectionID: String,
        _ frameID: String,
        _ value: String,
    ) -> String {
        string("performWebSocketInspectorAction", actionID, connectionID, frameID, value)
    }

    static func networkInspectorAction(_ featureID: String, _ actionID: String, _ requestID: String) -> String {
        string("networkInspectorAction", featureID, actionID, requestID)
    }

    static func networkDecryptionSettingsJSON() -> String { string("networkDecryptionSettingsJSON") }

    static func performNetworkDecryptionAction(_ actionID: String, _ value: String) -> String {
        string("performNetworkDecryptionAction", actionID, value)
    }

    static func networkSessionHistorySnapshotJSON() -> String { string("networkSessionHistorySnapshotJSON") }

    static func networkSessionRequestsSnapshotJSON(_ sessionID: String) -> String {
        string("networkSessionRequestsSnapshotJSON", sessionID)
    }

    static func performNetworkSessionHistoryAction(_ actionID: String, _ sessionID: String) -> String {
        string("performNetworkSessionHistoryAction", actionID, sessionID)
    }

    static func shareNetworkSessionRequestLog(_ text: String) -> String { string("shareNetworkSessionRequestLog", text) }
    static func replayNetworkSessionRequest(_ requestID: String) -> String { string("replayNetworkSessionRequest", requestID) }
    static func networkInjectionSettingsJSON() -> String { string("networkInjectionSettingsJSON") }

    static func applyNetworkInjectionSettingsJSON(_ json: String) -> String {
        string("applyNetworkInjectionSettingsJSON", json)
    }

    static func importNetworkInjectionRulesCSV(_ csv: String) -> String { string("importNetworkInjectionRulesCSV", csv) }
    static func exportNetworkInjectionRulesCSV() -> String { string("exportNetworkInjectionRulesCSV") }

    static func perform(_ featureID: String, _ actionID: String, _ value: String) -> String {
        string("perform", featureID, actionID, value)
    }

    static func gridSettings() -> String { string("gridSettings") }
    static func setGridSettings(_ value: String) -> String { string("setGridSettings", value) }

    static func interfaceToolEnabled(_ featureID: String) -> Bool {
        withMethod("interfaceToolEnabled", signature: "(\(stringType))Z") { javaClass, id in
            let enabled: Bool = try javaClass.callStatic(
                method: id,
                options: [],
                args: [featureID.toJavaParameter(options: [])],
            )
            return enabled
        } ?? false
    }

    static func setInterfaceToolEnabled(_ featureID: String, _ enabled: Bool) -> String {
        withMethod("setInterfaceToolEnabled", signature: "(\(stringType)Z)\(stringType)") { javaClass, id in
            let result: String = try javaClass.callStatic(
                method: id,
                options: [],
                args: [featureID.toJavaParameter(options: []), enabled.toJavaParameter(options: [])],
            )
            return result
        } ?? ""
    }

    static func log(_ message: String) {
        _ = withMethod("log", signature: "(\(stringType))V") { javaClass, id in
            try javaClass.callStatic(method: id, options: [], args: [message.toJavaParameter(options: [])])
            return true
        }
    }

    private static func string(_ method: String, _ args: String...) -> String {
        let signature = "(" + String(repeating: stringType, count: args.count) + ")" + stringType
        return withMethod(method, signature: signature) { javaClass, id in
            let value: String = try javaClass.callStatic(
                method: id,
                options: [],
                args: args.map { $0.toJavaParameter(options: []) },
            )
            return value
        } ?? ""
    }

    /// Looks up a static method and runs `body` attached to the JVM, since panels can call from any thread.
    private static func withMethod<T>(
        _ name: String,
        signature: String,
        _ body: (JClass, JavaMethodID) throws -> T,
    ) -> T? {
        guard isJNIInitialized else { return nil }
        do {
            return try jniContext {
                let javaClass = try JClass(name: className)
                guard let id = javaClass.getStaticMethodID(name: name, sig: signature) else { return nil }
                return try body(javaClass, id)
            }
        } catch {
            return nil
        }
    }
}
#endif
