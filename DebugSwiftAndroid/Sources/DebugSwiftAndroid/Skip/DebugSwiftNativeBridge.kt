package debug.swift.android

/** Kotlin calls used by SwiftUI code transpiled into Kotlin with Skip Lite. */
object DebugSwiftNativeBridge {
    @JvmStatic
    fun snapshot(featureID: String): String = AndroidDebugTools.snapshot(featureID)

    @JvmStatic
    fun securityAuditSnapshot(): String = AndroidDebugTools.securityAuditSnapshot()

    @JvmStatic
    fun networkInspectorSnapshot(featureID: String): String =
        AndroidDebugTools.networkInspectorSnapshotJSON(featureID)

    @JvmStatic
    fun webSocketInspectorSnapshot(connectionID: String, query: String, direction: String): String =
        AndroidDebugTools.webSocketInspectorSnapshotJSON(connectionID, query, direction)

    @JvmStatic
    fun performWebSocketInspectorAction(actionID: String, connectionID: String, frameID: String, value: String): String =
        AndroidDebugTools.performWebSocketInspectorAction(actionID, connectionID, frameID, value)

    @JvmStatic
    fun networkInspectorAction(featureID: String, actionID: String, requestID: String): String =
        AndroidDebugTools.performNetworkInspectorAction(featureID, actionID, requestID)

    @JvmStatic
    fun networkInjectionSettingsJSON(): String = AndroidDebugTools.networkInjectionSettingsJSON()

    @JvmStatic
    fun applyNetworkInjectionSettingsJSON(json: String): String = AndroidDebugTools.applyNetworkInjectionSettingsJSON(json)

    @JvmStatic
    fun importNetworkInjectionRulesCSV(csv: String): String = AndroidDebugTools.importNetworkInjectionRulesCSV(csv)

    @JvmStatic
    fun exportNetworkInjectionRulesCSV(): String = AndroidDebugTools.exportNetworkInjectionRulesCSV()

    @JvmStatic
    fun perform(featureID: String, actionID: String, value: String): String =
        AndroidDebugTools.perform(featureID, actionID, value)

    @JvmStatic
    fun gridSettings(): String = AndroidDebugTools.gridSettings()

    @JvmStatic
    fun setGridSettings(value: String): String = AndroidDebugTools.setGridSettings(value)

    @JvmStatic
    fun interfaceToolEnabled(featureID: String): Boolean =
        AndroidDebugTools.interfaceToolEnabled(featureID)

    @JvmStatic
    fun setInterfaceToolEnabled(featureID: String, enabled: Boolean): String =
        AndroidDebugTools.setInterfaceToolEnabled(featureID, enabled)

    @JvmStatic
    fun log(message: String) = AndroidDebugTools.log(message)
}
