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

    /**
     * Adds a request that a Swift networking stack finished. Swift's URLSession does not go through
     * OkHttp, so Swift hands each completed exchange over as JSON and every network tool covers it.
     */
    @JvmStatic
    fun recordExternalNetwork(json: String) {
        val record = org.json.JSONObject(json)
        fun headers(key: String): Map<String, List<String>> {
            val object_ = record.optJSONObject(key) ?: return emptyMap()
            return object_.keys().asSequence().associateWith { listOf(object_.optString(it)) }
        }
        AndroidDebugTools.recordNetwork(
            method = record.optString("method"),
            url = record.optString("url"),
            status = record.optInt("status"),
            durationMs = record.optLong("durationMs"),
            requestBytes = record.optLong("requestBytes"),
            responseBytes = record.optLong("responseBytes"),
            requestBody = record.optString("requestBody"),
            responseBody = record.optString("responseBody"),
            error = record.optString("error"),
            requestHeaders = headers("requestHeaders"),
            responseHeaders = headers("responseHeaders"),
            source = "http"
        )
    }

    /**
     * What the injection rules want done to one request, as JSON for a Swift transport to carry out.
     * Same order as the OkHttp interceptor: delay, block, failure, then response rewrite. A failure
     * is consumed here, so ask once per request.
     */
    @JvmStatic
    fun injectionDecision(url: String, method: String): String {
        val decision = org.json.JSONObject()
        decision.put("delaySeconds", AndroidDebugTools.requestDelay(url, method) / 1000.0)
        val blocked = AndroidDebugTools.shouldBlock(url)
        decision.put("isBlocked", blocked)
        if (!blocked) {
            AndroidDebugTools.consumeNetworkFailure(url, method)?.let { failure ->
                decision.put("failure", org.json.JSONObject()
                    .put("kind", failure.failureType)
                    .put("statusCode", failure.statusCode ?: org.json.JSONObject.NULL)
                    .put("domain", failure.customDomain)
                    .put("code", failure.customCode)
                    .put("message", failure.customDescription))
            }
            if (!decision.has("failure")) {
                AndroidDebugTools.matchingNetworkRewriteRule(url, method)?.let { rule ->
                    decision.put("rewrite", org.json.JSONObject()
                        .put("statusCode", rule.responseStatusCode ?: org.json.JSONObject.NULL)
                        .put("body", rule.responseBody)
                        .put("shortCircuit", AndroidDebugTools.shouldShortCircuitResponseRewrite()))
                }
            }
        }
        return decision.toString()
    }

    /** Structured data for the Resources and App screens; see [DebugSwiftResourceAPI] and [DebugSwiftAppAPI]. */
    @JvmStatic
    fun resource(operation: String, arguments: String): String =
        if (operation.startsWith("app.")) DebugSwiftAppAPI.handle(operation, arguments)
        else DebugSwiftResourceAPI.handle(operation, arguments)

    @JvmStatic
    fun floatingButtonEnabled(): Boolean =
        AndroidDebugTools.contextOrNull()?.let(DebugSwiftFloatingButton::isEnabled) ?: false

    @JvmStatic
    fun setFloatingButtonEnabled(enabled: Boolean) {
        AndroidDebugTools.contextOrNull()?.let { DebugSwiftFloatingButton.setEnabled(it, enabled) }
    }

    @JvmStatic
    fun consumeFloatingButtonTap(): Boolean = DebugSwiftFloatingButton.consumeTap()

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
