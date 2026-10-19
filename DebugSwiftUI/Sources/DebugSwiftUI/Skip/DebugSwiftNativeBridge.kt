package debug.swift.android

/** Static entry points the native Swift panel reaches through JNI. */
object DebugSwiftNativeBridge {
    /** Installs the runtime from the running process, so a Skip Fuse host needs no Kotlin glue. */
    @JvmStatic
    fun installFromProcess(): Boolean {
        val application = runCatching {
            Class.forName("android.app.ActivityThread").getMethod("currentApplication").invoke(null)
        }.getOrNull() as? android.app.Application ?: return false
        AndroidDebugTools.install(application)
        return true
    }

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
    fun networkDecryptionSettingsJSON(): String = DebugSwiftNetworkConfig.decryptionSettingsJSON()

    @JvmStatic
    fun performNetworkDecryptionAction(actionID: String, value: String): String =
        DebugSwiftNetworkConfig.performDecryptionAction(actionID, value)

    @JvmStatic
    fun networkSessionHistorySnapshotJSON(): String = AndroidDebugTools.networkSessionHistorySnapshotJSON()

    @JvmStatic
    fun networkSessionRequestsSnapshotJSON(sessionID: String): String =
        AndroidDebugTools.networkSessionRequestsSnapshotJSON(sessionID)

    @JvmStatic
    fun performNetworkSessionHistoryAction(actionID: String, sessionID: String): String =
        AndroidDebugTools.performNetworkSessionHistoryAction(actionID, sessionID)

    @JvmStatic
    fun shareNetworkSessionRequestLog(text: String): String = AndroidDebugTools.shareNetworkSessionRequestLog(text)

    @JvmStatic
    fun replayNetworkSessionRequest(requestID: String): String = AndroidDebugTools.replayNetworkSessionRequest(requestID)

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
