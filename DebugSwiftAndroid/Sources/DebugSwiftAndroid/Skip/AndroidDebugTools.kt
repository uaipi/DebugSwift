package debug.swift.android

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.security.keystore.KeyInfo
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.lang.ref.WeakReference
import java.security.KeyStore
import java.security.KeyFactory
import java.security.PrivateKey
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.zip.ZipFile
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.roundToInt

/** Android implementations for platform services that have no UIKit equivalent. */
object AndroidDebugTools {
    private const val TAG = "DebugSwift"
    private const val PREFS = "debugswift.android"
    private const val MAX_RECORDS = 500
    private const val MAIN_THREAD_STALL_MS = 700L
    private const val NOTIFICATION_CHANNEL = "debugswift_local_tests"
    private const val AGENT_LOG_FILENAME = "agent-debug.ndjson"
    private const val MAX_AGENT_LOG_BYTES = 5L * 1024L * 1024L

    @Volatile private var appContext: Context? = null
    @Volatile private var foregroundActivity = WeakReference<Activity>(null)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scheduler = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "DebugSwiftMonitor").apply { isDaemon = true }
    }
    private val persistenceExecutor = Executors.newSingleThreadExecutor { task ->
        Thread(task, "DebugSwiftHistory").apply { isDaemon = true }
    }
    private val networkRecords = CopyOnWriteArrayList<NetworkRecord>()
    private val webSocketRecords = CopyOnWriteArrayList<String>()
    private val consoleRecords = CopyOnWriteArrayList<String>()
    private val crashRecords = CopyOnWriteArrayList<String>()
    private val backtraces = CopyOnWriteArrayList<String>()
    private val threadViolations = CopyOnWriteArrayList<String>()
    private val events = CopyOnWriteArrayList<String>()
    private val slowFrameEvents = CopyOnWriteArrayList<String>()
    private val recentTouches = CopyOnWriteArrayList<Pair<Float, Float>>()
    private val recordedInteractions = CopyOnWriteArrayList<RecordedInteraction>()
    private val registeredPreferences = CopyOnWriteArrayList<String>()
    private val customInfo = linkedMapOf<String, String>()
    private val customActions = linkedMapOf<String, () -> Unit>()
    private val enabledTools = mutableSetOf("network_injection")
    private val agentLogSessionID = UUID.randomUUID().toString()
    @Volatile private var agentLogEnabled = false
    @Volatile private var logcatFilter = ""
    private val destroyedActivities = CopyOnWriteArrayList<DestroyedActivity>()
    private val webViewHosts = CopyOnWriteArrayList<String>()
    private var debugOverlay: DebugOverlay? = null
    @Volatile private var activeTouchStart: Pair<Float, Float>? = null
    @Volatile private var currentFilePath = "files"
    private val gridColors = listOf(Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW, Color.WHITE, Color.GRAY)
    @Volatile private var gridSpacingDp = 28f
    @Volatile private var gridOpacity = 0.5f
    @Volatile private var gridColorIndex = 0
    @Volatile private var gridColor = gridColors[0]
    @Volatile private var simulatedMemoryWarningCount = 0
    private var lastLocation = "No location has been reported by the host app."
    private var pushToken = "No FCM token has been reported by the host app."
    private var thresholdLimit = 0
    private var thresholdWindowMs = 60_000L
    private var thresholdStartMs = 0L
    private var thresholdCount = 0
    @Volatile private var thresholdBlockRequests = false
    @Volatile private var networkFilter = ""
    @Volatile private var networkInjectionEnabled = true
    @Volatile private var requestDelayMs = 0L
    private val failNextRequest = AtomicBoolean(false)
    @Volatile private var httpErrorCode = 0
    private val responseRewrites = CopyOnWriteArrayList<Pair<Regex, String>>()
    private val blockedURLPatterns = CopyOnWriteArrayList<Regex>()

    data class NetworkRecord(
        val timestamp: Long,
        val method: String,
        val url: String,
        val status: Int,
        val durationMs: Long,
        val requestBytes: Long,
        val responseBytes: Long,
        val requestHeaders: Map<String, List<String>>,
        val responseHeaders: Map<String, List<String>>,
        val requestBody: String,
        val responseBody: String,
        val decryptedResponseBody: String,
        val error: String,
        val graphqlOperation: String,
        val source: String
    )

    private data class RecordedInteraction(
        val kind: String,
        val startX: Float,
        val startY: Float,
        val endX: Float,
        val endY: Float
    )

    private data class DestroyedActivity(
        val className: String,
        val destroyedAtMs: Long,
        val reference: WeakReference<Activity>
    )

    fun install(context: Context) {
        val applicationContext = context.applicationContext
        if (appContext === applicationContext) return
        appContext = applicationContext
        restoreAppearanceOverride(applicationContext)
        loadNetworkHistory(applicationContext)
        loadCrashHistory(applicationContext)
        registerLifecycleCallbacks(applicationContext)
        installCrashHandler()
        startAnrWatchdog()
        startFrameMonitor()
        ensureNotificationChannel(applicationContext)
        log("DebugSwift Android runtime installed on ${Build.MANUFACTURER} ${Build.MODEL}")
    }

    fun registerPreferences(name: String) {
        if (name.isNotBlank() && name != PREFS && name !in registeredPreferences) {
            registeredPreferences.add(name)
        }
    }

    fun registerInfo(key: String, value: String) {
        synchronized(customInfo) { customInfo[key] = value }
        publishEvent("app", "Custom info updated: $key")
    }

    fun registerAction(title: String, action: () -> Unit) {
        synchronized(customActions) { customActions[title] = action }
    }

    fun reportPushToken(token: String) {
        pushToken = token
        log("FCM registration token received from host app")
    }

    fun reportLocation(latitude: Double, longitude: Double, accuracyMeters: Float) {
        lastLocation = "Latitude: $latitude\nLongitude: $longitude\nAccuracy: ${accuracyMeters}m"
        publishEvent("app", "Location updated")
    }

    fun snapshot(featureID: String): String {
        val context = appContext ?: return "Android runtime has not been installed. Call AndroidDebugTools.install(application) from the host app."
        return when (featureID) {
            "http", "websocket", "network_injection", "network_thresholds", "graphql", "network_encryption", "har_export", "webview_network", "network_history" -> networkSnapshot(featureID)
            "performance_overview", "performance_widget", "battery", "disk", "memory_warning", "frame_drops", "hangs", "backtraces", "leaks", "thread_checker", "super_calls" -> performanceSnapshot(context, featureID)
            "view_hierarchy", "grid", "touches", "view_borders", "animation_control", "dark_mode", "compose_renders", "doc_recorder", "measurement", "color_palette" -> interfaceSnapshot(context, featureID)
            "files", "preferences", "keychain", "sqlite", "realm", "core_data", "swift_data", "cookies", "security_audit" -> resourcesSnapshot(context, featureID)
            "crashes", "console", "oslog_console", "device_info", "push_token", "push_simulator", "custom_actions", "custom_info", "deep_links", "loaded_libraries", "location", "event_bus", "agent_debug_log" -> appSnapshot(context, featureID)
            else -> "Unknown DebugSwift tool: $featureID"
        }
    }

    fun perform(featureID: String, actionID: String, value: String = ""): String {
        val context = appContext ?: return "Android runtime has not been installed."
        return when (actionID) {
            "clear" -> clear(featureID)
            "capture" -> capture(featureID)
            "toggle" -> if (featureID == "dark_mode") toggleDarkMode(context) else toggle(featureID)
            "export" -> export(featureID, context)
            "notify" -> sendLocalNotification(context, value)
            "refresh" -> snapshot(featureID)
            "set_delay" -> value.toLongOrNull()?.let { setRequestDelay(it); "Request delay set to ${requestDelayMs}ms." } ?: "Enter the delay in milliseconds."
            "inject_failure" -> { failNextNetworkRequest(); "The next instrumented HTTP request will fail." }
            "set_http_error" -> value.toIntOrNull()?.let { setHTTPErrorInjection(it); "HTTP error injection set to ${injectedHTTPError().takeIf { code -> code != 0 } ?: "off"}." } ?: "Enter an HTTP status code from 400 to 599."
            "rewrite_response" -> {
                val parts = value.split("=>", limit = 2)
                if (parts.size != 2 || parts.first().isBlank()) "Enter a URL regex followed by => and the replacement body."
                else { addResponseRewrite(parts.first(), parts.last()); "Response rewrite rule added." }
            }
            "block_url" -> if (value.isBlank()) "Enter a URL regex to block." else {
                runCatching { blockedURLPatterns.add(Regex(value)); "URL block rule added." }.getOrElse { "Invalid URL pattern: ${it.message}" }
            }
            "set_threshold" -> {
                val parts = value.split(",", limit = 2).map { it.trim() }
                if (parts.size != 2) "Enter request limit,window seconds."
                else {
                    val limit = parts[0].toIntOrNull()
                    val window = parts[1].toIntOrNull()
                    if (limit == null || window == null) "Both threshold values must be numbers."
                    else { setRequestThreshold(limit, window); "Request threshold set to $limit per ${window}s." }
                }
            }
            "filter_requests" -> {
                networkFilter = value.trim()
                networkSnapshot(featureID)
            }
            "filter_logs" -> {
                logcatFilter = value.trim()
                logcatSnapshot()
            }
            "browse_files" -> {
                currentFilePath = value.trim().ifEmpty { "files" }
                browseFiles(context, currentFilePath)
            }
            "register_key" -> {
                val separator = value.lastIndexOf(':')
                val pattern = value.substringBeforeLast(':').trim()
                val encodedKey = value.substringAfterLast(':').trim()
                val key = runCatching { android.util.Base64.decode(encodedKey, android.util.Base64.DEFAULT) }.getOrNull()
                if (separator <= 0 || pattern.isBlank() || key == null) "Enter a URL regex followed by ':' and a base64 AES key."
                else if (DebugSwiftNetworkConfig.registerAESKey(pattern, key)) {
                    "URL matched by '$pattern' can now decrypt base64 AES-GCM response bodies (nonce + ciphertext)."
                } else "AES key must contain 16, 24, or 32 bytes and the URL pattern must be valid."
            }
            "clear_keys" -> {
                DebugSwiftNetworkConfig.clearAESKeys()
                "Response decryption keys cleared from this process."
            }
            "set_preference" -> writePreference(context, value)
            "reset_dark_mode" -> resetDarkMode(context)
            "set_grid" -> setGridOptions(value)
            "simulate_memory_warning" -> simulateMemoryWarning()
            "run_query" -> {
                val parts = value.split("|", limit = 2)
                if (parts.size != 2) "Enter databaseName|SELECT ..."
                else DebugSwiftDatabaseBrowser.query(context, parts[0].trim(), parts[1].trim())
            }
            "run_custom" -> {
                val action = synchronized(customActions) { customActions[value] }
                if (action == null) "No registered action named '$value'." else runCatching { action(); "Action '$value' completed." }.getOrElse { "Action failed: ${it.message}" }
            }
            "report_info" -> {
                val parts = value.split("=", limit = 2)
                if (parts.size != 2 || parts[0].isBlank()) "Enter name=value."
                else { registerInfo(parts[0].trim(), parts[1]); "Diagnostic value saved." }
            }
            "open_animation_settings" -> runCatching {
                context.startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "Opened Android Developer options. Change the window, transition, or animator duration scales there."
            }.getOrElse { "Could not open Android Developer options: ${it.message}" }
            else -> "Action '$actionID' is not available for $featureID."
        }
    }

    fun log(message: String, priority: Int = Log.DEBUG, tag: String = TAG) {
        val line = "${timestamp()} ${priorityName(priority)} $tag: $message"
        consoleRecords.add(line)
        trim(consoleRecords)
        appendAgentEntry(
            kind = "console",
            location = tag,
            message = message,
            data = mapOf("priority" to priorityName(priority))
        )
        Log.println(priority, tag, message)
        publishEvent("app", message)
    }

    private fun setGridOptions(value: String): String {
        val parts = value.split(",", limit = 2).map { it.trim() }
        val spacing = parts.firstOrNull()?.toFloatOrNull()
            ?: return "Enter grid spacing in dp, optionally followed by a color such as 24,#663399FF."
        if (spacing !in 4f..256f) return "Grid spacing must be between 4 and 256 dp."
        val color = parts.getOrNull(1)?.takeIf { it.isNotEmpty() }?.let {
            runCatching { Color.parseColor(it) }.getOrElse { return "Invalid color. Use #RRGGBB or #AARRGGBB." }
        }
        gridSpacingDp = spacing
        if (color != null) gridColor = color
        debugOverlay?.postInvalidate()
        publishEvent("interface", "Grid set to ${gridSpacingDp}dp")
        return "Grid spacing set to ${gridSpacingDp}dp" + (color?.let { " with #${"%08X".format(it)}." } ?: ".")
    }

    fun gridSettings(): String {
        val enabled = synchronized(enabledTools) { "grid" in enabledTools }
        return "$enabled|$gridSpacingDp|$gridOpacity|$gridColorIndex"
    }

    fun setGridSettings(value: String): String {
        val parts = value.split("|")
        if (parts.size != 4) return "Expected enabled|size|opacity|colorIndex."
        val isEnabled = parts[0].toBooleanStrictOrNull()
            ?: return "Grid enabled value must be true or false."
        val spacing = parts[1].toFloatOrNull()
            ?: return "Grid size must be a number from 4 to 64 dp."
        val opacity = parts[2].toFloatOrNull()
            ?: return "Grid opacity must be a number from 0.1 to 1.0."
        val colorIndex = parts[3].toIntOrNull()
            ?: return "Grid color index must be an integer from 0 to 5."
        if (spacing !in 4f..64f) return "Grid size must be between 4 and 64 dp."
        if (opacity !in 0.1f..1f) return "Grid opacity must be between 0.1 and 1.0."
        if (colorIndex !in gridColors.indices) return "Grid color index must be between 0 and 5."

        gridSpacingDp = spacing
        gridOpacity = opacity
        gridColorIndex = colorIndex
        gridColor = gridColors[colorIndex]
        synchronized(enabledTools) {
            if (isEnabled) enabledTools.add("grid") else enabledTools.remove("grid")
        }
        updateOverlay()
        publishEvent("interface", "Grid ${if (isEnabled) "enabled" else "disabled"} at ${spacing}dp")
        return "Grid ${if (isEnabled) "enabled" else "disabled"}: ${spacing}dp, ${"%.1f".format(opacity)} opacity, color $colorIndex."
    }

    fun interfaceToolEnabled(featureID: String): Boolean {
        val nativeID = if (featureID == "colorize") "view_borders" else featureID
        return synchronized(enabledTools) { nativeID in enabledTools }
    }

    fun setInterfaceToolEnabled(featureID: String, enabled: Boolean): String {
        val nativeID = if (featureID == "colorize") "view_borders" else featureID
        if (nativeID !in setOf("grid", "touches", "view_borders")) {
            return "Interface toggle '$featureID' is not available on Android."
        }
        synchronized(enabledTools) {
            if (enabled) enabledTools.add(nativeID) else enabledTools.remove(nativeID)
        }
        updateOverlay()
        publishEvent("interface", "$nativeID ${if (enabled) "enabled" else "disabled"}")
        return "$nativeID ${if (enabled) "enabled" else "disabled"}."
    }

    fun recordNetwork(
        method: String,
        url: String,
        status: Int,
        durationMs: Long,
        requestBytes: Long,
        responseBytes: Long,
        requestBody: String,
        responseBody: String,
        error: String = "",
        requestHeaders: Map<String, List<String>> = emptyMap(),
        responseHeaders: Map<String, List<String>> = emptyMap(),
        source: String = "http"
    ) {
        val graphOperation = graphqlOperation(requestBody)
        networkRecords.add(
            NetworkRecord(
                System.currentTimeMillis(), method, url, status, durationMs,
                requestBytes, responseBytes, requestHeaders, responseHeaders,
                requestBody.take(32_000), responseBody.take(64_000),
                DebugSwiftNetworkConfig.decryptResponse(url, responseBody).orEmpty(),
                error, graphOperation, source
            )
        )
        trim(networkRecords)
        persistNetworkHistory()
        appendAgentEntry(
            kind = "network",
            location = "OkHttp/$source",
            message = "$method $url ($status)",
            data = mapOf(
                "method" to method,
                "url" to url,
                "status" to status,
                "durationMs" to durationMs,
                "requestBytes" to requestBytes,
                "responseBytes" to responseBytes,
                "error" to error
            )
        )
        val now = SystemClock.elapsedRealtime()
        synchronized(this) {
            if (thresholdStartMs == 0L || now - thresholdStartMs > thresholdWindowMs) {
                thresholdStartMs = now
                thresholdCount = 0
            }
            thresholdCount++
            if (thresholdLimit > 0 && thresholdCount > thresholdLimit) {
                publishEvent("network", "Request threshold exceeded: $thresholdCount / $thresholdLimit")
            }
        }
        publishEvent("network", "$method $url ($status, ${durationMs}ms)")
    }

    fun setRequestDelay(milliseconds: Long) {
        requestDelayMs = milliseconds.coerceIn(0L, 60_000L)
    }

    fun failNextNetworkRequest() {
        failNextRequest.set(true)
    }

    fun setHTTPErrorInjection(statusCode: Int) {
        httpErrorCode = if (statusCode in 400..599) statusCode else 0
    }

    fun addResponseRewrite(pattern: String, replacement: String) {
        runCatching { responseRewrites.add(Regex(pattern) to replacement) }
    }

    fun setRequestThreshold(limit: Int, windowSeconds: Int) {
        synchronized(this) {
            thresholdLimit = limit.coerceAtLeast(0)
            thresholdWindowMs = windowSeconds.coerceAtLeast(1) * 1000L
            thresholdStartMs = SystemClock.elapsedRealtime()
            thresholdCount = 0
        }
    }

    fun shouldBlock(url: String): Boolean {
        if (networkInjectionEnabled && blockedURLPatterns.any { it.containsMatchIn(url) }) return true
        return synchronized(this) {
            thresholdBlockRequests && thresholdLimit > 0 && thresholdCount >= thresholdLimit &&
                thresholdStartMs != 0L && SystemClock.elapsedRealtime() - thresholdStartMs <= thresholdWindowMs
        }
    }

    fun requestDelay(): Long = requestDelayMs.takeIf { networkInjectionEnabled } ?: 0L

    fun consumeFailure(): Boolean {
        return networkInjectionEnabled && failNextRequest.compareAndSet(true, false)
    }

    fun injectedHTTPError(): Int = httpErrorCode.takeIf { networkInjectionEnabled } ?: 0

    fun rewriteResponse(url: String, body: String): String {
        if (!networkInjectionEnabled) return body
        var rewritten = body
        responseRewrites.forEach { (pattern, replacement) ->
            if (pattern.containsMatchIn(url)) rewritten = replacement
        }
        return rewritten
    }

    fun recordWebSocket(url: String, direction: String, payload: String) {
        val line = "${timestamp()} WebSocket $direction $url: ${payload.take(500)}"
        webSocketRecords.add(line)
        trim(webSocketRecords)
        publishEvent("network", line)
        log("WebSocket $direction $url: ${payload.take(500)}", Log.VERBOSE)
    }

    fun recordWebViewHost(host: String) {
        if (host.isNotBlank() && host !in webViewHosts) webViewHosts.add(host)
    }

    fun recordTouch(event: MotionEvent) {
        val point = localTouchPosition(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                activeTouchStart = point
                recentTouches.add(point)
            }
            MotionEvent.ACTION_MOVE -> recentTouches.add(point)
            MotionEvent.ACTION_UP -> {
                recentTouches.add(point)
                val start = activeTouchStart ?: point
                val dx = point.first - start.first
                val dy = point.second - start.second
                val density = appContext?.resources?.displayMetrics?.density ?: 1f
                val threshold = 24f * density
                val kind = if (dx * dx + dy * dy >= threshold * threshold) "scroll" else "tap"
                recordedInteractions.add(RecordedInteraction(kind, start.first, start.second, point.first, point.second))
                trim(recordedInteractions)
                appendAgentEntry(
                    kind = "event",
                    location = "Interface/$kind",
                    message = if (kind == "tap") "Tap recorded" else "Scroll gesture recorded",
                    data = mapOf("x" to point.first, "y" to point.second, "startX" to start.first, "startY" to start.second)
                )
                activeTouchStart = null
            }
            MotionEvent.ACTION_CANCEL -> activeTouchStart = null
        }
        while (recentTouches.size > 24) recentTouches.removeAt(0)
        debugOverlay?.invalidate()
    }

    private fun localTouchPosition(event: MotionEvent): Pair<Float, Float> {
        val offset = IntArray(2)
        foregroundActivity.get()?.window?.decorView?.getLocationOnScreen(offset)
        return (event.rawX - offset[0]) to (event.rawY - offset[1])
    }

    fun captureHierarchy(): String {
        val activity = foregroundActivity.get() ?: return "No foreground activity is available."
        val root = activity.window.decorView
        return buildString {
            append("Window ${root.width} × ${root.height}px\n")
            describeView(root, 0, this)
        }.take(40_000)
    }

    fun exportHar(featureID: String = "network_history"): File? {
        val context = appContext ?: return null
        val entries = org.json.JSONArray()
        val records = when (featureID) {
            "http" -> networkRecords.filter { it.source == "http" }
            "graphql" -> networkRecords.filter { it.source == "http" && it.graphqlOperation.isNotBlank() }
            else -> networkRecords.toList()
        }
        records.forEach { record ->
            val request = org.json.JSONObject()
                .put("method", record.method)
                .put("url", record.url)
                .put("httpVersion", "HTTP/1.1")
                .put("headers", harHeaders(record.requestHeaders))
                .put("queryString", org.json.JSONArray())
                .put("cookies", org.json.JSONArray())
                .put("headersSize", -1)
                .put("bodySize", record.requestBytes)
            if (record.requestBody.isNotEmpty()) {
                request.put("postData", org.json.JSONObject()
                    .put("mimeType", headerValue(record.requestHeaders, "Content-Type") ?: "application/octet-stream")
                    .put("text", record.requestBody))
            }
            val responseContent = org.json.JSONObject()
                .put("size", record.responseBytes)
                .put("mimeType", headerValue(record.responseHeaders, "Content-Type") ?: "application/octet-stream")
            record.responseBody.takeIf { it.isNotEmpty() }?.let { responseContent.put("text", it) }
            entries.put(
                org.json.JSONObject()
                    .put("startedDateTime", harTimestamp(record.timestamp))
                    .put("time", record.durationMs)
                    .put("request", request)
                    .put("response", org.json.JSONObject()
                        .put("status", record.status)
                        .put("statusText", record.error)
                        .put("httpVersion", "HTTP/1.1")
                        .put("headers", harHeaders(record.responseHeaders))
                        .put("cookies", org.json.JSONArray())
                        .put("content", responseContent)
                        .put("redirectURL", "")
                        .put("headersSize", -1)
                        .put("bodySize", record.responseBytes))
                    .put("cache", org.json.JSONObject())
                    .put("timings", org.json.JSONObject().put("send", -1).put("wait", record.durationMs).put("receive", -1))
            )
        }
        val har = org.json.JSONObject().put("log", org.json.JSONObject().put("version", "1.2").put("creator", org.json.JSONObject().put("name", "DebugSwift Android").put("version", "1.0")).put("entries", entries))
        val file = File(context.cacheDir, "debugswift-${System.currentTimeMillis()}.har")
        file.writeText(har.toString(2))
        publishEvent("resources", "Exported ${entries.length()} network requests to ${file.name}")
        return file
    }

    private fun exportWebSockets(context: Context): File =
        File(context.cacheDir, "debugswift-websocket-${System.currentTimeMillis()}.txt").apply {
            writeText(webSocketRecords.joinToString("\n\n"))
        }

    private fun loadNetworkHistory(context: Context) {
        val file = File(context.filesDir, "debugswift-network-history.json")
        if (!file.isFile) return
        runCatching {
            val rows = org.json.JSONObject(file.readText()).optJSONArray("requests") ?: return
            for (index in 0 until rows.length()) {
                val row = rows.getJSONObject(index)
                networkRecords.add(
                    NetworkRecord(
                        timestamp = row.optLong("timestamp"),
                        method = row.optString("method"),
                        url = row.optString("url"),
                        status = row.optInt("status"),
                        durationMs = row.optLong("durationMs"),
                        requestBytes = row.optLong("requestBytes"),
                        responseBytes = row.optLong("responseBytes"),
                        requestHeaders = decodeHeaders(row.optJSONObject("requestHeaders")),
                        responseHeaders = decodeHeaders(row.optJSONObject("responseHeaders")),
                        requestBody = row.optString("requestBody"),
                        responseBody = row.optString("responseBody"),
                        decryptedResponseBody = row.optString("decryptedResponseBody"),
                        error = row.optString("error"),
                        graphqlOperation = row.optString("graphqlOperation"),
                        source = row.optString("source", "http")
                    )
                )
            }
            trim(networkRecords)
        }.onFailure { error ->
            log("Could not read saved network history: ${error.message}", Log.WARN)
        }
    }

    private fun persistNetworkHistory() {
        val context = appContext ?: return
        val snapshot = networkRecords.takeLast(100).toList()
        persistenceExecutor.execute {
            runCatching {
                val rows = org.json.JSONArray()
                snapshot.forEach { record ->
                    rows.put(org.json.JSONObject()
                        .put("timestamp", record.timestamp)
                        .put("method", record.method)
                        .put("url", record.url)
                        .put("status", record.status)
                        .put("durationMs", record.durationMs)
                        .put("requestBytes", record.requestBytes)
                        .put("responseBytes", record.responseBytes)
                        .put("requestHeaders", encodeHeaders(record.requestHeaders))
                        .put("responseHeaders", encodeHeaders(record.responseHeaders))
                        .put("requestBody", record.requestBody.take(8_000))
                        .put("responseBody", record.responseBody.take(16_000))
                        .put("decryptedResponseBody", record.decryptedResponseBody.take(16_000))
                        .put("error", record.error)
                        .put("graphqlOperation", record.graphqlOperation)
                        .put("source", record.source))
                }
                val target = File(context.filesDir, "debugswift-network-history.json")
                val temporary = File(context.filesDir, "debugswift-network-history.tmp")
                temporary.writeText(org.json.JSONObject().put("requests", rows).toString())
                if (!temporary.renameTo(target)) {
                    target.writeText(temporary.readText())
                    temporary.delete()
                }
            }
        }
    }

    private fun encodeHeaders(headers: Map<String, List<String>>): org.json.JSONObject =
        org.json.JSONObject().also { json -> headers.forEach { (key, values) -> json.put(key, org.json.JSONArray(values)) } }

    private fun decodeHeaders(headers: org.json.JSONObject?): Map<String, List<String>> {
        if (headers == null) return emptyMap()
        return buildMap {
            val keys = headers.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                val values = headers.optJSONArray(key) ?: continue
                put(key, buildList { for (index in 0 until values.length()) add(values.optString(index)) })
            }
        }
    }

    private fun harHeaders(headers: Map<String, List<String>>): org.json.JSONArray = org.json.JSONArray().also { array ->
        headers.forEach { (name, values) -> values.forEach { value ->
            array.put(org.json.JSONObject().put("name", name).put("value", value))
        } }
    }

    private fun headerValue(headers: Map<String, List<String>>, name: String): String? =
        headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value?.firstOrNull()

    private fun formatHeaders(headers: Map<String, List<String>>): String =
        headers.entries.joinToString("\n") { (name, values) -> "$name: ${values.joinToString(", ")}" }

    private fun harTimestamp(timestamp: Long): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = java.util.TimeZone.getTimeZone("UTC")
    }.format(Date(timestamp))

    private fun networkSnapshot(featureID: String): String {
        if (featureID == "network_injection") {
            return "Injection enabled: $networkInjectionEnabled\nDelay: ${requestDelayMs}ms\nFail next request: ${failNextRequest.get()}\nHTTP error: ${httpErrorCode.takeIf { it != 0 } ?: "off"}\nResponse rewrites: ${responseRewrites.size}\nBlocked URL patterns: ${blockedURLPatterns.size}"
        }
        if (featureID == "network_thresholds") {
            return "Requests in window: $thresholdCount\nLimit: ${thresholdLimit.takeIf { it > 0 } ?: "off"}\nWindow: ${thresholdWindowMs / 1000}s\nBlock after limit: $thresholdBlockRequests"
        }
        if (featureID == "websocket") {
            val matching = webSocketRecords.takeLast(30)
            return "WebSocket events: ${matching.size}\n" + matching.joinToString("\n")
        }
        if (featureID == "webview_network") {
            val requests = networkRecords.filter { it.source == "webview" }.takeLast(30).asReversed()
            return "Observed WebView hosts:\n" + webViewHosts.takeLast(30).joinToString("\n").ifEmpty { "No host app WebViews have reported activity." } +
                "\n\nRecorded navigation/resources:\n" + requests.joinToString("\n") { "${it.method} ${it.url}" }.ifEmpty { "Install DebugSwiftWebViewClient on host WebViews to record navigation and resource requests." }
        }
        if (featureID == "har_export") {
            return "Captured requests available for HAR export: ${networkRecords.size}\nUse Export to write a .har file into the app cache."
        }
        if (featureID == "network_encryption") {
            return "Registered body decryptors: ${DebugSwiftNetworkConfig.decryptors.size}\nHost-supplied keys are kept in memory for this process."
        }
        val historyDescription = if (featureID == "network_history") {
            "WebSocket frames: ${webSocketRecords.size}\nUp to 100 recent HTTP requests are restored from app-private storage; this process keeps at most $MAX_RECORDS.\n"
        } else ""
        val recordsForFeature = when (featureID) {
            "graphql" -> networkRecords.filter { it.source == "http" && it.graphqlOperation.isNotBlank() }
            "http" -> networkRecords.filter { it.source == "http" }
            else -> networkRecords.toList()
        }
        val matchingRecords = recordsForFeature.filter { record ->
            val query = networkFilter.trim().lowercase()
            query.isEmpty() || listOf(record.url, record.method, record.requestBody, record.responseBody, record.graphqlOperation)
                .any { it.lowercase().contains(query) }
        }
        val lines = matchingRecords.takeLast(40).asReversed().map { record ->
            "${record.method} ${record.url}\n  ${record.status} · ${record.durationMs}ms · ${record.responseBytes} bytes" +
                (record.graphqlOperation.takeIf { it.isNotBlank() }?.let { "\n  GraphQL: $it" } ?: "") +
                (record.error.takeIf { it.isNotBlank() }?.let { "\n  Error: $it" } ?: "") +
                (formatHeaders(record.requestHeaders).takeIf { it.isNotBlank() }?.let { "\n  Request headers:\n$it" } ?: "") +
                (record.requestBody.takeIf { it.isNotBlank() }?.let { "\n  Request body: ${it.take(2_000)}" } ?: "") +
                (formatHeaders(record.responseHeaders).takeIf { it.isNotBlank() }?.let { "\n  Response headers:\n$it" } ?: "") +
                (record.decryptedResponseBody.takeIf { it.isNotBlank() }?.let { "\n  Decrypted response: ${it.take(2_000)}" } ?: "") +
                (record.responseBody.takeIf { it.isNotBlank() }?.let { "\n  Response: ${it.take(2_000)}" } ?: "")
        }
        val filterDescription = networkFilter.takeIf { it.isNotBlank() }?.let { "\nFilter: $it · ${matchingRecords.size} matches" }.orEmpty()
        val capturedTitle = when (featureID) {
            "graphql" -> "GraphQL operations"
            "network_history" -> "Saved network requests"
            else -> "HTTP requests"
        }
        return historyDescription + "Captured $capturedTitle: ${recordsForFeature.size}$filterDescription\n" + lines.joinToString("\n\n").ifEmpty { "No matching requests. Add DebugSwiftOkHttpInterceptor to the host OkHttpClient.Builder." }
    }

    private fun performanceSnapshot(context: Context, featureID: String): String {
        return when (featureID) {
            "memory_warning" -> "Simulated callbacks sent: $simulatedMemoryWarningCount\nThe action calls Application.onLowMemory and foreground Activity low-memory/critical-trim callbacks. Android does not let an app force the operating system to enter real memory pressure."
            "battery" -> {
                val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
                val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
                val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
                val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
                val percent = if (level >= 0 && scale > 0) (level * 100 / scale) else -1
                "Battery: ${percent}%\nCharging: ${status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL}\nPower source: ${intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0}"
            }
            "disk" -> {
                val files = context.filesDir.walkTopDown().filter { it.isFile }.toList()
                val bytes = files.sumOf { it.length() }
                val io = runCatching { File("/proc/self/io").readLines().filter { it.startsWith("read_bytes:") || it.startsWith("write_bytes:") }.joinToString("\n") }.getOrDefault("I/O counters unavailable")
                "Files directory: ${context.filesDir.absolutePath}\nFiles: ${files.size}\nApp files: ${formatBytes(bytes)}\n$io\nDatabases: ${context.databaseList().joinToString().ifEmpty { "none" }}"
            }
            "frame_drops" -> "Frames sampled: $frameCount\nSlow frames (>32ms): $slowFrameCount\nSlowest frame: ${slowestFrameMs}ms\n\nRecent slow frames:\n" + slowFrameEvents.takeLast(40).asReversed().joinToString("\n").ifEmpty { "No slow frame events captured." }
            "hangs" -> "Detected main-thread stalls: ${events.count { it.contains("main thread stalled") }}\nThreshold: ${MAIN_THREAD_STALL_MS}ms\nRecent events:\n" + events.filter { it.contains("main thread stalled") }.takeLast(20).joinToString("\n").ifEmpty { "No stalls detected." } + "\n\nAndroid process ANRs:\n${platformExitHistory(context, android.app.ApplicationExitInfo.REASON_ANR)}"
            "backtraces" -> backtraces.takeLast(20).asReversed().joinToString("\n\n").ifEmpty { "No backtraces captured. Use Capture to save the current thread stack." }
            "performance_widget" -> {
                val enabled = synchronized(enabledTools) { "performance_widget" in enabledTools }
                if (!enabled) "Performance widget is disabled. Enable it to show live metrics over the host app."
                else "Widget is active in the host app window.\nCPU: ${"%.1f".format(cpuUsagePercent)}%\nFrames/s: $framesPerSecond\nSlow frames: $slowFrameCount"
            }
            "leaks" -> {
                val candidates = destroyedActivities.filter {
                    SystemClock.elapsedRealtime() - it.destroyedAtMs >= 5_000L && it.reference.get() != null
                }
                "Destroyed Activities still reachable after 5s: ${candidates.size}\n" +
                    candidates.joinToString("\n") { it.className }.ifEmpty { "No retained Activity candidates detected." } +
                    "\n\nThis is a reachability heuristic; force a GC or use Android Studio's Memory Profiler to confirm a leak."
            }
            "thread_checker" -> "Current thread: ${Thread.currentThread().name}\nUI thread: ${Looper.myLooper() == Looper.getMainLooper()}\nStrictMode: ${if ("thread_checker" in enabledTools) "enabled" else "disabled"}\nRecent violations:\n" + threadViolations.takeLast(30).asReversed().joinToString("\n\n").ifEmpty { "No StrictMode violations recorded." }
            "super_calls" -> "Android reports missing required Activity super calls with SuperNotCalledException. Recent captured crashes: ${crashRecords.count { it.contains("SuperNotCalledException") }}"
            else -> {
                val runtime = Runtime.getRuntime()
                val used = runtime.totalMemory() - runtime.freeMemory()
                val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val memory = ActivityManager.MemoryInfo().also(manager::getMemoryInfo)
                val cpu = Process.getElapsedCpuTime()
                cpuUsagePercent = cpuUsage(cpu)
                "CPU usage: ${"%.1f".format(cpuUsagePercent)}%\nProcess memory: ${formatBytes(used)} / ${formatBytes(runtime.maxMemory())}\nNative heap: ${formatBytes(Debug.getNativeHeapAllocatedSize())}\nSystem available memory: ${formatBytes(memory.availMem)}\nCPU time: ${cpu}ms\nFrames sampled: $frameCount (${slowFrameCount} slow)"
            }
        }
    }

    private fun simulateMemoryWarning(): String {
        val application = appContext?.applicationContext as? Application
        val activity = foregroundActivity.get()
        if (application == null && activity == null) return "No Android Application or foreground Activity is available."

        mainHandler.post {
            simulatedMemoryWarningCount += 1
            runCatching { application?.onLowMemory() }
            runCatching { application?.onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL) }
            if (activity != null) {
                runCatching { activity.onLowMemory() }
                runCatching { activity.onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL) }
            }
            publishEvent("performance", "Android low-memory callbacks simulated")
        }
        return "Sent low-memory and critical-trim callbacks to the Application and foreground Activity. This does not create real OS memory pressure."
    }

    private fun interfaceSnapshot(context: Context, featureID: String): String {
        return when (featureID) {
            "view_hierarchy", "measurement" -> captureHierarchy()
            "grid", "touches", "view_borders" -> "Enabled: ${synchronized(enabledTools) { featureID in enabledTools }}\nOverlay is drawn in the host app window without the system draw-over-other-apps permission.\nGrid: ${gridSpacingDp}dp, ${"%.1f".format(gridOpacity)} opacity, #${"%08X".format(gridColor)}\nRecent touches: ${recentTouches.size}"
            "animation_control" -> {
                val keys = listOf("window_animation_scale", "transition_animation_scale", "animator_duration_scale")
                "Android system animation scales:\n" + keys.joinToString("\n") { key ->
                    val value = runCatching { android.provider.Settings.Global.getFloat(context.contentResolver, key, 1f) }.getOrDefault(1f)
                    "$key: ${value}×"
                } + "\n\nUse Open Developer options to change these system-wide settings."
            }
            "dark_mode" -> appearanceSnapshot(context)
            "compose_renders" -> "Compose recompositions observed: $composeRenderCount\nMeasured frame callbacks: $frameCount\nSlow frames: $slowFrameCount"
            "doc_recorder" -> "Recorded gestures: ${recordedInteractions.size}\nTaps: ${recordedInteractions.count { it.kind == "tap" }}\nScrolls: ${recordedInteractions.count { it.kind == "scroll" }}\nLast screenshot: ${lastRecordingPath.ifEmpty { "none" }}"
            "color_palette" -> "Most common colors in the last captured app window:\n${lastPalette.joinToString("\n").ifEmpty { "Capture a screen to sample its colors." }}"
            else -> "View hierarchy entries: ${captureHierarchy().lineSequence().count()}"
        }
    }

    private fun appearanceSnapshot(context: Context): String {
        val override = when (AppCompatDelegate.getDefaultNightMode()) {
            AppCompatDelegate.MODE_NIGHT_YES -> "Dark"
            AppCompatDelegate.MODE_NIGHT_NO -> "Light"
            else -> "Follow system"
        }
        val windowContext = foregroundActivity.get() ?: context
        val nightMode = windowContext.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
        val effective = if (nightMode == android.content.res.Configuration.UI_MODE_NIGHT_YES) "Dark" else "Light"
        return "Appearance override: $override\nCurrent host window: $effective\n\nToggle Dark Mode to force light or dark appearance. Follow system appearance clears the override. AppCompat host activities apply the override when their theme supports DayNight."
    }

    private fun toggleDarkMode(context: Context): String {
        val windowContext = foregroundActivity.get() ?: context
        val nightMode = windowContext.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
        val currentlyDark = when (AppCompatDelegate.getDefaultNightMode()) {
            AppCompatDelegate.MODE_NIGHT_YES -> true
            AppCompatDelegate.MODE_NIGHT_NO -> false
            else -> nightMode == android.content.res.Configuration.UI_MODE_NIGHT_YES
        }
        val newMode = if (currentlyDark) AppCompatDelegate.MODE_NIGHT_NO else AppCompatDelegate.MODE_NIGHT_YES
        val override = if (newMode == AppCompatDelegate.MODE_NIGHT_YES) "dark" else "light"
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("appearance_override", override).apply()
        AppCompatDelegate.setDefaultNightMode(newMode)
        publishEvent("interface", "Appearance forced to $override mode")
        return "App appearance forced to ${override.replaceFirstChar { it.uppercase() }} mode. AppCompat host activities apply the override when their theme supports DayNight."
    }

    private fun resetDarkMode(context: Context): String {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove("appearance_override").apply()
        AppCompatDelegate.setDefaultNightMode(AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM)
        publishEvent("interface", "Appearance follows system settings")
        return "App appearance now follows the Android system setting."
    }

    private fun restoreAppearanceOverride(context: Context) {
        val mode = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("appearance_override", "system")
        AppCompatDelegate.setDefaultNightMode(
            when (mode) {
                "dark" -> AppCompatDelegate.MODE_NIGHT_YES
                "light" -> AppCompatDelegate.MODE_NIGHT_NO
                else -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
            }
        )
    }

    private fun resourcesSnapshot(context: Context, featureID: String): String {
        return when (featureID) {
            "files" -> browseFiles(context, currentFilePath)
            "preferences" -> registeredPreferences.joinToString("\n\n") { name ->
                val values = context.getSharedPreferences(name, Context.MODE_PRIVATE).all
                "$name (${values.size} values)\n" + values.entries.joinToString("\n") { "${it.key} = ${safeValue(it.value)}" }
            }.ifEmpty { "No host preferences registered. Call AndroidDebugTools.registerPreferences(name) during app startup." }
            "keychain" -> {
                val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
                "Android Keystore aliases:\n" + store.aliases().toList().joinToString("\n").ifEmpty { "none" } + "\nPrivate key and secret bytes are not exported."
            }
            "realm" -> "Registered Realm databases:\n${DebugSwiftRealmRegistry.snapshot()}\n\nSQLite files:\n${DebugSwiftDatabaseBrowser.databaseNames(context).joinToString("\n").ifEmpty { "none" }}"
            "sqlite", "core_data", "swift_data" -> {
                val dbs = DebugSwiftDatabaseBrowser.databaseNames(context).map { name ->
                    val file = context.getDatabasePath(name)
                    val tables = runCatching { DebugSwiftDatabaseBrowser.tables(context, name).joinToString() }.getOrDefault("unavailable")
                    "$name (${formatBytes(file.length())})\nTables: ${tables.ifEmpty { "none" }}"
                }
                "SQLite/Room databases in this app:\n" + dbs.joinToString("\n").ifEmpty { "No app databases found." } +
                    "\n\nRoom databases use SQLite files. Register external or custom database names to enable browsing."
            }
            "cookies" -> {
                val values = webViewHosts.mapNotNull { host -> CookieManager.getInstance().getCookie("https://$host")?.let { "$host\n$it" } }
                values.joinToString("\n\n").ifEmpty { "No cookies available for reported host-app WebView domains." }
            }
            "security_audit" -> securityAudit(context)
            else -> "No resources found."
        }
    }

    private fun logcatSnapshot(): String {
        val result = runCatching {
            val process = ProcessBuilder("logcat", "-d", "-t", "500", "--pid=${Process.myPid()}")
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().use { it.readText() }
            val exitCode = process.waitFor()
            if (exitCode != 0) return "Android Logcat is unavailable (exit $exitCode):\n${output.takeLast(8_000)}"
            output
        }.getOrElse { return "Android Logcat is unavailable: ${it.message ?: it.javaClass.simpleName}" }
        val filtered = result.lineSequence()
            .filter { logcatFilter.isBlank() || it.contains(logcatFilter, ignoreCase = true) }
            .toList()
            .takeLast(300)
            .joinToString("\n")
            .takeLast(128_000)
        val filterSummary = logcatFilter.takeIf { it.isNotBlank() }?.let { "\nFilter: $it" }.orEmpty()
        return "Android Logcat records for this process PID ${Process.myPid()}$filterSummary\n\n" +
            filtered.ifEmpty { "No matching Logcat records are currently available." }
    }

    private fun appSnapshot(context: Context, featureID: String): String {
        return when (featureID) {
            "crashes" -> "Saved crash reports:\n" + crashRecords.takeLast(20).asReversed().joinToString("\n\n") { it }.ifEmpty { "No uncaught crash reports saved by DebugSwift." } + "\n\nRecent Android process exits:\n${platformExitHistory(context)}"
            "console" -> consoleRecords.takeLast(100).asReversed().joinToString("\n").ifEmpty { "No messages captured. Use DebugSwiftAndroidRuntime.log() from the host app." }
            "oslog_console" -> logcatSnapshot()
            "push_token" -> pushToken
            "push_simulator" -> "Create a local Android notification without an FCM server. Enter title | message | optional delay seconds, then choose Post test notification.\nChannel: $NOTIFICATION_CHANNEL"
            "custom_actions" -> synchronized(customActions) { customActions.keys.toList() }.joinToString("\n").ifEmpty { "No custom actions registered by the host app." }
            "custom_info" -> synchronized(customInfo) { customInfo.entries.joinToString("\n") { "${it.key}: ${it.value}" } }.ifEmpty { "No host diagnostic values registered." }
            "deep_links" -> lastIntentDescription.ifEmpty { "No deep-link intent received. Call reportIntent(intent) from your host Activity." }
            "loaded_libraries" -> {
                val appInfo = context.applicationInfo
                val dexFiles = (listOf(appInfo.sourceDir) + appInfo.splitSourceDirs.orEmpty()).joinToString("\n")
                "App package: ${context.packageName}\nInstalled DEX files:\n$dexFiles\nNative library directory: ${appInfo.nativeLibraryDir}\nSupported ABIs: ${Build.SUPPORTED_ABIS.joinToString()}\nNative heap: ${formatBytes(Debug.getNativeHeapAllocatedSize())}\nClass loader: ${context.classLoader.javaClass.name}"
            }
            "location" -> lastLocation
            "event_bus" -> events.takeLast(100).asReversed().joinToString("\n").ifEmpty { "No diagnostic events published yet." }
            "agent_debug_log" -> agentDebugLogSnapshot(context)
            "device_info" -> deviceInfo(context)
            else -> deviceInfo(context)
        }
    }

    private fun clear(featureID: String): String {
        when (featureID) {
            "http" -> {
                networkRecords.removeAll { it.source == "http" }
                networkFilter = ""
                persistNetworkHistory()
                publishEvent("network", "HTTP history cleared")
                return "HTTP history cleared."
            }
            "graphql" -> {
                networkRecords.removeAll { it.graphqlOperation.isNotBlank() }
                persistNetworkHistory()
                publishEvent("network", "GraphQL history cleared")
                return "GraphQL history cleared."
            }
            "webview_network" -> {
                networkRecords.removeAll { it.source == "webview" }
                webViewHosts.clear()
                persistNetworkHistory()
                publishEvent("network", "WebView history cleared")
                return "WebView history cleared."
            }
            "websocket" -> {
                webSocketRecords.clear()
                events.removeAll { it.contains("WebSocket") }
                publishEvent("network", "WebSocket history cleared")
                return "WebSocket history cleared."
            }
            "network_history", "har_export" -> {
                networkRecords.clear()
                webSocketRecords.clear()
                networkFilter = ""
                synchronized(this) { thresholdCount = 0; thresholdStartMs = SystemClock.elapsedRealtime() }
                events.removeAll { it.contains("WebSocket") }
                persistNetworkHistory()
                publishEvent("network", "Network history cleared")
                return "Network and WebSocket history cleared."
            }
            "console" -> consoleRecords.clear()
            "agent_debug_log" -> {
                persistenceExecutor.execute {
                    File(appContext!!.filesDir, AGENT_LOG_FILENAME).delete()
                    File(appContext!!.filesDir, "$AGENT_LOG_FILENAME.previous").delete()
                }
                return "Agent debug log cleared."
            }
            "crashes" -> {
                crashRecords.clear()
                appContext?.filesDir?.listFiles()?.filter { it.name.startsWith("debugswift-crash-") }?.forEach { it.delete() }
            }
            "backtraces" -> backtraces.clear()
            "thread_checker" -> threadViolations.clear()
            "event_bus" -> events.clear()
            "frame_drops", "hangs" -> {
                events.removeAll { it.contains("frame") || it.contains("main thread stalled") }
                slowFrameEvents.clear()
                frameCount = 0
                slowFrameCount = 0
                slowestFrameMs = 0
            }
            "doc_recorder" -> {
                recordedInteractions.clear()
                recentTouches.clear()
                lastRecordingPath = ""
            }
            "color_palette" -> lastPalette = emptyList()
            else -> {
                return "$featureID has no history to clear."
            }
        }
        publishEvent("app", "$featureID history cleared")
        return "$featureID history cleared."
    }

    private fun capture(featureID: String): String {
        when (featureID) {
            "backtraces" -> {
                val trace = Throwable("DebugSwift backtrace at ${timestamp()}").stackTraceToString()
                backtraces.add(trace)
                trim(backtraces)
                publishEvent("performance", "Backtrace captured")
                return trace
            }
            "view_hierarchy", "measurement" -> return captureHierarchy()
            "doc_recorder" -> return captureScreenshot(annotateTouches = true)
            "color_palette" -> return capturePalette()
            "push_simulator" -> return sendLocalNotification(appContext!!)
            "http", "websocket", "network_history" -> return networkSnapshot(featureID)
            "crashes" -> return crashRecords.lastOrNull() ?: "No crash record is available. Crashes are saved when the process handles an uncaught exception."
            else -> {
                publishEvent("performance", "Manual capture requested for $featureID")
                return "Capture recorded at ${timestamp()}.\n\n${snapshot(featureID)}"
            }
        }
    }

    private fun toggle(featureID: String): String {
        val enabled = synchronized(enabledTools) {
            if (featureID in enabledTools) {
                enabledTools.remove(featureID)
                false
            } else {
                enabledTools.add(featureID)
                true
            }
        }
        when (featureID) {
            "grid", "touches", "view_borders", "performance_widget" -> updateOverlay()
            "agent_debug_log" -> if (enabled) {
                agentLogEnabled = true
            }
            "thread_checker" -> if (enabled) enableStrictMode() else disableStrictMode()
            "network_thresholds" -> thresholdBlockRequests = enabled
            "network_injection" -> {
                networkInjectionEnabled = enabled
                if (!enabled) clearInjectionRules()
            }
        }
        publishEvent("interface", "$featureID ${if (enabled) "enabled" else "disabled"}")
        if (featureID == "agent_debug_log" && !enabled) agentLogEnabled = false
        return "$featureID ${if (enabled) "enabled" else "disabled"}."
    }

    private fun export(featureID: String, context: Context): String {
        val file = when (featureID) {
            "http" -> exportHar("http")
            "graphql" -> exportHar("graphql")
            "websocket" -> exportWebSockets(context)
            "har_export", "network_history" -> exportHar()
            "realm" -> File(context.cacheDir, "debugswift-realm-${System.currentTimeMillis()}.txt").apply { writeText(snapshot(featureID)) }
            "console" -> File(context.cacheDir, "debugswift-console-${System.currentTimeMillis()}.txt").apply { writeText(consoleRecords.joinToString("\n")) }
            "oslog_console" -> File(context.cacheDir, "debugswift-logcat-${System.currentTimeMillis()}.txt").apply { writeText(logcatSnapshot()) }
            "agent_debug_log" -> File(context.filesDir, AGENT_LOG_FILENAME).takeIf { it.exists() }
            "crashes" -> File(context.cacheDir, "debugswift-crashes-${System.currentTimeMillis()}.txt").apply { writeText(crashRecords.joinToString("\n\n")) }
            "files" -> exportCurrentFile(context)
            "color_palette" -> File(context.cacheDir, "debugswift-palette-${System.currentTimeMillis()}.txt").apply { writeText(lastPalette.joinToString("\n")) }
            "sqlite", "core_data", "swift_data" -> File(context.cacheDir, "debugswift-resources-${System.currentTimeMillis()}.txt").apply { writeText(snapshot(featureID)) }
            "doc_recorder" -> File(lastRecordingPath).takeIf { lastRecordingPath.isNotEmpty() && it.exists() }
            else -> null
        }
        return file?.let { "Exported ${it.name}\n${it.absolutePath}" } ?: "Nothing to export for $featureID."
    }

    private fun registerLifecycleCallbacks(context: Context) {
        val application = context as? Application ?: return
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: android.os.Bundle?) {
                publishEvent("app", "Activity created: ${activity.javaClass.simpleName}")
            }

            override fun onActivityStarted(activity: Activity) {
                publishEvent("app", "Activity started: ${activity.javaClass.simpleName}")
            }

            override fun onActivityResumed(activity: Activity) {
                val previous = foregroundActivity.get()
                foregroundActivity = WeakReference(activity)
                if (previous !== activity) updateOverlay()
                publishEvent("app", "Activity resumed: ${activity.javaClass.simpleName}")
            }

            override fun onActivityPaused(activity: Activity) {
                publishEvent("app", "Activity paused: ${activity.javaClass.simpleName}")
            }

            override fun onActivityStopped(activity: Activity) {
                publishEvent("app", "Activity stopped: ${activity.javaClass.simpleName}")
            }

            override fun onActivitySaveInstanceState(activity: Activity, outState: android.os.Bundle) = Unit

            override fun onActivityDestroyed(activity: Activity) {
                destroyedActivities.add(DestroyedActivity(activity.javaClass.name, SystemClock.elapsedRealtime(), WeakReference(activity)))
                while (destroyedActivities.size > 100) destroyedActivities.removeAt(0)
                if (foregroundActivity.get() === activity) {
                    debugOverlay?.detach()
                    debugOverlay = null
                    foregroundActivity.clear()
                }
                publishEvent("app", "Activity destroyed: ${activity.javaClass.simpleName}")
            }
        })
    }

    private fun installCrashHandler() {
        val original = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            val writer = StringWriter()
            error.printStackTrace(PrintWriter(writer))
            val record = "${timestamp()} · ${thread.name}\n${writer}"
            crashRecords.add(record)
            trim(crashRecords)
            appContext?.let { context ->
                runCatching { File(context.filesDir, "debugswift-crash-${System.currentTimeMillis()}.txt").writeText(record) }
            }
            appendAgentEntry(
                kind = "crash",
                location = thread.name,
                message = error.message ?: error.javaClass.name,
                data = mapOf("exception" to error.javaClass.name, "stackTrace" to writer.toString()),
                writeImmediately = true
            )
            publishEvent("app", "Uncaught ${error.javaClass.simpleName}")
            original?.uncaughtException(thread, error)
        }
    }

    private fun loadCrashHistory(context: Context) {
        context.filesDir.listFiles()
            ?.filter { it.isFile && it.name.startsWith("debugswift-crash-") }
            ?.sortedBy { it.lastModified() }
            ?.takeLast(20)
            ?.forEach { file ->
                runCatching { crashRecords.add(file.readText().take(256_000)) }
            }
        trim(crashRecords)
    }

    private fun startAnrWatchdog() {
        scheduler.scheduleAtFixedRate({
            val posted = SystemClock.uptimeMillis()
            mainHandler.post {
                val delay = SystemClock.uptimeMillis() - posted
                if (delay > MAIN_THREAD_STALL_MS) {
                    val event = "${timestamp()} main thread stalled for ${delay}ms\n${Thread.getAllStackTraces()[Looper.getMainLooper().thread]?.take(20)?.joinToString("\n") ?: "No stack available"}"
                    events.add(event)
                    trim(events)
                    Log.w(TAG, event)
                }
                val showWidget = synchronized(enabledTools) { "performance_widget" in enabledTools }
                if (showWidget) {
                    cpuUsagePercent = cpuUsage()
                    val currentFrames = frameCount
                    framesPerSecond = (currentFrames - previousFrameCount).coerceAtLeast(0)
                    previousFrameCount = currentFrames
                    debugOverlay?.invalidate()
                }
            }
        }, 1, 1, TimeUnit.SECONDS)
    }

    @Volatile private var frameCount = 0L
    @Volatile private var slowFrameCount = 0L
    @Volatile private var slowestFrameMs = 0L
    @Volatile private var lastFrameNanos = 0L
    @Volatile private var lastRecordingPath = ""
    @Volatile private var lastPalette: List<String> = emptyList()
    @Volatile private var composeRenderCount = 0L
    @Volatile private var cpuUsagePercent = 0.0
    @Volatile private var framesPerSecond = 0L
    private var previousFrameCount = 0L
    private var previousCpuTimeMs = 0L
    private var previousWallTimeMs = 0L

    fun recordComposeRender() {
        composeRenderCount++
    }

    @Synchronized private fun cpuUsage(currentCpuMs: Long = Process.getElapsedCpuTime()): Double {
        val now = SystemClock.elapsedRealtime()
        val elapsed = now - previousWallTimeMs
        val cpu = currentCpuMs - previousCpuTimeMs
        previousWallTimeMs = now
        previousCpuTimeMs = currentCpuMs
        if (elapsed <= 0L || cpu < 0L) return cpuUsagePercent
        return ((cpu.toDouble() / elapsed) * 100.0 / Runtime.getRuntime().availableProcessors()).coerceIn(0.0, 100.0)
    }

    private fun startFrameMonitor() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { startFrameMonitor() }
            return
        }
        Choreographer.getInstance().postFrameCallback(object : Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                if (lastFrameNanos != 0L) {
                    val intervalMs = (frameTimeNanos - lastFrameNanos) / 1_000_000L
                    frameCount++
                    if (intervalMs > 32) {
                        slowFrameCount++
                        slowestFrameMs = maxOf(slowestFrameMs, intervalMs)
                        slowFrameEvents.add("${timestamp()} · ${intervalMs}ms")
                        trim(slowFrameEvents)
                        if (slowFrameCount == 1L || slowFrameCount % 30L == 0L) publishEvent("performance", "Slow frame: ${intervalMs}ms")
                    }
                }
                lastFrameNanos = frameTimeNanos
                Choreographer.getInstance().postFrameCallback(this)
            }
        })
    }

    private fun updateOverlay() {
        val activity = foregroundActivity.get() ?: return
        activity.runOnUiThread {
            val enabled = synchronized(enabledTools) { enabledTools.any { it == "grid" || it == "touches" || it == "view_borders" || it == "performance_widget" } }
            val decor = activity.window.decorView as? ViewGroup ?: return@runOnUiThread
            val previous = debugOverlay
            previous?.detach()
            debugOverlay = if (enabled) DebugOverlay(activity).also { overlay ->
                overlay.attachTo(decor)
            } else null
        }
    }

    private class DebugOverlay(context: Context) : View(context) {
        private val gridPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = gridColor; strokeWidth = 1f }
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(90, 255, 90, 90); style = Paint.Style.STROKE; strokeWidth = 1f }
        private val touchPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(180, 255, 210, 60); style = Paint.Style.FILL }
        private val widgetBackgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(220, 24, 26, 32) }
        private val widgetTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = 13 * resources.displayMetrics.density
            typeface = android.graphics.Typeface.create("monospace", android.graphics.Typeface.NORMAL)
        }
        private val density = resources.displayMetrics.density
        private var observedDecor = WeakReference<ViewGroup>(null)
        private var globalLayoutListener: android.view.ViewTreeObserver.OnGlobalLayoutListener? = null

        fun attachTo(decor: ViewGroup) {
            observedDecor = WeakReference(decor)
            layout(0, 0, decor.width, decor.height)
            decor.overlay.add(this)
            val listener = android.view.ViewTreeObserver.OnGlobalLayoutListener {
                observedDecor.get()?.let { root -> layout(0, 0, root.width, root.height) }
            }
            globalLayoutListener = listener
            decor.viewTreeObserver.addOnGlobalLayoutListener(listener)
        }

        fun detach() {
            val decor = observedDecor.get()
            if (decor != null) {
                decor.overlay.remove(this)
                val listener = globalLayoutListener
                if (listener != null && decor.viewTreeObserver.isAlive) {
                    decor.viewTreeObserver.removeOnGlobalLayoutListener(listener)
                }
            }
            globalLayoutListener = null
            observedDecor.clear()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val active: Set<String> = synchronized(enabledTools) { enabledTools.toSet() }
            if ("grid" in active) {
                gridPaint.color = Color.argb(
                    (gridOpacity * 255).roundToInt().coerceIn(0, 255),
                    Color.red(gridColor),
                    Color.green(gridColor),
                    Color.blue(gridColor)
                )
                val spacing = (gridSpacingDp * density).coerceAtLeast(1f)
                var x = 0f
                while (x < width) { canvas.drawLine(x, 0f, x, height.toFloat(), gridPaint); x += spacing }
                var y = 0f
                while (y < height) { canvas.drawLine(0f, y, width.toFloat(), y, gridPaint); y += spacing }
            }
            if ("view_borders" in active) drawViewBorders(canvas, this)
            if ("touches" in active) recentTouches.forEach { (x, y) -> canvas.drawCircle(x, y, 8 * density, touchPaint) }
            if ("performance_widget" in active) {
                val runtime = Runtime.getRuntime()
                val used = runtime.totalMemory() - runtime.freeMemory()
                val lines = listOf(
                    "CPU ${"%.1f".format(cpuUsagePercent)}%",
                    "MEM ${formatBytes(used)}",
                    "FPS $framesPerSecond  ·  slow $slowFrameCount"
                )
                val left = 14 * density
                val top = 72 * density
                val padding = 10 * density
                val lineHeight = 18 * density
                val boxWidth = lines.maxOf { widgetTextPaint.measureText(it) } + padding * 2
                val boxHeight = lineHeight * lines.size + padding * 2
                canvas.drawRoundRect(left, top, left + boxWidth, top + boxHeight, 8 * density, 8 * density, widgetBackgroundPaint)
                lines.forEachIndexed { index, line ->
                    canvas.drawText(line, left + padding, top + padding + lineHeight * (index + 1), widgetTextPaint)
                }
            }
        }

        private fun drawViewBorders(canvas: Canvas, root: View) {
            fun walk(view: View) {
                if (view !== this@DebugOverlay && view.width > 0 && view.height > 0) {
                    val rect = Rect()
                    if (view.getGlobalVisibleRect(rect)) canvas.drawRect(rect, borderPaint)
                }
                if (view is ViewGroup) for (index in 0 until view.childCount) walk(view.getChildAt(index))
            }
            val activityRoot = (context as? Activity)?.window?.decorView
            if (activityRoot != null) walk(activityRoot)
        }
    }

    private fun captureScreenshot(annotateTouches: Boolean = false): String {
        val activity = foregroundActivity.get() ?: return "No active window is available."
        val view = activity.window.decorView
        if (view.width <= 0 || view.height <= 0) return "The active window has no layout yet."
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        view.draw(canvas)
        if (annotateTouches) {
            val interactions = recordedInteractions.takeLast(24)
            val markPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.RED; style = Paint.Style.FILL; strokeWidth = 4f }
            val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.RED; style = Paint.Style.STROKE; strokeWidth = 5f }
            val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 24f; textAlign = Paint.Align.CENTER; style = Paint.Style.FILL }
            interactions.forEachIndexed { index, interaction ->
                if (interaction.kind == "scroll") {
                    canvas.drawLine(interaction.startX, interaction.startY, interaction.endX, interaction.endY, linePaint)
                    val angle = atan2(interaction.endY - interaction.startY, interaction.endX - interaction.startX)
                    val headLength = 22f
                    val spread = (PI / 6).toFloat()
                    canvas.drawLine(interaction.endX, interaction.endY, interaction.endX - headLength * cos(angle - spread), interaction.endY - headLength * sin(angle - spread), linePaint)
                    canvas.drawLine(interaction.endX, interaction.endY, interaction.endX - headLength * cos(angle + spread), interaction.endY - headLength * sin(angle + spread), linePaint)
                    canvas.drawCircle(interaction.startX, interaction.startY, 15f, markPaint)
                    canvas.drawText((index + 1).toString(), interaction.startX, interaction.startY + 8f, labelPaint)
                } else {
                    canvas.drawCircle(interaction.endX, interaction.endY, 18f, markPaint)
                    canvas.drawText((index + 1).toString(), interaction.endX, interaction.endY + 8f, labelPaint)
                }
            }
        }
        val file = File(appContext!!.cacheDir, "debugswift-screen-${System.currentTimeMillis()}.png")
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        lastRecordingPath = file.absolutePath
        publishEvent("interface", "Screenshot saved: ${file.name}")
        bitmap.recycle()
        return "Screenshot saved to ${file.absolutePath}"
    }

    private fun capturePalette(): String {
        val activity = foregroundActivity.get() ?: return "No active window is available."
        val view = activity.window.decorView
        if (view.width <= 0 || view.height <= 0) return "The active window has no layout yet."
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(bitmap))
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        lastPalette = pixels.asSequence()
            .filter { Color.alpha(it) > 200 }
            .map { color -> Color.rgb(Color.red(color) / 16 * 16, Color.green(color) / 16 * 16, Color.blue(color) / 16 * 16) }
            .groupingBy { it }
            .eachCount()
            .entries
            .sortedByDescending { it.value }
            .take(12)
            .map { "#%06X · %d px".format(it.key and 0xFFFFFF, it.value) }
        bitmap.recycle()
        publishEvent("interface", "Sampled ${lastPalette.size} screen colors")
        return lastPalette.joinToString("\n").ifEmpty { "No opaque colors could be sampled." }
    }

    private fun sendLocalNotification(context: Context, value: String = ""): String {
        val parts = value.split("|", limit = 3)
        val title = parts.getOrNull(0)?.trim()?.takeIf { it.isNotEmpty() } ?: "DebugSwift test notification"
        val message = parts.getOrNull(1)?.trim()?.takeIf { it.isNotEmpty() } ?: "Local push simulation · ${timestamp()}"
        val delaySeconds = parts.getOrNull(2)?.trim()?.toLongOrNull() ?: 0L
        if (delaySeconds < 0) return "Delay must be zero or more seconds."
        val activity = foregroundActivity.get()
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            activity?.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 5081)
            return "Notification permission requested. Press Capture again after granting it."
        }
        val postNotification = {
            val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(message)
                .setAutoCancel(true)
                .build()
            NotificationManagerCompat.from(context).notify(System.currentTimeMillis().toInt(), notification)
            publishEvent("app", "Local test notification posted: $title")
        }
        if (delaySeconds == 0L) {
            postNotification()
            return "Local test notification posted."
        }
        mainHandler.postDelayed({ postNotification() }, delaySeconds.coerceAtMost(86_400L) * 1_000L)
        return "Local notification scheduled in ${delaySeconds.coerceAtMost(86_400L)} seconds."
    }

    private fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(NotificationChannel(NOTIFICATION_CHANNEL, "DebugSwift tests", NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    private fun deviceInfo(context: Context): String {
        val packageInfo = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getPackageInfo(context.packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION") context.packageManager.getPackageInfo(context.packageName, 0)
        }
        val display = context.resources.displayMetrics
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo().also(activityManager::getMemoryInfo)
        @Suppress("DEPRECATION")
        val versionCode = if (Build.VERSION.SDK_INT >= 28) packageInfo.longVersionCode else packageInfo.versionCode.toLong()
        return "App: ${context.packageName}\nVersion: ${packageInfo.versionName ?: "unknown"} ($versionCode)\nAndroid: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})\nDevice: ${Build.MANUFACTURER} ${Build.MODEL}\nHardware: ${Build.HARDWARE}\nDisplay: ${display.widthPixels} × ${display.heightPixels} @ ${display.densityDpi}dpi\nSystem memory: ${formatBytes(memoryInfo.totalMem)}"
    }

    private fun platformExitHistory(context: Context, reasonFilter: Int? = null): String {
        if (Build.VERSION.SDK_INT < 30) return "Android does not expose historical process exit details on this version."
        val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val exits = manager.getHistoricalProcessExitReasons(context.packageName, 0, 10)
            .filter { reasonFilter == null || it.reason == reasonFilter }
        return exits.joinToString("\n\n") { exit ->
            val reason = when (exit.reason) {
                android.app.ApplicationExitInfo.REASON_ANR -> "ANR"
                android.app.ApplicationExitInfo.REASON_CRASH -> "Java/Kotlin crash"
                android.app.ApplicationExitInfo.REASON_CRASH_NATIVE -> "Native crash"
                android.app.ApplicationExitInfo.REASON_LOW_MEMORY -> "Low memory"
                android.app.ApplicationExitInfo.REASON_USER_REQUESTED -> "User requested"
                else -> "Reason ${exit.reason}"
            }
            val trace = runCatching { exit.traceInputStream?.bufferedReader()?.use { it.readText().take(32_000) } }.getOrNull()
            "${Date(exit.timestamp)} · $reason · ${exit.status}\n${exit.description.orEmpty()}" +
                (trace?.takeIf { it.isNotBlank() }?.let { "\n$it" } ?: "")
        }.ifEmpty { "No matching process exit records reported by Android." }
    }

    private fun securityAudit(context: Context): String {
        val sensitiveName = Regex("password|secret|token|credential|api.?key|key", RegexOption.IGNORE_CASE)
        val criticalFindings = linkedSetOf<String>()
        val warningFindings = linkedSetOf<String>()

        val preferenceDirectory = File(context.applicationInfo.dataDir, "shared_prefs")
        val preferenceNames = (registeredPreferences + preferenceDirectory.listFiles()
            .orEmpty()
            .filter { it.isFile && it.extension.equals("xml", ignoreCase = true) }
            .map { it.nameWithoutExtension }).toSet()
        preferenceNames.forEach { name ->
            context.getSharedPreferences(name, Context.MODE_PRIVATE).all.forEach { (key, value) ->
                if (sensitiveName.containsMatchIn(key) && value is String && value.isNotEmpty()) {
                    warningFindings.add("User preferences · $name: $key — sensitive key has a non-empty string value")
                }
            }
        }

        val manifestMetadata = runCatching {
            context.packageManager.getApplicationInfo(
                context.packageName,
                android.content.pm.PackageManager.GET_META_DATA
            ).metaData
        }.getOrNull()
        manifestMetadata?.keySet()?.forEach { key ->
            val value = manifestMetadata.get(key)
            if (sensitiveName.containsMatchIn(key) && value is String && value.isNotEmpty()) {
                warningFindings.add("Manifest metadata · $key — sensitive key has a non-empty string value")
            }
        }

        val bundleFiles = linkedSetOf<String>()
        val apkPaths = mutableListOf(context.applicationInfo.sourceDir)
        context.applicationInfo.splitSourceDirs?.forEach(apkPaths::add)
        apkPaths.forEach { apkPath ->
            runCatching {
                ZipFile(apkPath).use { apk ->
                    apk.entries().asSequence()
                        .filter { entry ->
                            !entry.isDirectory && (entry.name.startsWith("assets/") || entry.name.startsWith("res/raw/"))
                        }
                        .forEach { bundleFiles.add(it.name) }
                }
            }
        }
        val credentialExtensions = setOf("cer", "p12", "mobileconfig", "pem", "key")
        bundleFiles.forEach { path ->
            if (credentialExtensions.contains(path.substringAfterLast('.', "").lowercase())) {
                criticalFindings.add("App bundle · $path — credential file is packaged with the app")
            }
        }

        var filesScanned = 0
        context.filesDir.walkTopDown().filter { it.isFile }.take(200).forEach { file ->
            if (file.length() > 256_000 || file.extension.lowercase() in setOf("db", "sqlite", "png", "jpg", "jpeg", "webp", "zip", "so")) return@forEach
            filesScanned++
            if (sensitiveName.containsMatchIn(file.name)) {
                warningFindings.add("Private file · ${file.relativeTo(context.filesDir).path} — sensitive-looking filename")
            }
            val content = runCatching { file.readText() }.getOrNull() ?: return@forEach
            if ('\u0000' in content) return@forEach
            Regex("(password|secret|token|credential|private.?key)[\\\"']?\\s*[:=]", RegexOption.IGNORE_CASE)
                .findAll(content).take(20).forEach { match ->
                    warningFindings.add("Private file · ${file.relativeTo(context.filesDir).path} — ${match.groupValues[1]} assignment")
                }
        }

        val keyStorePolicies = runCatching {
            val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            store.aliases().toList().mapNotNull { alias ->
                val key = runCatching { store.getKey(alias, null) }.getOrNull() ?: return@mapNotNull null
                val keySpec = when (key) {
                    is SecretKey -> runCatching {
                        SecretKeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
                            .getKeySpec(key, KeyInfo::class.java)
                    }.getOrNull()
                    is PrivateKey -> runCatching {
                        KeyFactory.getInstance(key.algorithm, "AndroidKeyStore")
                            .getKeySpec(key, KeyInfo::class.java)
                    }.getOrNull()
                    else -> null
                }
                alias to (keySpec as? KeyInfo)
            }
        }.getOrDefault(emptyList())
        val keyStoreFindings = keyStorePolicies.mapNotNull { (alias, info) ->
            if (info != null && !info.isUserAuthenticationRequired()) {
                "Android Keystore · $alias — key use does not require user authentication"
            } else {
                null
            }
        }
        val count = criticalFindings.size + warningFindings.size + keyStoreFindings.size
        return "Potentially sensitive references: $count\n\n" +
            "Critical (${criticalFindings.size})\n" + criticalFindings.take(100).joinToString("\n").ifEmpty { "No credential files found in the app bundle." } +
            "\n\nWarning (${warningFindings.size})\n" + warningFindings.take(100).joinToString("\n").ifEmpty { "No sensitive keys or assignments found in scanned preferences, manifest metadata, or private text files." } +
            "\n\nInfo (${keyStoreFindings.size})\n" + keyStoreFindings.take(100).joinToString("\n").ifEmpty { "No Android Keystore keys without user-authentication requirements were reported." } +
            "\n\nScanned: ${preferenceNames.size} preference stores, ${manifestMetadata?.size() ?: 0} manifest metadata entries, ${bundleFiles.size} bundled files, $filesScanned private text files, and ${keyStorePolicies.size} Android Keystore key policies.\n" +
            "The audit reports key names and file paths only; it never displays matched values."
    }

    private fun writePreference(context: Context, value: String): String {
        val parts = value.split("|", limit = 2)
        if (parts.size != 2) return "Enter preferenceStore|key=value."
        val assignment = parts[1].split("=", limit = 2)
        if (assignment.size != 2 || assignment[0].isBlank()) return "Enter preferenceStore|key=value."
        val storeName = parts[0].trim()
        if (storeName.isBlank() || storeName == PREFS) return "Choose a registered host preference store."
        if (storeName !in registeredPreferences) return "Register '$storeName' with AndroidDebugTools.registerPreferences(name) before editing it."
        val store = context.getSharedPreferences(storeName, Context.MODE_PRIVATE)
        val key = assignment[0].trim()
        val rawValue = assignment[1]
        val current = store.all[key]
        val editor = store.edit()
        when (current) {
            is Boolean -> editor.putBoolean(key, rawValue.toBooleanStrictOrNull() ?: return "'$key' is a Boolean preference; enter true or false.")
            is Int -> editor.putInt(key, rawValue.toIntOrNull() ?: return "'$key' is an integer preference; enter a whole number.")
            is Long -> editor.putLong(key, rawValue.toLongOrNull() ?: return "'$key' is a long integer preference; enter a whole number.")
            is Float -> editor.putFloat(key, rawValue.toFloatOrNull() ?: return "'$key' is a numeric preference; enter a number.")
            is Set<*> -> editor.putStringSet(key, rawValue.split(',').map { it.trim() }.toMutableSet())
            is String -> editor.putString(key, rawValue)
            else -> when {
                rawValue.equals("true", ignoreCase = true) || rawValue.equals("false", ignoreCase = true) -> editor.putBoolean(key, rawValue.toBoolean())
                rawValue.toIntOrNull() != null -> editor.putInt(key, rawValue.toInt())
                rawValue.toLongOrNull() != null -> editor.putLong(key, rawValue.toLong())
                else -> editor.putString(key, rawValue)
            }
        }
        editor.apply()
        publishEvent("resources", "Preference updated: $storeName.$key")
        return "Preference updated."
    }

    private fun listFiles(directory: File): String = directory.listFiles()?.sortedBy { it.name }?.take(100)?.joinToString("\n") {
        val suffix = if (it.isDirectory) "/" else " (${formatBytes(it.length())})"
        it.name + suffix
    }?.ifEmpty { "empty" } ?: "unavailable"

    private fun browseFiles(context: Context, path: String): String {
        val normalized = path.trim().trimStart('/')
        val rootName = normalized.substringBefore('/').ifEmpty { "files" }
        val root = when (rootName) {
            "files" -> context.filesDir
            "cache" -> context.cacheDir
            "databases" -> File(context.applicationInfo.dataDir, "databases")
            else -> return "Choose an app-private root: files/, cache/, or databases/."
        }.canonicalFile
        val relative = normalized.substringAfter('/', "")
        val target = File(root, relative).canonicalFile
        if (target != root && !target.path.startsWith(root.path + File.separator)) {
            return "The file browser is limited to the app's private files, cache, and databases."
        }
        currentFilePath = if (relative.isEmpty()) rootName else "$rootName/$relative"
        if (target.isDirectory) {
            val children = target.listFiles()?.sortedWith(compareBy<File> { !it.isDirectory }.thenBy { it.name })
                ?.take(200)?.joinToString("\n") { file ->
                    val kind = if (file.isDirectory) "DIR" else "FILE"
                    val size = if (file.isFile) " · ${formatBytes(file.length())}" else ""
                    "$kind  ${file.name}$size"
                }.orEmpty()
            return "Path: $currentFilePath\nEnter a child path above and choose Open path to browse it.\n\n${children.ifEmpty { "This directory is empty or unreadable." }}"
        }
        if (!target.isFile) return "Path not found: $currentFilePath"
        if (target.length() > 1_000_000) return "File is ${formatBytes(target.length())}; preview is limited to 1 MB."
        val preview = runCatching { target.readText().take(64_000) }.getOrElse { "Text preview unavailable: ${it.message}" }
        return "Path: $currentFilePath · ${formatBytes(target.length())}\n\n$preview"
    }

    private fun exportCurrentFile(context: Context): File? {
        val path = currentFilePath.trim().trimStart('/')
        val rootName = path.substringBefore('/').ifEmpty { "files" }
        val root = when (rootName) {
            "files" -> context.filesDir
            "cache" -> context.cacheDir
            "databases" -> File(context.applicationInfo.dataDir, "databases")
            else -> return null
        }.canonicalFile
        val source = File(root, path.substringAfter('/', "")).canonicalFile
        if (source != root && !source.path.startsWith(root.path + File.separator)) return null
        if (source.isDirectory) {
            return File(context.cacheDir, "debugswift-files-${System.currentTimeMillis()}.txt").apply {
                writeText(browseFiles(context, path))
            }
        }
        if (!source.isFile) return null
        val destination = File(context.cacheDir, "debugswift-export-${source.name}")
        return runCatching { source.copyTo(destination, overwrite = true) }.getOrNull()
    }

    private fun describeView(view: View, depth: Int, output: StringBuilder) {
        if (depth > 12 || output.length > 40_000) return
        val rect = Rect()
        view.getGlobalVisibleRect(rect)
        output.append("  ".repeat(depth))
            .append(view.javaClass.simpleName)
            .append(" [${rect.left},${rect.top} ${rect.width()}×${rect.height()}]")
        if (view.id != View.NO_ID) {
            val id = runCatching { view.resources.getResourceEntryName(view.id) }.getOrNull()
            if (id != null) output.append(" id=").append(id)
        }
        if (view.contentDescription != null) output.append(" label=").append(view.contentDescription)
        output.append('\n')
        if (view is ViewGroup) for (index in 0 until view.childCount) describeView(view.getChildAt(index), depth + 1, output)
    }

    private var previousThreadPolicy: android.os.StrictMode.ThreadPolicy? = null
    private var previousVmPolicy: android.os.StrictMode.VmPolicy? = null

    private fun enableStrictMode() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { enableStrictMode() }
            return
        }
        if (previousThreadPolicy == null) previousThreadPolicy = android.os.StrictMode.getThreadPolicy()
        if (previousVmPolicy == null) previousVmPolicy = android.os.StrictMode.getVmPolicy()
        val threadPolicy = android.os.StrictMode.ThreadPolicy.Builder()
                .detectAll()
        if (Build.VERSION.SDK_INT >= 28) {
            threadPolicy.penaltyListener(java.util.concurrent.Executor { command -> mainHandler.post(command) }) { violation ->
                val detail = "${timestamp()} ${violation.javaClass.simpleName}\n${violation.stackTraceToString()}"
                threadViolations.add(detail)
                trim(threadViolations)
                publishEvent("performance", "StrictMode ${violation.javaClass.simpleName}")
            }
        } else {
            threadPolicy.penaltyLog()
        }
        android.os.StrictMode.setThreadPolicy(threadPolicy.build())
        val vmPolicy = android.os.StrictMode.VmPolicy.Builder().detectAll()
        if (Build.VERSION.SDK_INT >= 28) {
            vmPolicy.penaltyListener(java.util.concurrent.Executor { command -> mainHandler.post(command) }) { violation ->
                val detail = "${timestamp()} VM ${violation.javaClass.simpleName}\n${violation.stackTraceToString()}"
                threadViolations.add(detail)
                trim(threadViolations)
                publishEvent("performance", "StrictMode VM ${violation.javaClass.simpleName}")
            }
        } else {
            vmPolicy.penaltyLog()
        }
        android.os.StrictMode.setVmPolicy(vmPolicy.build())
    }

    private fun disableStrictMode() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { disableStrictMode() }
            return
        }
        android.os.StrictMode.setThreadPolicy(previousThreadPolicy ?: android.os.StrictMode.ThreadPolicy.LAX)
        android.os.StrictMode.setVmPolicy(previousVmPolicy ?: android.os.StrictMode.VmPolicy.LAX)
        previousThreadPolicy = null
        previousVmPolicy = null
    }

    private fun clearInjectionRules() {
        requestDelayMs = 0L
        httpErrorCode = 0
        failNextRequest.set(false)
        responseRewrites.clear()
        blockedURLPatterns.clear()
    }

    private fun publishEvent(domain: String, message: String) {
        val eventTimestamp = System.currentTimeMillis()
        events.add("${timestamp()} [$domain] $message")
        trim(events)
        val kind = when {
            domain == "network" -> "network"
            message.startsWith("Activity ") || message.startsWith("Intent ") -> "lifecycle"
            else -> "event"
        }
        appendAgentEntry(
            kind = kind,
            location = domain,
            message = message,
            data = mapOf("domain" to domain),
            timestampMs = eventTimestamp
        )
    }

    private fun agentDebugLogSnapshot(context: Context): String {
        val file = File(context.filesDir, AGENT_LOG_FILENAME)
        val recentEntries = runCatching { file.readLines(Charsets.UTF_8).takeLast(20) }.getOrDefault(emptyList())
        return "Capture: ${if (agentLogEnabled) "ON" else "OFF"}\n" +
            "Session: $agentLogSessionID\n" +
            "Path: ${file.absolutePath}\n" +
            "Size: ${formatBytes(file.length())}\n" +
            "Recent entries:\n" + recentEntries.joinToString("\n").ifEmpty { "No records yet. Enable capture to collect events." }
    }

    private fun appendAgentEntry(
        kind: String,
        location: String,
        message: String,
        data: Map<String, Any?> = emptyMap(),
        timestampMs: Long = System.currentTimeMillis(),
        writeImmediately: Boolean = false
    ) {
        if (!agentLogEnabled) return
        val context = appContext ?: return
        val payload = org.json.JSONObject()
            .put("sessionId", agentLogSessionID)
            .put("location", location)
            .put("message", message.take(16_000))
            .put("kind", kind)
            .put("hypothesisId", "")
            .put("runId", "debugswift-android")
            .put("timestamp", timestampMs)
        if (data.isNotEmpty()) {
            val dataJSON = org.json.JSONObject()
            data.forEach { (key, value) -> dataJSON.put(key, value) }
            payload.put("data", dataJSON)
        }
        val line = payload.toString() + "\n"
        val writeRecord = {
            runCatching {
                val file = File(context.filesDir, AGENT_LOG_FILENAME)
                if (file.length() + line.toByteArray(Charsets.UTF_8).size > MAX_AGENT_LOG_BYTES) {
                    val previous = File(context.filesDir, "$AGENT_LOG_FILENAME.previous")
                    previous.delete()
                    file.renameTo(previous)
                }
                file.appendText(line, Charsets.UTF_8)
            }
        }
        if (writeImmediately) writeRecord() else persistenceExecutor.execute { writeRecord() }
    }

    private fun graphqlOperation(body: String): String {
        if (body.isBlank()) return ""
        val name = Regex("\"operationName\"\\s*:\\s*\"([^\"]+)\"").find(body)?.groupValues?.getOrNull(1)
        if (name != null) return name
        val operation = Regex("\\b(query|mutation|subscription)\\s+([A-Za-z_][A-Za-z0-9_]*)").find(body)
        return operation?.let { "${it.groupValues[1]} ${it.groupValues[2]}" }.orEmpty()
    }

    private fun safeValue(value: Any?): String = when (value) {
        is String -> if (value.length > 200) value.take(200) + "…" else value
        is Set<*> -> value.joinToString()
        else -> value.toString()
    }

    private fun formatBytes(bytes: Long): String = when {
        bytes >= 1_000_000_000 -> "%.2f GB".format(bytes / 1_000_000_000.0)
        bytes >= 1_000_000 -> "%.2f MB".format(bytes / 1_000_000.0)
        bytes >= 1_000 -> "%.1f KB".format(bytes / 1_000.0)
        else -> "$bytes B"
    }

    private fun timestamp(): String = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault()).format(Date())

    private fun priorityName(priority: Int): String = when (priority) {
        Log.ERROR -> "ERROR"
        Log.WARN -> "WARN"
        Log.INFO -> "INFO"
        Log.DEBUG -> "DEBUG"
        Log.VERBOSE -> "TRACE"
        else -> "LOG"
    }

    private fun <T> trim(records: CopyOnWriteArrayList<T>) {
        while (records.size > MAX_RECORDS) records.removeAt(0)
    }

    @Volatile private var lastIntentDescription = ""

    fun reportIntent(intent: Intent?) {
        lastIntentDescription = intent?.data?.toString() ?: intent?.action ?: "No URI or action on the last intent."
        publishEvent("app", "Intent received: $lastIntentDescription")
    }
}

/** Shared request injection configuration for host OkHttp clients. */
object DebugSwiftNetworkConfig {
    val decryptors = CopyOnWriteArrayList<String>()
    private val encryptionKeys = mutableMapOf<String, SecretKey>()

    fun registerAESKey(urlPattern: String, encodedKey: ByteArray): Boolean {
        if (encodedKey.size !in listOf(16, 24, 32)) {
            AndroidDebugTools.log("AES key for '$urlPattern' must contain 16, 24, or 32 bytes", Log.ERROR)
            return false
        }
        runCatching { Regex(urlPattern) }.onFailure {
            AndroidDebugTools.log("Invalid URL pattern '$urlPattern': ${it.message}", Log.ERROR)
            return false
        }
        synchronized(encryptionKeys) {
            encryptionKeys[urlPattern] = SecretKeySpec(encodedKey.copyOf(), "AES")
        }
        if (urlPattern !in decryptors) decryptors.add(urlPattern)
        return true
    }

    fun clearAESKeys() {
        synchronized(encryptionKeys) { encryptionKeys.clear() }
        decryptors.clear()
    }

    fun decryptResponse(url: String, encodedBody: String): String? {
        val encrypted = runCatching {
            android.util.Base64.decode(encodedBody.trim(), android.util.Base64.DEFAULT)
        }.getOrNull() ?: return null
        if (encrypted.size <= 12) return null
        val matchingPatterns = synchronized(encryptionKeys) {
            encryptionKeys.keys.filter { pattern -> runCatching { Regex(pattern).containsMatchIn(url) }.getOrDefault(false) }
        }
        for (pattern in matchingPatterns) {
            val cleartext = decryptAESGCM(pattern, encrypted.copyOfRange(0, 12), encrypted.copyOfRange(12, encrypted.size))
            if (cleartext != null) return cleartext.toString(Charsets.UTF_8)
        }
        return null
    }

    fun decryptAESGCM(urlPattern: String, nonce: ByteArray, ciphertext: ByteArray): ByteArray? {
        val key = synchronized(encryptionKeys) { encryptionKeys[urlPattern] } ?: return null
        return runCatching {
            val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(javax.crypto.Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, nonce))
            cipher.doFinal(ciphertext)
        }.getOrNull()
    }
}
