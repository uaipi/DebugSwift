package debug.swift.android

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ClipData
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
import android.net.Uri
import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.MimeTypeMap
import android.security.keystore.KeyInfo
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
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
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONArray
import org.json.JSONObject
import okhttp3.WebSocket
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
    private const val MAX_WEBSOCKET_CONNECTIONS = 200
    private const val MAX_WEBSOCKET_FRAMES = 1000
    private const val MAIN_THREAD_STALL_MS = 700L
    private const val NOTIFICATION_CHANNEL = "debugswift_local_tests"
    private const val PUSH_HISTORY_PAGE_SIZE = 20
    private const val PUSH_STATE_PREFS = "DebugSwift.PushNotifications"
    private const val THRESHOLD_STATE_PREFS = "DebugSwift.NetworkThreshold"
    private const val PUSH_NOTIFICATION_ID_EXTRA = "debugswift_notification_id"
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
    private val webSocketConnections = CopyOnWriteArrayList<WebSocketConnectionRecord>()
    private val webSocketByInstance = ConcurrentHashMap<WebSocket, String>()
    private val activeWebSockets = ConcurrentHashMap<String, WebSocket>()
    private val legacyWebSocketIDs = ConcurrentHashMap<String, String>()
    @Volatile private var selectedWebSocketConnectionID = ""
    @Volatile private var selectedWebSocketFrameID = ""
    @Volatile private var webSocketFilter = ""
    @Volatile private var webSocketDirectionFilter = ""
    private val consoleRecords = CopyOnWriteArrayList<String>()
    private val crashRecords = CopyOnWriteArrayList<String>()
    private val backtraces = CopyOnWriteArrayList<String>()
    private val threadViolations = CopyOnWriteArrayList<String>()
    private val events = CopyOnWriteArrayList<String>()
    private val slowFrameEvents = CopyOnWriteArrayList<String>()
    private val recentTouches = CopyOnWriteArrayList<Pair<Float, Float>>()
    private val recordedInteractions = CopyOnWriteArrayList<RecordedInteraction>()
    private val pushHistory = CopyOnWriteArrayList<PushNotificationRecord>()
    private val pushTemplates = CopyOnWriteArrayList<PushNotificationTemplate>()
    private val pendingPushNotifications = ConcurrentHashMap<String, ScheduledFuture<*>>()
    private val notificationExecutor = Executors.newSingleThreadScheduledExecutor { task ->
        Thread(task, "DebugSwiftNotifications").apply { isDaemon = true }
    }
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
    @Volatile private var pushStateLoaded = false
    @Volatile private var pushEnabled = false
    @Volatile private var pushShowInForeground = true
    @Volatile private var pushPlaySound = true
    @Volatile private var pushShowBadge = true
    @Volatile private var pushAutoInteraction = false
    @Volatile private var pushInteractionDelaySeconds = 3.0
    @Volatile private var pushSimulateRealPush = false
    @Volatile private var pushDefaultSound = "default"
    @Volatile private var pushMaxHistoryCount = 100
    @Volatile private var appInForeground = false
    @Volatile private var pushHistoryPage = 1
    @Volatile private var androidNotificationsEnabled = true
    @Volatile private var androidNotificationSettingsLoaded = false
    @Volatile private var thresholdTrackingEnabled = false
    private var thresholdLimit = 1000
    private var thresholdWindowMs = 60_000L
    private var thresholdStartMs = 0L
    private var thresholdCount = 0
    @Volatile private var thresholdBlockRequests = false
    @Volatile private var thresholdAlertEmoji = "⚠️"
    @Volatile private var thresholdAlertMessage = "Request limit exceeded!"
    private data class EndpointThresholdLimit(val limit: Int, val windowMs: Long)
    private data class EndpointThresholdCount(val timestamps: java.util.ArrayDeque<Long> = java.util.ArrayDeque())
    private data class ThresholdBreachRecord(
        val timestampMs: Long,
        val requestCount: Int,
        val limit: Int,
        val endpoint: String,
        val message: String
    )
    private val endpointThresholdLimits = ConcurrentHashMap<String, EndpointThresholdLimit>()
    private val endpointThresholdCounts = ConcurrentHashMap<String, EndpointThresholdCount>()
    private val thresholdRequestTimes = java.util.ArrayDeque<Long>()
    private val thresholdBreaches = CopyOnWriteArrayList<ThresholdBreachRecord>()
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

    private class WebSocketConnectionRecord(
        val id: String,
        val url: String,
        val createdAtMs: Long = System.currentTimeMillis()
    ) {
        @Volatile var status: String = "Connecting"
        @Volatile var statusDetail: String = ""
        @Volatile var lastActivityAtMs: Long = createdAtMs
        val unreadFrameCount = AtomicInteger(0)
        val frames = CopyOnWriteArrayList<WebSocketFrameRecord>()

        fun isActive(): Boolean = status == "Connecting" || status == "Connected" || status == "Closing"
    }

    private data class WebSocketFrameRecord(
        val id: String,
        val timestampMs: Long,
        val direction: String,
        val type: String,
        val payload: ByteArray
    )

    private data class PushNotificationRecord(
        val id: String,
        val title: String,
        val body: String,
        val subtitle: String?,
        val badge: Int?,
        val sound: String?,
        val category: String?,
        val userInfo: Map<String, String>,
        val scheduledAtMs: Long,
        val deliveryAtMs: Long?,
        val status: String,
        val trigger: String,
        val interactionType: String?
    )

    private data class PushNotificationTemplate(
        val id: String,
        val name: String,
        val title: String,
        val body: String,
        val subtitle: String?,
        val badge: Int?,
        val sound: String?,
        val category: String?,
        val userInfo: Map<String, String>,
        val isDefault: Boolean
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
        loadThresholdSettings(applicationContext)
        loadPushState(applicationContext)
        restoreAppearanceOverride(applicationContext)
        loadNetworkHistory(applicationContext)
        loadCrashHistory(applicationContext)
        registerLifecycleCallbacks(applicationContext)
        installCrashHandler()
        startAnrWatchdog()
        startFrameMonitor()
        notificationExecutor.execute { ensureNotificationChannel(applicationContext) }
        refreshNotificationSettings(applicationContext)
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

    @JvmStatic
    fun setPushSimulationEnabled(enabled: Boolean): String {
        val context = appContext ?: return "Android runtime has not been installed."
        if (pushEnabled == enabled) return "Push notification simulation is already ${if (enabled) "enabled" else "disabled"}."
        return togglePushSimulation(context)
    }

    @JvmStatic
    fun isPushSimulationEnabled(): Boolean = pushEnabled

    @JvmStatic
    fun simulatePushNotification(
        title: String,
        body: String,
        delaySeconds: Long = 0,
        subtitle: String? = null,
        badge: Int? = null,
        sound: String? = null,
        category: String? = null,
        userInfo: Map<String, String> = emptyMap()
    ): String {
        val context = appContext ?: return "Android runtime has not been installed."
        return schedulePushNotification(context, title, body, delaySeconds, subtitle, badge, sound, category, userInfo)
    }

    @JvmStatic
    fun simulateMessagePush(sender: String, message: String): String =
        simulatePushNotification("New Message", message, subtitle = "From $sender", userInfo = mapOf("type" to "message", "sender" to sender))

    @JvmStatic
    fun simulateReminderPush(task: String, delaySeconds: Long = 0): String =
        simulatePushNotification("Reminder", "Don't forget: $task", delaySeconds, badge = 1, userInfo = mapOf("type" to "reminder", "task" to task))

    @JvmStatic
    fun simulateNewsPush(headline: String, category: String = "General"): String =
        simulatePushNotification("Breaking News", headline, subtitle = category, userInfo = mapOf("type" to "news", "category" to category))

    @JvmStatic
    fun simulateMarketingPush(title: String, offer: String, discount: String? = null): String {
        val info = mutableMapOf("type" to "marketing", "offer" to offer)
        if (discount != null) info["discount"] = discount
        return simulatePushNotification(title, offer, subtitle = discount?.let { "$it% off" }, badge = 1, userInfo = info)
    }

    @JvmStatic
    fun simulatePushNotificationFromTemplate(name: String, delaySeconds: Long = 0): String {
        val context = appContext ?: return "Android runtime has not been installed."
        return simulatePushTemplate(context, "$name|$delaySeconds")
    }

    @JvmStatic
    fun runPushNotificationScenario(name: String): String {
        val context = appContext ?: return "Android runtime has not been installed."
        return runPushScenario(context, name)
    }

    @JvmStatic
    fun updatePushNotificationSetting(name: String, value: String): String {
        val context = appContext ?: return "Android runtime has not been installed."
        return setPushConfiguration(context, "$name=$value")
    }

    @JvmStatic
    fun addPushNotificationTemplate(
        name: String,
        title: String,
        body: String,
        subtitle: String? = null,
        badge: Int? = null,
        sound: String? = null,
        category: String? = null,
        userInfo: Map<String, String> = emptyMap()
    ): String {
        val context = appContext ?: return "Android runtime has not been installed."
        if (name.isBlank() || title.isBlank() || body.isBlank()) return "Template name, title, and body cannot be empty."
        return storePushTemplate(context, PushNotificationTemplate(UUID.randomUUID().toString(), name, title, body, subtitle, badge, sound, category, userInfo, false))
    }

    @JvmStatic
    fun removePushNotificationTemplate(name: String): String {
        val context = appContext ?: return "Android runtime has not been installed."
        return removePushTemplate(context, name)
    }

    @JvmStatic
    fun clearPushNotificationHistory(): String = clearPushHistory()

    @JvmStatic
    fun removeSimulatedPushNotification(id: String): String {
        val context = appContext ?: return "Android runtime has not been installed."
        return removePushNotification(context, id)
    }

    @JvmStatic
    fun simulatePushNotificationInteraction(id: String): String {
        val context = appContext ?: return "Android runtime has not been installed."
        return interactWithPushNotification(context, id)
    }

    @JvmStatic
    fun simulateForegroundPushNotification(id: String): String {
        if (pushHistory.none { it.id == id }) return "No simulated notification with ID '$id'."
        publishEvent("app", "Simulated foreground notification: $id")
        return "Foreground notification simulation recorded for $id."
    }

    @JvmStatic
    fun simulateBackgroundPushNotification(id: String): String {
        val context = appContext ?: return "Android runtime has not been installed."
        if (pushHistory.none { it.id == id }) return "No simulated notification with ID '$id'."
        updatePushNotification(context, id, "Delivered")
        publishEvent("app", "Simulated background notification: $id")
        return "Background notification simulation recorded for $id."
    }

    @JvmStatic
    fun pushNotificationSnapshot(): String {
        val context = appContext ?: return "Android runtime has not been installed."
        return pushNotificationSnapshot(context)
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
            "files", "preferences", "keychain", "persistent_data", "sqlite", "realm", "core_data", "swift_data", "cookies", "security_audit" -> resourcesSnapshot(context, featureID)
            "crashes", "console", "oslog_console", "device_info", "push_token", "push_simulator", "custom_actions", "custom_info", "deep_links", "loaded_libraries", "location", "event_bus", "agent_debug_log" -> appSnapshot(context, featureID)
            else -> "Unknown DebugSwift tool: $featureID"
        }
    }

    fun perform(featureID: String, actionID: String, value: String = ""): String {
        val context = appContext ?: return "Android runtime has not been installed."
        return when (actionID) {
            "clear" -> clear(featureID)
            "clear_push_history" -> if (value.trim() == "CLEAR") clearPushHistory() else "Type CLEAR to remove notification history."
            "capture" -> capture(featureID)
            "toggle" -> if (featureID == "dark_mode") toggleDarkMode(context) else toggle(featureID)
            "export" -> export(featureID, context)
            "notify" -> sendLocalNotification(context, value)
            "simulate_template" -> simulatePushTemplate(context, value)
            "run_scenario" -> runPushScenario(context, value)
            "set_notification_config" -> setPushConfiguration(context, value)
            "add_template" -> addPushTemplate(context, value)
            "remove_template" -> removePushTemplate(context, value)
            "remove_notification" -> removePushNotification(context, value)
            "interact_notification" -> interactWithPushNotification(context, value)
            "resend_notification" -> resendPushNotification(context, value)
            "delete_console_entry" -> {
                val index = value.toIntOrNull()
                if (featureID != "console" || index == null || index !in consoleRecords.indices) {
                    "Console entry no longer exists."
                } else {
                    consoleRecords.removeAt(index)
                    "Console entry removed."
                }
            }
            "history_page" -> showPushHistoryPage(context, value)
            "open_notification_settings" -> openNotificationSettings(context)
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
            "set_threshold_tracking" -> value.toBooleanStrictOrNull()?.let {
                setRequestTracking(it)
                "Request tracking ${if (it) "enabled" else "disabled"}."
            } ?: "Set request tracking to true or false."
            "set_threshold_blocking" -> value.toBooleanStrictOrNull()?.let {
                setThresholdBlocking(it)
                "Request blocking ${if (it) "enabled" else "disabled"}."
            } ?: "Set request blocking to true or false."
            "clear_threshold_history" -> clearThresholdHistory()
            "filter_requests" -> {
                networkFilter = value.trim()
                networkSnapshot(featureID)
            }
            "select_request" -> selectNetworkRequest(featureID, value)
            "filter_websockets" -> {
                webSocketFilter = value.trim()
                selectedWebSocketFrameID = ""
                webSocketSnapshot()
            }
            "select_connection" -> selectWebSocketConnection(value)
            "select_frame" -> selectWebSocketFrame(value)
            "filter_sent" -> { webSocketDirectionFilter = "Sent"; selectedWebSocketFrameID = ""; webSocketSnapshot() }
            "filter_received" -> { webSocketDirectionFilter = "Received"; selectedWebSocketFrameID = ""; webSocketSnapshot() }
            "filter_all_frames" -> { webSocketDirectionFilter = ""; selectedWebSocketFrameID = ""; webSocketSnapshot() }
            "copy_url" -> copyWebSocketURL(context)
            "copy_payload" -> copyWebSocketPayload(context)
            "close_connection" -> closeSelectedWebSocketConnection()
            "clear_frames" -> clearSelectedWebSocketFrames()
            "back_connections" -> {
                selectedWebSocketConnectionID = ""
                selectedWebSocketFrameID = ""
                webSocketDirectionFilter = ""
                webSocketSnapshot()
            }
            "send_frame" -> sendWebSocketFrame(value, resendSelected = false)
            "resend_frame" -> sendWebSocketFrame(value, resendSelected = true)
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
            "delete_preference" -> deletePreference(context, value)
            "clear_preferences" -> clearPreferenceStore(context, value)
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
            "copy_token" -> copyPushToken(context)
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
        recordThresholdRequest(url)
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
            thresholdLimit = limit.coerceIn(1, 1000)
            thresholdWindowMs = windowSeconds.coerceAtLeast(1) * 1000L
            thresholdCount = thresholdRequestTimes.count { SystemClock.elapsedRealtime() - it <= thresholdWindowMs }
        }
        persistThresholdSettings()
    }

    @JvmStatic
    fun setRequestTracking(enabled: Boolean) {
        synchronized(this) {
            thresholdTrackingEnabled = enabled
            thresholdStartMs = SystemClock.elapsedRealtime()
            thresholdCount = 0
            endpointThresholdCounts.clear()
            thresholdRequestTimes.clear()
        }
        persistThresholdSettings()
    }

    @JvmStatic
    fun setThresholdBlocking(enabled: Boolean) {
        thresholdBlockRequests = enabled
        persistThresholdSettings()
    }

    @JvmStatic
    fun setThresholdAlert(emoji: String, message: String) {
        thresholdAlertEmoji = emoji
        thresholdAlertMessage = message
        persistThresholdSettings()
    }

    @JvmStatic
    fun setEndpointRequestThreshold(endpoint: String, limit: Int, windowSeconds: Int) {
        if (endpoint.isBlank() || limit <= 0 || windowSeconds <= 0) return
        endpointThresholdLimits[endpoint] = EndpointThresholdLimit(limit, windowSeconds * 1000L)
        persistThresholdSettings()
    }

    @JvmStatic
    fun removeEndpointRequestThreshold(endpoint: String) {
        endpointThresholdLimits.remove(endpoint)
        endpointThresholdCounts.remove(endpoint)
        persistThresholdSettings()
    }

    @JvmStatic
    fun clearThresholdHistory(): String {
        synchronized(this) {
            thresholdStartMs = SystemClock.elapsedRealtime()
            thresholdCount = 0
            endpointThresholdCounts.clear()
            thresholdRequestTimes.clear()
        }
        thresholdBreaches.clear()
        publishEvent("network", "Request threshold history cleared")
        return "Request threshold history cleared."
    }

    private fun thresholdSnapshot(): String {
        val state = synchronized(this) {
            val now = SystemClock.elapsedRealtime()
            val count = if (thresholdTrackingEnabled) thresholdRequestTimes.count { now - it <= thresholdWindowMs } else 0
            thresholdCount = count
            listOf(thresholdTrackingEnabled, thresholdLimit, thresholdWindowMs / 1000L, thresholdBlockRequests, count, thresholdBreaches.size)
        }
        val endpoints = endpointThresholdLimits.entries.sortedBy { it.key }.joinToString("\n") { (endpoint, config) ->
            "$endpoint — ${config.limit} per ${config.windowMs / 1000L}s"
        }.ifEmpty { "No endpoint limits configured." }
        val breaches = thresholdBreaches.takeLast(5).asReversed().joinToString("\n") { breach ->
            "${Date(breach.timestampMs)} · ${breach.message}"
        }.ifEmpty { "No threshold breaches." }
        return "threshold|${state[0]}|${state[1]}|${state[2]}|${state[3]}|${state[4]}|${state[5]}\n" +
            "ENDPOINT LIMITS\n$endpoints\n\nRECENT BREACHES\n$breaches"
    }

    @JvmStatic
    fun getCurrentRequestCount(endpoint: String? = null): Int = synchronized(this) {
        val now = SystemClock.elapsedRealtime()
        val window = endpoint?.let { endpointThresholdLimits[it]?.windowMs } ?: thresholdWindowMs
        if (endpoint == null) {
            thresholdRequestTimes.count { now - it <= window }
        } else {
            endpointThresholdCounts[endpoint]?.timestamps?.count { now - it <= window } ?: 0
        }
    }

    @JvmStatic
    fun getThresholdLogs(): String {
        val config = synchronized(this) {
            val now = SystemClock.elapsedRealtime()
            thresholdCount = thresholdRequestTimes.count { now - it <= thresholdWindowMs }
            listOf(thresholdLimit, thresholdWindowMs / 1000L, thresholdTrackingEnabled, thresholdBlockRequests, thresholdCount)
        }
        val endpoints = endpointThresholdLimits.entries.sortedBy { it.key }.joinToString("\n") { (endpoint, value) ->
            "- $endpoint: ${value.limit} per ${value.windowMs / 1000L}s"
        }
        val breaches = thresholdBreaches.takeLast(10).joinToString("\n") { breach ->
            "- ${Date(breach.timestampMs)}: ${breach.message}"
        }
        return buildString {
            append("=== Network Request Threshold Logs ===\n\n")
            append("Configuration:\n")
            append("- Global Threshold: ${config[0]} requests per ${config[1]}s\n")
            append("- Tracking Enabled: ${config[2]}\n")
            append("- Request Blocking: ${config[3]}\n\n")
            append("Endpoint Thresholds:\n")
            if (endpoints.isNotEmpty()) append(endpoints).append('\n')
            append("\nCurrent Request Count: ${config[4]}\n\n")
            append("Breach History:\n")
            if (breaches.isNotEmpty()) append(breaches).append('\n')
        }
    }

    private fun recordThresholdRequest(url: String) {
        val now = SystemClock.elapsedRealtime()
        val endpoint = thresholdEndpoint(url)
        var breach: ThresholdBreachRecord? = null
        synchronized(this) {
            if (!thresholdTrackingEnabled) return
            if (thresholdStartMs == 0L || now - thresholdStartMs > thresholdWindowMs) {
                thresholdStartMs = now
            }
            thresholdRequestTimes.addLast(now)
            while (thresholdRequestTimes.isNotEmpty() && now - thresholdRequestTimes.peekFirst() > maxOf(thresholdWindowMs, 300_000L)) {
                thresholdRequestTimes.removeFirst()
            }
            thresholdCount = thresholdRequestTimes.count { now - it <= thresholdWindowMs }

            val endpointCounter = endpointThresholdCounts.computeIfAbsent(endpoint) { EndpointThresholdCount() }
            endpointCounter.timestamps.addLast(now)
            val endpointWindow = maxOf(endpointThresholdLimits[endpoint]?.windowMs ?: 0L, thresholdWindowMs, 300_000L)
            while (endpointCounter.timestamps.isNotEmpty() && now - endpointCounter.timestamps.peekFirst() > endpointWindow) {
                endpointCounter.timestamps.removeFirst()
            }

            val endpointLimit = endpointThresholdLimits[endpoint]
            val effectiveCount: Int
            val effectiveLimit: Int
            if (endpointLimit != null) {
                effectiveCount = endpointCounter.timestamps.count { now - it <= endpointLimit.windowMs }
                effectiveLimit = endpointLimit.limit
            } else {
                effectiveCount = thresholdCount
                effectiveLimit = thresholdLimit
            }
            if (effectiveCount > effectiveLimit) {
                val emoji = if (endpointLimit == null) thresholdAlertEmoji else "⚠️"
                val text = if (endpointLimit == null) thresholdAlertMessage else "Request limit exceeded!"
                val message = "$emoji $text ($effectiveCount/$effectiveLimit)"
                breach = ThresholdBreachRecord(now, effectiveCount, effectiveLimit, endpoint, message)
                thresholdBreaches.add(breach!!)
                while (thresholdBreaches.size > 1000) thresholdBreaches.removeAt(0)
            }
        }
        breach?.let { publishEvent("network", it.message) }
    }

    private fun thresholdEndpoint(url: String): String {
        val parsed = Uri.parse(url)
        val components = parsed.pathSegments.filter { it.isNotBlank() }
        return components.take(2).joinToString("/").ifEmpty { parsed.host ?: "unknown" }
    }

    private fun loadThresholdSettings(context: Context) {
        val prefs = context.getSharedPreferences(THRESHOLD_STATE_PREFS, Context.MODE_PRIVATE)
        thresholdLimit = prefs.getInt("limit", 1000)
        thresholdWindowMs = prefs.getLong("window_ms", 60_000L).coerceAtLeast(1_000L)
        thresholdTrackingEnabled = prefs.getBoolean("tracking_enabled", false)
        thresholdBlockRequests = prefs.getBoolean("block_requests", false)
        thresholdAlertEmoji = prefs.getString("alert_emoji", "⚠️") ?: "⚠️"
        thresholdAlertMessage = prefs.getString("alert_message", "Request limit exceeded!") ?: "Request limit exceeded!"
        val endpoints = runCatching { JSONArray(prefs.getString("endpoint_limits", "[]")) }.getOrNull()
        endpointThresholdLimits.clear()
        if (endpoints != null) {
            for (index in 0 until endpoints.length()) {
                val endpoint = endpoints.optJSONObject(index) ?: continue
                val name = endpoint.optString("endpoint").takeIf { it.isNotBlank() } ?: continue
                val limit = endpoint.optInt("limit", 0).takeIf { it > 0 } ?: continue
                val windowMs = endpoint.optLong("windowMs", 60_000L).coerceAtLeast(1_000L)
                endpointThresholdLimits[name] = EndpointThresholdLimit(limit, windowMs)
            }
        }
        if (thresholdTrackingEnabled) thresholdStartMs = SystemClock.elapsedRealtime()
    }

    private fun persistThresholdSettings() {
        val context = appContext ?: return
        val endpoints = JSONArray()
        endpointThresholdLimits.entries.sortedBy { it.key }.forEach { (name, config) ->
            endpoints.put(JSONObject().put("endpoint", name).put("limit", config.limit).put("windowMs", config.windowMs))
        }
        context.getSharedPreferences(THRESHOLD_STATE_PREFS, Context.MODE_PRIVATE).edit()
            .putInt("limit", thresholdLimit)
            .putLong("window_ms", thresholdWindowMs)
            .putBoolean("tracking_enabled", thresholdTrackingEnabled)
            .putBoolean("block_requests", thresholdBlockRequests)
            .putString("alert_emoji", thresholdAlertEmoji)
            .putString("alert_message", thresholdAlertMessage)
            .putString("endpoint_limits", endpoints.toString())
            .apply()
    }

    fun shouldBlock(url: String): Boolean {
        if (networkInjectionEnabled && blockedURLPatterns.any { it.containsMatchIn(url) }) return true
        return synchronized(this) {
            if (!thresholdTrackingEnabled || !thresholdBlockRequests) return@synchronized false
            val endpoint = thresholdEndpoint(url)
            val endpointLimit = endpointThresholdLimits[endpoint]
            val endpointCounter = endpointThresholdCounts[endpoint]
            val now = SystemClock.elapsedRealtime()
            val window = endpointLimit?.windowMs ?: thresholdWindowMs
            val count = if (endpointLimit != null) {
                endpointCounter?.timestamps?.count { now - it <= window } ?: 0
            } else {
                thresholdRequestTimes.count { now - it <= window }
            }
            val limit = endpointLimit?.limit ?: thresholdLimit
            limit > 0 && count >= limit
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

    fun webSocketOpened(webSocket: WebSocket, url: String, responseCode: Int) {
        val connection = findOrCreateWebSocketConnection(webSocket, url)
        connection.status = "Connected"
        connection.statusDetail = "HTTP $responseCode"
        connection.lastActivityAtMs = System.currentTimeMillis()
        recordWebSocketEvent(connection, "connected", connection.statusDetail)
    }

    fun recordWebSocketFrame(
        webSocket: WebSocket,
        url: String,
        direction: String,
        type: String,
        payload: ByteArray
    ) {
        val connection = findOrCreateWebSocketConnection(webSocket, url)
        if (connection.status == "Connecting") connection.status = "Connected"
        recordWebSocketFrame(connection, direction, type, payload)
    }

    fun webSocketClosing(webSocket: WebSocket, url: String, code: Int, reason: String) {
        val connection = findOrCreateWebSocketConnection(webSocket, url)
        connection.status = "Closing"
        connection.statusDetail = listOf(code.toString(), reason).filter { it.isNotBlank() }.joinToString(" · ")
        connection.lastActivityAtMs = System.currentTimeMillis()
        recordWebSocketEvent(connection, "closing", connection.statusDetail)
    }

    fun webSocketClosed(webSocket: WebSocket, url: String, code: Int, reason: String) {
        val connection = findOrCreateWebSocketConnection(webSocket, url)
        connection.status = "Closed"
        connection.statusDetail = listOf(code.toString(), reason).filter { it.isNotBlank() }.joinToString(" · ")
        connection.lastActivityAtMs = System.currentTimeMillis()
        activeWebSockets.remove(connection.id, webSocket)
        webSocketByInstance.remove(webSocket, connection.id)
        recordWebSocketEvent(connection, "closed", connection.statusDetail)
    }

    fun webSocketFailed(webSocket: WebSocket, url: String, error: String, responseCode: Int?) {
        val connection = findOrCreateWebSocketConnection(webSocket, url)
        connection.status = "Error"
        connection.statusDetail = listOfNotNull(responseCode?.let { "HTTP $it" }, error).joinToString(" · ")
        connection.lastActivityAtMs = System.currentTimeMillis()
        activeWebSockets.remove(connection.id, webSocket)
        webSocketByInstance.remove(webSocket, connection.id)
        recordWebSocketEvent(connection, "failed", connection.statusDetail)
    }

    /** Backward-compatible text hook for hosts that record frames without the listener wrapper. */
    fun recordWebSocket(url: String, direction: String, payload: String) {
        val normalizedDirection = direction.lowercase(Locale.ROOT)
        val connection = findOrCreateLegacyWebSocketConnection(url)
        when (normalizedDirection) {
            "connected" -> {
                connection.status = "Connected"
                connection.statusDetail = payload
                recordWebSocketEvent(connection, direction, payload)
            }
            "closing" -> {
                connection.status = "Closing"
                connection.statusDetail = payload
                recordWebSocketEvent(connection, direction, payload)
            }
            "closed" -> {
                connection.status = "Closed"
                connection.statusDetail = payload
                recordWebSocketEvent(connection, direction, payload)
            }
            "failed", "error" -> {
                connection.status = "Error"
                connection.statusDetail = payload
                recordWebSocketEvent(connection, direction, payload)
            }
            else -> {
                if (!connection.isActive()) {
                    connection.status = "Connected"
                    connection.statusDetail = ""
                }
                recordWebSocketFrame(
                    connection,
                    if (normalizedDirection.startsWith("sent")) "Sent" else "Received",
                    if (normalizedDirection.contains("binary")) "Binary" else "Text",
                    payload.toByteArray(StandardCharsets.UTF_8)
                )
            }
        }
    }

    private fun findOrCreateWebSocketConnection(webSocket: WebSocket, url: String): WebSocketConnectionRecord =
        synchronized(webSocketConnections) {
            val previousID = webSocketByInstance[webSocket]
            if (previousID != null) {
                webSocketConnections.firstOrNull { it.id == previousID }?.let { return@synchronized it }
                activeWebSockets.remove(previousID)
            }

            val connection = WebSocketConnectionRecord(UUID.randomUUID().toString(), url)
            webSocketConnections.add(connection)
            webSocketByInstance[webSocket] = connection.id
            activeWebSockets[connection.id] = webSocket
            while (webSocketConnections.size > MAX_WEBSOCKET_CONNECTIONS) {
                val removed = webSocketConnections.removeAt(0)
                activeWebSockets.remove(removed.id)
                legacyWebSocketIDs.forEach { (legacyURL, id) ->
                    if (id == removed.id) legacyWebSocketIDs.remove(legacyURL, id)
                }
                webSocketByInstance.forEach { (socket, id) ->
                    if (id == removed.id) webSocketByInstance.remove(socket, id)
                }
            }
            connection
        }

    private fun findOrCreateLegacyWebSocketConnection(url: String): WebSocketConnectionRecord =
        synchronized(webSocketConnections) {
            legacyWebSocketIDs[url]?.let { id ->
                webSocketConnections.firstOrNull { it.id == id }?.let { return@synchronized it }
            }
            val connection = WebSocketConnectionRecord("legacy:${UUID.randomUUID()}", url).apply {
                status = "Connected"
            }
            webSocketConnections.add(connection)
            legacyWebSocketIDs[url] = connection.id
            while (webSocketConnections.size > MAX_WEBSOCKET_CONNECTIONS) {
                val removed = webSocketConnections.removeAt(0)
                activeWebSockets.remove(removed.id)
                legacyWebSocketIDs.forEach { (legacyURL, id) ->
                    if (id == removed.id) legacyWebSocketIDs.remove(legacyURL, id)
                }
                webSocketByInstance.forEach { (socket, id) ->
                    if (id == removed.id) webSocketByInstance.remove(socket, id)
                }
            }
            connection
        }

    private fun recordWebSocketFrame(
        connection: WebSocketConnectionRecord,
        direction: String,
        type: String,
        payload: ByteArray
    ) {
        val frame = WebSocketFrameRecord(
            id = UUID.randomUUID().toString(),
            timestampMs = System.currentTimeMillis(),
            direction = direction,
            type = type,
            payload = payload.copyOf()
        )
        connection.frames.add(frame)
        while (connection.frames.size > MAX_WEBSOCKET_FRAMES) connection.frames.removeAt(0)
        connection.lastActivityAtMs = frame.timestampMs
        connection.unreadFrameCount.incrementAndGet()
        val preview = decodeWebSocketPayload(frame.payload)?.replace('\n', ' ')?.take(500)
            ?: "<Binary Data: ${frame.payload.size} bytes>"
        recordWebSocketEvent(connection, "${direction.lowercase(Locale.ROOT)} $type", preview)
    }

    private fun recordWebSocketEvent(connection: WebSocketConnectionRecord, action: String, payload: String) {
        val line = "${timestamp()} WebSocket $action ${connection.url}: ${payload.take(500)}"
        webSocketRecords.add(line)
        trim(webSocketRecords)
        publishEvent("network", line)
        log("WebSocket $action ${connection.url}: ${payload.take(500)}", Log.VERBOSE)
    }

    private fun decodeWebSocketPayload(payload: ByteArray): String? = runCatching {
        StandardCharsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(payload)).toString()
    }.getOrNull()

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
            writeText(webSocketConnections.sortedByDescending { it.createdAtMs }.joinToString("\n\n") { connection ->
                buildString {
                    appendLine("${connection.url}\nStatus: ${connection.status}")
                    appendLine("Started: ${Date(connection.createdAtMs)}")
                    appendLine("Last activity: ${Date(connection.lastActivityAtMs)}")
                    append(connection.frames.sortedBy { it.timestampMs }.joinToString("\n\n") { frame ->
                        webSocketFrameSnapshot(connection, frame, forExport = true)
                    }.ifEmpty { "No frames recorded." })
                }
            }.ifEmpty { webSocketRecords.joinToString("\n\n") })
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
            return thresholdSnapshot()
        }
        if (featureID == "websocket") {
            return webSocketSnapshot()
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
            "WebSocket connections: ${webSocketConnections.size} · frames: ${webSocketConnections.sumOf { it.frames.size }}\nUp to 100 recent HTTP requests are restored from app-private storage; this process keeps at most $MAX_RECORDS.\n"
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
        val lines = matchingRecords.takeLast(40).asReversed().mapIndexed { index, record ->
            "#${index + 1} ${record.method} ${record.url}\n  ${record.status} · ${record.durationMs}ms · ${record.responseBytes} bytes" +
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

    private fun filteredWebSocketConnections(): List<WebSocketConnectionRecord> {
        val query = webSocketFilter.trim()
        return webSocketConnections.sortedByDescending { it.lastActivityAtMs }.filter { connection ->
            query.isEmpty() || connection.url.contains(query, ignoreCase = true) ||
                connection.status.contains(query, ignoreCase = true) ||
                connection.frames.any { frame ->
                    decodeWebSocketPayload(frame.payload)?.contains(query, ignoreCase = true) == true
                }
        }
    }

    private fun filteredWebSocketFrames(connection: WebSocketConnectionRecord): List<WebSocketFrameRecord> {
        val query = webSocketFilter.trim()
        return connection.frames.sortedByDescending { it.timestampMs }.filter { frame ->
            (webSocketDirectionFilter.isEmpty() || frame.direction.equals(webSocketDirectionFilter, ignoreCase = true)) &&
                (query.isEmpty() || decodeWebSocketPayload(frame.payload)?.contains(query, ignoreCase = true) == true)
        }
    }

    private fun webSocketSnapshot(): String {
        val connection = webSocketConnections.firstOrNull { it.id == selectedWebSocketConnectionID }
        if (connection == null) {
            selectedWebSocketConnectionID = ""
            selectedWebSocketFrameID = ""
        } else {
            val selectedFrame = connection.frames.firstOrNull { it.id == selectedWebSocketFrameID }
            if (selectedFrame != null) return webSocketFrameSnapshot(connection, selectedFrame)
            selectedWebSocketFrameID = ""

            val frames = filteredWebSocketFrames(connection)
            val directionLabel = webSocketDirectionFilter.takeIf { it.isNotEmpty() }?.let { " · $it only" }.orEmpty()
            return buildString {
                appendLine(connection.url)
                appendLine("Status: ${connection.status}${connection.statusDetail.takeIf { it.isNotBlank() }?.let { " · $it" }.orEmpty()}")
                appendLine("Started: ${Date(connection.createdAtMs)}")
                appendLine("Last activity: ${Date(connection.lastActivityAtMs)}")
                appendLine("Frames: ${connection.frames.size} · Unread: ${connection.unreadFrameCount.get()}$directionLabel")
                if (webSocketFilter.isNotBlank()) appendLine("Filter: $webSocketFilter")
                appendLine("\nFrames (newest first):")
                append(frames.mapIndexed { index, frame -> webSocketFrameRow(index + 1, frame) }
                    .joinToString("\n\n").ifEmpty { "No matching frames. Use Send Frame to send text or base64:<data>." })
            }
        }

        val matching = filteredWebSocketConnections()
        val activeCount = webSocketConnections.count { it.isActive() }
        return buildString {
            appendLine("Connections: ${matching.size} · Active: $activeCount")
            if (webSocketFilter.isNotBlank()) appendLine("Filter: $webSocketFilter · ${matching.size} matches")
            append(matching.mapIndexed { index, item ->
                val sent = item.frames.count { it.direction.equals("Sent", ignoreCase = true) }
                val received = item.frames.size - sent
                "#${index + 1} ${item.url}\n  ${item.status} · Sent $sent · Received $received · Unread ${item.unreadFrameCount.get()}" +
                    item.statusDetail.takeIf { it.isNotBlank() }?.let { "\n  $it" }.orEmpty()
            }.joinToString("\n\n").ifEmpty { "No WebSocket connections recorded. Install DebugSwiftWebSocketListener on the host OkHttp WebSocket listener." })
        }
    }

    private fun webSocketFrameRow(index: Int, frame: WebSocketFrameRecord): String {
        val preview = decodeWebSocketPayload(frame.payload)?.replace('\n', ' ')?.take(180)
            ?: "<Binary Data: ${frame.payload.size} bytes>"
        return "#$index ${frame.direction} · ${frame.type} · ${formatBytes(frame.payload.size.toLong())} · ${timestampAt(frame.timestampMs)}\n$preview"
    }

    private fun webSocketFrameSnapshot(connection: WebSocketConnectionRecord, frame: WebSocketFrameRecord): String {
        return webSocketFrameSnapshot(connection, frame, forExport = false)
    }

    private fun webSocketFrameSnapshot(
        connection: WebSocketConnectionRecord,
        frame: WebSocketFrameRecord,
        forExport: Boolean
    ): String {
        val decoded = decodeWebSocketPayload(frame.payload)
        val rawPayload = if (forExport || decoded == null) decoded else decoded.take(64_000)
        val pretty = rawPayload?.let(::prettyWebSocketPayload)
        val hexLimit = if (forExport) frame.payload.size else minOf(frame.payload.size, 4096)
        val hex = frame.payload.take(hexLimit).joinToString(" ") { "%02X".format(it.toInt() and 0xFF) }
        return buildString {
            appendLine(connection.url)
            appendLine("Direction: ${frame.direction}")
            appendLine("Timestamp: ${Date(frame.timestampMs)}")
            appendLine("Type: ${frame.type}")
            appendLine("Size: ${formatBytes(frame.payload.size.toLong())}")
            appendLine("\nPretty / decoded payload")
            appendLine(pretty ?: if (decoded == null) "<Binary data>" else "<Payload too large to format>")
            if (!forExport && decoded != null && decoded.length > 64_000) appendLine("… payload preview truncated …")
            appendLine("\nRaw payload")
            appendLine(rawPayload ?: "<Binary data>")
            if (!forExport && decoded != null && decoded.length > 64_000) appendLine("… payload preview truncated …")
            appendLine("\nHex")
            append(hex.ifBlank { "(empty)" })
            if (!forExport && frame.payload.size > hexLimit) appendLine("\n… showing $hexLimit of ${frame.payload.size} bytes …")
        }
    }

    private fun prettyWebSocketPayload(payload: String): String = runCatching {
        when {
            payload.trim().startsWith("{") -> JSONObject(payload).toString(2)
            payload.trim().startsWith("[") -> JSONArray(payload).toString(2)
            else -> payload
        }
    }.getOrDefault(payload)

    private fun selectWebSocketConnection(value: String): String {
        val index = value.trim().removePrefix("#").toIntOrNull()
            ?: return "Enter a connection number from the current list."
        val connection = filteredWebSocketConnections().getOrNull(index - 1)
            ?: return "No WebSocket connection at position $index. Refresh the list; the newest activity is #1."
        selectedWebSocketConnectionID = connection.id
        selectedWebSocketFrameID = ""
        webSocketDirectionFilter = ""
        connection.unreadFrameCount.set(0)
        return webSocketSnapshot()
    }

    private fun selectWebSocketFrame(value: String): String {
        val connection = webSocketConnections.firstOrNull { it.id == selectedWebSocketConnectionID }
            ?: return "Open a WebSocket connection first."
        val index = value.trim().removePrefix("#").toIntOrNull()
            ?: return "Enter a frame number from the current connection."
        val frame = filteredWebSocketFrames(connection).getOrNull(index - 1)
            ?: return "No WebSocket frame at position $index. Refresh the frame list; the newest frame is #1."
        selectedWebSocketFrameID = frame.id
        return webSocketSnapshot()
    }

    private fun closeSelectedWebSocketConnection(): String {
        val connection = webSocketConnections.firstOrNull { it.id == selectedWebSocketConnectionID }
            ?: return "Open a WebSocket connection first."
        val socket = activeWebSockets[connection.id]
            ?: return "Connection is already closed."
        val accepted = runCatching { socket.close(1000, "Closed from DebugSwift") }.getOrDefault(false)
        if (!accepted) return "The WebSocket client rejected the close request.\n\n${webSocketSnapshot()}"
        connection.status = "Closing"
        connection.statusDetail = "Close requested by DebugSwift"
        recordWebSocketEvent(connection, "closing", connection.statusDetail)
        selectedWebSocketFrameID = ""
        return webSocketSnapshot()
    }

    private fun copyWebSocketURL(context: Context): String {
        val connection = webSocketConnections.firstOrNull { it.id == selectedWebSocketConnectionID }
            ?: return "Open a WebSocket connection first."
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
            ?: return "Clipboard service is not available."
        clipboard.setPrimaryClip(ClipData.newPlainText("WebSocket URL", connection.url))
        return "WebSocket URL copied to clipboard.\n\n${webSocketSnapshot()}"
    }

    private fun copyWebSocketPayload(context: Context): String {
        val connection = webSocketConnections.firstOrNull { it.id == selectedWebSocketConnectionID }
            ?: return "Open a WebSocket connection first."
        val frame = connection.frames.firstOrNull { it.id == selectedWebSocketFrameID }
            ?: return "Open a frame first."
        val content = decodeWebSocketPayload(frame.payload)?.let(::prettyWebSocketPayload)
            ?: frame.payload.joinToString(" ") { "%02X".format(it.toInt() and 0xFF) }
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
            ?: return "Clipboard service is not available."
        clipboard.setPrimaryClip(ClipData.newPlainText("WebSocket payload", content))
        return "Frame payload copied to clipboard.\n\n${webSocketFrameSnapshot(connection, frame)}"
    }

    private fun clearSelectedWebSocketFrames(): String {
        val connection = webSocketConnections.firstOrNull { it.id == selectedWebSocketConnectionID }
        if (connection == null) {
            webSocketConnections.forEach { it.frames.clear(); it.unreadFrameCount.set(0) }
        } else {
            connection.frames.clear()
            connection.unreadFrameCount.set(0)
        }
        selectedWebSocketFrameID = ""
        recordWebSocketEvent(connection ?: WebSocketConnectionRecord("history", "all connections"), "frames cleared", "")
        return webSocketSnapshot()
    }

    private fun sendWebSocketFrame(value: String, resendSelected: Boolean): String {
        val connection = webSocketConnections.firstOrNull { it.id == selectedWebSocketConnectionID }
            ?: return "Open a WebSocket connection first."
        val socket = activeWebSockets[connection.id] ?: return "Connection is closed. Frames cannot be sent."
        val frame = if (resendSelected) {
            connection.frames.firstOrNull { it.id == selectedWebSocketFrameID }
                ?: return "Select a frame to resend first."
        } else null

        val isBase64Payload = !resendSelected && value.startsWith("base64:", ignoreCase = true)
        val payloadText = when {
            frame?.type == "Binary" || isBase64Payload -> null
            frame != null -> decodeWebSocketPayload(frame.payload)
            else -> value
        }
        val payloadBytes = when {
            frame != null -> frame.payload
            value.startsWith("base64:", ignoreCase = true) -> runCatching {
                android.util.Base64.decode(value.substringAfter(':'), android.util.Base64.DEFAULT)
            }.getOrElse { return "Invalid base64 payload: ${it.message}" }
            else -> value.toByteArray(StandardCharsets.UTF_8)
        }
        val sent = if (payloadText == null) {
            runCatching { socket.send(okio.ByteString.of(*payloadBytes)) }.getOrDefault(false)
        } else {
            runCatching { socket.send(payloadText) }.getOrDefault(false)
        }
        if (!sent) return "The WebSocket client rejected the frame.\n\n${webSocketSnapshot()}"
        recordWebSocketFrame(connection, "Sent", if (payloadText == null) "Binary" else "Text", payloadBytes)
        selectedWebSocketFrameID = ""
        return "Frame sent.\n\n${webSocketSnapshot()}"
    }

    private fun clearWebSocketHistory(): String {
        webSocketConnections.clear()
        webSocketRecords.clear()
        legacyWebSocketIDs.clear()
        selectedWebSocketConnectionID = ""
        selectedWebSocketFrameID = ""
        webSocketFilter = ""
        webSocketDirectionFilter = ""
        events.removeAll { it.contains("WebSocket") }
        publishEvent("network", "WebSocket history cleared")
        return "WebSocket connections and frames cleared."
    }

    private fun selectNetworkRequest(featureID: String, value: String): String {
        if (featureID !in setOf("http", "graphql", "network_history")) {
            return "Request details are not available for $featureID."
        }
        val records = when (featureID) {
            "http" -> networkRecords.filter { it.source == "http" }
            "graphql" -> networkRecords.filter { it.source == "http" && it.graphqlOperation.isNotBlank() }
            else -> networkRecords.toList()
        }
        val matching = records.filter { record ->
            val query = networkFilter.trim().lowercase()
            query.isEmpty() || listOf(record.url, record.method, record.requestBody, record.responseBody, record.graphqlOperation)
                .any { it.lowercase().contains(query) }
        }.takeLast(40).asReversed()
        val index = value.trim().toIntOrNull()
        val selected = if (index != null) matching.getOrNull(index - 1) else {
            val query = value.trim()
            matching.firstOrNull { it.url.contains(query, ignoreCase = true) || it.graphqlOperation.contains(query, ignoreCase = true) }
        }
        if (selected == null) {
            return if (index != null) "No request at position $index. Refresh the list; request numbers start at 1 with the newest request."
            else "Enter a request number from the list, or a URL/GraphQL operation name to search."
        }
        return buildString {
            appendLine("${selected.method} ${selected.url}")
            appendLine("Status: ${selected.status}")
            appendLine("Duration: ${selected.durationMs}ms")
            appendLine("Started: ${Date(selected.timestamp)}")
            appendLine("Request size: ${formatBytes(selected.requestBytes)}")
            appendLine("Response size: ${formatBytes(selected.responseBytes)}")
            selected.graphqlOperation.takeIf { it.isNotBlank() }?.let { appendLine("GraphQL operation: $it") }
            selected.error.takeIf { it.isNotBlank() }?.let { appendLine("Error: $it") }
            appendLine("\nRequest headers\n${formatHeaders(selected.requestHeaders).ifBlank { "(none)" }}")
            appendLine("\nRequest body\n${selected.requestBody.ifBlank { "(none)" }}")
            appendLine("\nResponse headers\n${formatHeaders(selected.responseHeaders).ifBlank { "(none)" }}")
            appendLine("\nResponse body\n${selected.responseBody.ifBlank { "(none)" }}")
            if (selected.decryptedResponseBody.isNotBlank() && selected.decryptedResponseBody != selected.responseBody) {
                appendLine("\nDecrypted response body\n${selected.decryptedResponseBody}")
            }
        }
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
            "persistent_data" -> persistentDataSnapshot(context)
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

    private fun persistentDataSnapshot(context: Context): String {
        val preferenceDirectory = File(context.applicationInfo.dataDir, "shared_prefs")
        val preferenceNames = (registeredPreferences + preferenceDirectory.listFiles()
            .orEmpty()
            .filter { it.isFile && it.extension.equals("xml", ignoreCase = true) }
            .map { it.nameWithoutExtension }).toSet()
        val preferences = preferenceNames.sorted().joinToString("\n\n") { name ->
            val values = context.getSharedPreferences(name, Context.MODE_PRIVATE).all
            "$name (${values.size} values)\n" +
                values.entries.sortedBy { it.key }.joinToString("\n") { "${it.key} = ${safeValue(it.value)}" }.ifEmpty { "empty" }
        }.ifEmpty { "No preference stores found." }
        val aliases = runCatching {
            KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.aliases().toList().sorted()
        }.getOrDefault(emptyList())
        return "App preferences (SharedPreferences)\n$preferences\n\n" +
            "Secure storage (Android Keystore)\n" + aliases.joinToString("\n").ifEmpty { "No aliases found." } +
            "\nPrivate key and secret bytes are not exported. Use Preferences to add, remove, or clear values in registered stores."
    }

    private fun appSnapshot(context: Context, featureID: String): String {
        return when (featureID) {
            "crashes" -> "Saved crash reports:\n" + crashRecords.takeLast(20).asReversed().joinToString("\n\n") { it }.ifEmpty { "No uncaught crash reports saved by DebugSwift." } + "\n\nRecent Android process exits:\n${platformExitHistory(context)}"
            "console" -> JSONArray().also { entries -> consoleRecords.forEach { entries.put(it) } }.toString()
            "oslog_console" -> logcatSnapshot()
            "push_token" -> pushToken
            "push_simulator" -> pushNotificationSnapshot(context)
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

    private fun copyPushToken(context: Context): String {
        val token = pushToken.takeIf { it.isNotBlank() && !it.startsWith("No FCM token has been reported") }
            ?: return "No FCM token is available to copy."
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? android.content.ClipboardManager
            ?: return "Android clipboard is unavailable."
        clipboard.setPrimaryClip(ClipData.newPlainText("Push token", token))
        return "FCM token copied to the clipboard."
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
                return clearWebSocketHistory()
            }
            "network_history", "har_export" -> {
                networkRecords.clear()
                clearWebSocketHistory()
                networkFilter = ""
                synchronized(this) {
                    thresholdCount = 0
                    thresholdStartMs = SystemClock.elapsedRealtime()
                    thresholdRequestTimes.clear()
                    endpointThresholdCounts.clear()
                }
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
            "push_simulator" -> return clearPushHistory()
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
        if (featureID == "push_simulator") return togglePushSimulation(appContext!!)
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
            "network_thresholds" -> setThresholdBlocking(enabled)
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
            "backtraces" -> File(context.cacheDir, "debugswift-backtraces-${System.currentTimeMillis()}.txt").apply { writeText(backtraces.joinToString("\n\n")) }
            "event_bus" -> File(context.cacheDir, "debugswift-events-${System.currentTimeMillis()}.txt").apply { writeText(events.joinToString("\n")) }
            "realm" -> File(context.cacheDir, "debugswift-realm-${System.currentTimeMillis()}.txt").apply { writeText(snapshot(featureID)) }
            "console" -> File(context.cacheDir, "debugswift-console-${System.currentTimeMillis()}.txt").apply { writeText(consoleRecords.joinToString("\n")) }
            "oslog_console" -> File(context.cacheDir, "debugswift-logcat-${System.currentTimeMillis()}.txt").apply { writeText(logcatSnapshot()) }
            "network_thresholds" -> File(context.cacheDir, "debugswift-network-thresholds-${System.currentTimeMillis()}.txt").apply { writeText(getThresholdLogs()) }
            "agent_debug_log" -> File(context.filesDir, AGENT_LOG_FILENAME).takeIf { it.exists() }
            "crashes" -> File(context.cacheDir, "debugswift-crashes-${System.currentTimeMillis()}.txt").apply { writeText(crashRecords.joinToString("\n\n")) }
            "files" -> exportCurrentFile(context)
            "preferences", "persistent_data" -> File(context.cacheDir, "debugswift-${featureID}-${System.currentTimeMillis()}.txt").apply { writeText(snapshot(featureID)) }
            "push_simulator" -> File(context.cacheDir, "debugswift-push-notifications-${System.currentTimeMillis()}.txt").apply { writeText(pushNotificationSnapshot(context, showAllHistory = true)) }
            "color_palette" -> File(context.cacheDir, "debugswift-palette-${System.currentTimeMillis()}.txt").apply { writeText(lastPalette.joinToString("\n")) }
            "sqlite", "core_data", "swift_data" -> File(context.cacheDir, "debugswift-resources-${System.currentTimeMillis()}.txt").apply { writeText(snapshot(featureID)) }
            "doc_recorder" -> File(lastRecordingPath).takeIf { lastRecordingPath.isNotEmpty() && it.exists() }
            else -> null
        }
        return file?.let { shareExport(it, context) } ?: "Nothing to export for $featureID."
    }

    private fun shareExport(file: File, context: Context): String {
        if (!file.isFile) return "Export file is unavailable."
        val activity = foregroundActivity.get() ?: return "Exported ${file.name}, but no foreground Activity is available to share it."
        return runCatching {
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.debugswift.fileprovider",
                file
            )
            val mimeType = MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(file.extension.lowercase(Locale.ROOT))
                ?: "application/octet-stream"
            val sendIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newUri(context.contentResolver, file.name, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(sendIntent, "Share ${file.name}")
            if (Looper.myLooper() == Looper.getMainLooper()) {
                activity.startActivity(chooser)
            } else {
                mainHandler.post { activity.startActivity(chooser) }
            }
            "Sharing ${file.name}."
        }.getOrElse { error ->
            Log.e(TAG, "Unable to share exported file ${file.name}", error)
            "Exported ${file.name}, but sharing failed. Add the DebugSwift FileProvider to the host app manifest."
        }
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
                appInForeground = true
                appContext?.let(::refreshNotificationSettings)
                if (previous !== activity) updateOverlay()
                publishEvent("app", "Activity resumed: ${activity.javaClass.simpleName}")
            }

            override fun onActivityPaused(activity: Activity) {
                if (foregroundActivity.get() === activity) appInForeground = false
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
        val parts = value.split("|", limit = 8).map { it.trim() }
        val title = parts.getOrNull(0)?.trim()?.takeIf { it.isNotEmpty() } ?: "DebugSwift test notification"
        val message = parts.getOrNull(1)?.trim()?.takeIf { it.isNotEmpty() } ?: "Local push simulation · ${timestamp()}"
        val delayValue = parts.getOrNull(2)?.trim().orEmpty()
        val delaySeconds = delayValue.toLongOrNull() ?: if (delayValue.isBlank()) 0L else return "Delay must be a whole number of seconds."
        if (delaySeconds < 0) return "Delay must be zero or more seconds."
        val badgeValue = parts.getOrNull(4).orEmpty()
        val badge = badgeValue.toIntOrNull() ?: if (badgeValue.isBlank()) null else return "Badge must be a whole number."
        val userInfo = parsePushUserInfo(parts.getOrNull(7).orEmpty())
            ?: return "User info must use key=value pairs separated by commas."
        return schedulePushNotification(
            context,
            title,
            message,
            delaySeconds,
            parts.getOrNull(3)?.takeIf { it.isNotBlank() },
            badge,
            parts.getOrNull(5)?.takeIf { it.isNotBlank() },
            parts.getOrNull(6)?.takeIf { it.isNotBlank() },
            userInfo
        )
    }

    private fun parsePushUserInfo(value: String): Map<String, String>? {
        if (value.isBlank()) return emptyMap()
        val result = linkedMapOf<String, String>()
        for (entry in value.split(",")) {
            val pair = entry.split("=", limit = 2)
            if (pair.size != 2 || pair[0].isBlank()) return null
            result[pair[0].trim()] = pair[1].trim()
        }
        return result
    }

    private fun ensureNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(NotificationChannel(NOTIFICATION_CHANNEL, "DebugSwift tests", NotificationManager.IMPORTANCE_DEFAULT))
        }
    }

    private fun loadPushState(context: Context) {
        if (pushStateLoaded) return
        synchronized(this) {
            if (pushStateLoaded) return
            val preferences = context.getSharedPreferences(PUSH_STATE_PREFS, Context.MODE_PRIVATE)
            pushEnabled = false
            pushShowInForeground = preferences.getBoolean("showInForeground", true)
            pushPlaySound = preferences.getBoolean("playSound", true)
            pushShowBadge = preferences.getBoolean("showBadge", true)
            pushAutoInteraction = preferences.getBoolean("autoInteraction", false)
            pushInteractionDelaySeconds = preferences.getFloat("interactionDelay", 3f).toDouble()
            pushSimulateRealPush = preferences.getBoolean("simulateRealPush", false)
            pushDefaultSound = preferences.getString("defaultSound", "default") ?: "default"
            pushMaxHistoryCount = preferences.getInt("maxHistoryCount", 100).coerceIn(1, 1_000)
            runCatching {
                val historyJSON = JSONArray(preferences.getString("history", "[]") ?: "[]")
                for (index in 0 until historyJSON.length()) {
                    val json = historyJSON.getJSONObject(index)
                    pushHistory.add(json.toPushRecord())
                }
            }
            runCatching {
                val templateJSON = JSONArray(preferences.getString("templates", "") ?: "")
                for (index in 0 until templateJSON.length()) {
                    pushTemplates.add(templateJSON.getJSONObject(index).toPushTemplate())
                }
            }
            if (pushTemplates.isEmpty()) {
                pushTemplates.addAll(defaultPushTemplates())
                savePushTemplates(context)
            }
            pushHistory.replaceAll { record ->
                if (record.status == "Scheduled") record.copy(status = "Failed") else record
            }
            savePushHistory(context)
            pushStateLoaded = true
        }
    }

    private fun defaultPushTemplates() = listOf(
        PushNotificationTemplate("message", "Message", "New Message", "You have a new message from {{sender}}", null, null, null, null, mapOf("type" to "message", "sender" to "John Doe"), true),
        PushNotificationTemplate("news", "News Update", "Breaking News", "{{headline}}", "{{category}}", null, null, null, mapOf("type" to "news", "headline" to "Major technology breakthrough announced", "category" to "Technology"), true),
        PushNotificationTemplate("reminder", "Reminder", "Reminder", "Don't forget: {{task}}", null, 1, null, null, mapOf("type" to "reminder", "task" to "your task"), true),
        PushNotificationTemplate("marketing", "Marketing", "Special Offer! 🎉", "Get {{discount}}% off your next purchase", "Limited time offer", 1, null, null, mapOf("type" to "marketing", "discount" to "50"), true),
        PushNotificationTemplate("system", "System Alert", "System Notification", "{{message}}", null, null, "default", null, mapOf("type" to "system", "message" to "System alert"), true)
    )

    private fun pushPreferences(context: Context) =
        context.getSharedPreferences(PUSH_STATE_PREFS, Context.MODE_PRIVATE)

    private fun persistPushConfiguration(context: Context) {
        pushPreferences(context).edit()
            .putBoolean("showInForeground", pushShowInForeground)
            .putBoolean("playSound", pushPlaySound)
            .putBoolean("showBadge", pushShowBadge)
            .putBoolean("autoInteraction", pushAutoInteraction)
            .putFloat("interactionDelay", pushInteractionDelaySeconds.toFloat())
            .putBoolean("simulateRealPush", pushSimulateRealPush)
            .putString("defaultSound", pushDefaultSound)
            .putInt("maxHistoryCount", pushMaxHistoryCount)
            .apply()
    }

    private fun JSONObject.toPushRecord() = PushNotificationRecord(
        id = optString("id", UUID.randomUUID().toString()),
        title = optString("title"),
        body = optString("body"),
        subtitle = optString("subtitle").takeUnless { isNull("subtitle") || it.isBlank() },
        badge = if (isNull("badge")) null else optInt("badge"),
        sound = optString("sound").takeUnless { isNull("sound") || it.isBlank() },
        category = optString("category").takeUnless { isNull("category") || it.isBlank() },
        userInfo = jsonObjectToStringMap(optJSONObject("userInfo")),
        scheduledAtMs = optLong("scheduledAtMs", System.currentTimeMillis()),
        deliveryAtMs = if (isNull("deliveryAtMs")) null else optLong("deliveryAtMs"),
        status = optString("status", "Scheduled"),
        trigger = optString("trigger", "Immediate"),
        interactionType = optString("interactionType").takeUnless { isNull("interactionType") || it.isBlank() }
    )

    private fun JSONObject.toPushTemplate() = PushNotificationTemplate(
        id = optString("id", UUID.randomUUID().toString()),
        name = optString("name"),
        title = optString("title"),
        body = optString("body"),
        subtitle = optString("subtitle").takeUnless { isNull("subtitle") || it.isBlank() },
        badge = if (isNull("badge")) null else optInt("badge"),
        sound = optString("sound").takeUnless { isNull("sound") || it.isBlank() },
        category = optString("category").takeUnless { isNull("category") || it.isBlank() },
        userInfo = jsonObjectToStringMap(optJSONObject("userInfo")),
        isDefault = optBoolean("isDefault", false)
    )

    private fun jsonObjectToStringMap(json: JSONObject?): Map<String, String> {
        if (json == null) return emptyMap()
        return json.keys().asSequence().associateWith { key -> json.optString(key) }
    }

    private fun pushRecordJSON(record: PushNotificationRecord) = JSONObject().apply {
        put("id", record.id)
        put("title", record.title)
        put("body", record.body)
        put("subtitle", record.subtitle ?: JSONObject.NULL)
        put("badge", record.badge ?: JSONObject.NULL)
        put("sound", record.sound ?: JSONObject.NULL)
        put("category", record.category ?: JSONObject.NULL)
        put("userInfo", JSONObject(record.userInfo))
        put("scheduledAtMs", record.scheduledAtMs)
        put("deliveryAtMs", record.deliveryAtMs ?: JSONObject.NULL)
        put("status", record.status)
        put("trigger", record.trigger)
        put("interactionType", record.interactionType ?: JSONObject.NULL)
    }

    private fun pushTemplateJSON(template: PushNotificationTemplate) = JSONObject().apply {
        put("id", template.id)
        put("name", template.name)
        put("title", template.title)
        put("body", template.body)
        put("subtitle", template.subtitle ?: JSONObject.NULL)
        put("badge", template.badge ?: JSONObject.NULL)
        put("sound", template.sound ?: JSONObject.NULL)
        put("category", template.category ?: JSONObject.NULL)
        put("userInfo", JSONObject(template.userInfo))
        put("isDefault", template.isDefault)
    }

    private fun savePushHistory(context: Context) {
        val json = JSONArray()
        pushHistory.take(pushMaxHistoryCount).forEach { json.put(pushRecordJSON(it)) }
        pushPreferences(context).edit().putString("history", json.toString()).apply()
    }

    private fun savePushTemplates(context: Context) {
        val json = JSONArray()
        pushTemplates.forEach { json.put(pushTemplateJSON(it)) }
        pushPreferences(context).edit().putString("templates", json.toString()).apply()
    }

    private fun notificationsPermissionGranted(context: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == android.content.pm.PackageManager.PERMISSION_GRANTED) &&
            (!androidNotificationSettingsLoaded || androidNotificationsEnabled)

    private fun refreshNotificationSettings(context: Context) {
        notificationExecutor.execute {
            androidNotificationsEnabled = runCatching { NotificationManagerCompat.from(context).areNotificationsEnabled() }.getOrDefault(false)
            androidNotificationSettingsLoaded = true
        }
    }

    private fun requestNotificationPermission(context: Context): String {
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            val activity = foregroundActivity.get()
            if (activity != null) {
                activity.runOnUiThread {
                    if (context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        activity.requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 5081)
                    }
                }
                return "Android notification permission requested. Grant it, then try the action again."
            }
            return "Android notification permission is not granted. Open the host app and request it from an Activity."
        }
        if (androidNotificationSettingsLoaded && !androidNotificationsEnabled) {
            return "Notifications are disabled for this app. Choose Open notification settings to enable them."
        }
        return ""
    }

    private fun togglePushSimulation(context: Context): String {
        pushEnabled = !pushEnabled
        persistPushConfiguration(context)
        if (pushEnabled) {
            refreshNotificationSettings(context)
            publishEvent("app", "Push notification simulation enabled")
            val permissionMessage = requestNotificationPermission(context)
            return if (permissionMessage.isEmpty()) "Push notification simulation enabled. Android notification permission is available."
            else "Push notification simulation enabled.\n$permissionMessage"
        }
        pendingPushNotifications.values.forEach { it.cancel(true) }
        pendingPushNotifications.clear()
        pushHistory.filter { it.status == "Scheduled" }.forEach { record ->
            notificationExecutor.execute { NotificationManagerCompat.from(context).cancel(record.id.hashCode()) }
            updatePushNotification(context, record.id, "Dismissed")
        }
        publishEvent("app", "Push notification simulation disabled")
        return "Push notification simulation disabled. Pending local notifications were cancelled."
    }

    private fun pushNotificationSnapshot(context: Context, showAllHistory: Boolean = false): String {
        val permission = when {
            Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED -> "Not granted"
            !androidNotificationSettingsLoaded -> "Checking Android notification settings"
            androidNotificationsEnabled -> "Allowed"
            else -> "Disabled in system settings"
        }
        val pageCount = ((pushHistory.size + PUSH_HISTORY_PAGE_SIZE - 1) / PUSH_HISTORY_PAGE_SIZE).coerceAtLeast(1)
        pushHistoryPage = pushHistoryPage.coerceIn(1, pageCount)
        val firstIndex = (pushHistoryPage - 1) * PUSH_HISTORY_PAGE_SIZE
        val pageRecords = if (showAllHistory) pushHistory.toList() else pushHistory.drop(firstIndex).take(PUSH_HISTORY_PAGE_SIZE)
        val history = pageRecords.joinToString("\n\n") { record ->
            val scheduled = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(Date(record.scheduledAtMs))
            val delivered = record.deliveryAtMs?.let { "\nDelivered: ${SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date(it))}" }.orEmpty()
            val metadata = buildList {
                record.subtitle?.let { add("Subtitle: $it") }
                record.badge?.let { add("Badge: $it") }
                record.sound?.let { add("Sound: $it") }
                if (record.userInfo.isNotEmpty()) add("User info: ${record.userInfo.entries.joinToString { "${it.key}=${it.value}" }}")
            }.joinToString("\n")
            "${record.status} · ${record.title}\n${record.body}${if (metadata.isEmpty()) "" else "\n$metadata"}\nTrigger: ${record.trigger}\nScheduled: $scheduled${delivered}\nID: ${record.id}"
        }.ifEmpty { "No simulated notifications yet." }
        val templates = pushTemplates.joinToString("\n") { "${it.name}: ${it.title} — ${it.body}" }.ifEmpty { "No templates configured." }
        val pageLabel = if (showAllHistory) "all pages" else "page $pushHistoryPage/$pageCount"
        return "Simulation: ${if (pushEnabled) "Enabled" else "Disabled"}\nNotification permission: $permission\nChannel: $NOTIFICATION_CHANNEL\n\nConfiguration\nShow in foreground: $pushShowInForeground\nPlay sound: $pushPlaySound\nShow badge: $pushShowBadge\nAuto interaction: $pushAutoInteraction (${pushInteractionDelaySeconds}s)\nSimulate real push: $pushSimulateRealPush\nDefault sound: $pushDefaultSound\nMax history: $pushMaxHistoryCount\n\nTemplates\n$templates\n\nNotification history (${pushHistory.size}) · $pageLabel\n$history${if (showAllHistory) "" else "\n\nUse History page with a page number to browse older notifications."}"
    }

    private fun addPushRecord(context: Context, record: PushNotificationRecord) {
        synchronized(pushHistory) {
            pushHistory.add(0, record)
            pushHistoryPage = 1
            while (pushHistory.size > pushMaxHistoryCount) pushHistory.removeAt(pushHistory.lastIndex)
            savePushHistory(context)
        }
    }

    private fun updatePushNotification(context: Context, id: String, status: String, interactionType: String? = null) {
        synchronized(pushHistory) {
            val index = pushHistory.indexOfFirst { it.id == id }
            if (index < 0) return
            val old = pushHistory[index]
            pushHistory[index] = old.copy(
                status = status,
                deliveryAtMs = if (status == "Delivered" || status == "Interacted") old.deliveryAtMs ?: System.currentTimeMillis() else old.deliveryAtMs,
                interactionType = interactionType ?: old.interactionType
            )
            savePushHistory(context)
        }
        publishEvent("app", "Notification $id status: $status")
    }

    private fun schedulePushNotification(
        context: Context,
        title: String,
        body: String,
        delaySeconds: Long = 0,
        subtitle: String? = null,
        badge: Int? = null,
        sound: String? = null,
        category: String? = null,
        userInfo: Map<String, String> = emptyMap()
    ): String {
        if (!pushEnabled) return "Enable push notification simulation before creating a notification."
        if (delaySeconds < 0) return "Delay must be zero or more seconds."
        val permissionMessage = requestNotificationPermission(context)
        if (permissionMessage.isNotEmpty()) return permissionMessage
        val boundedDelay = delaySeconds.coerceAtMost(86_400L)
        val id = UUID.randomUUID().toString()
        val record = PushNotificationRecord(
            id = id,
            title = title,
            body = body,
            subtitle = subtitle,
            badge = badge,
            sound = sound,
            category = category,
            userInfo = userInfo,
            scheduledAtMs = System.currentTimeMillis(),
            deliveryAtMs = null,
            status = "Scheduled",
            trigger = if (boundedDelay == 0L) "Immediate" else "In ${boundedDelay}s",
            interactionType = null
        )
        addPushRecord(context, record)
        val deliver = Runnable {
            pendingPushNotifications.remove(id)
            if (!pushEnabled) {
                updatePushNotification(context, id, "Dismissed")
                return@Runnable
            }
            if (!notificationsPermissionGranted(context)) {
                updatePushNotification(context, id, "Failed")
                return@Runnable
            }
            val shouldShow = pushShowInForeground || !appInForeground
            if (shouldShow) {
                runCatching {
                    val soundName = sound ?: if (pushPlaySound) pushDefaultSound else "silent"
                    val channelID = notificationChannelID(context, soundName)
                    val launchIntent = foregroundActivity.get()?.let { activity -> Intent(context, activity.javaClass) }
                        ?: context.packageManager.getLaunchIntentForPackage(context.packageName)
                        ?: Intent()
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    launchIntent.putExtra(PUSH_NOTIFICATION_ID_EXTRA, id)
                    launchIntent.putExtra("debugswift_notification_title", title)
                    launchIntent.putExtra("debugswift_notification_body", body)
                    launchIntent.putExtra("debugswift_notification_user_info", JSONObject(userInfo).toString())
                    val pendingIntent = PendingIntent.getActivity(
                        context,
                        id.hashCode(),
                        launchIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0
                    )
                    val notification = NotificationCompat.Builder(context, channelID)
                        .setSmallIcon(android.R.drawable.ic_dialog_info)
                        .setContentTitle(title)
                        .setContentText(body)
                        .setSubText(subtitle)
                        .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                        .setContentIntent(pendingIntent)
                        .setAutoCancel(true)
                        .setNumber(if (pushShowBadge) badge ?: 0 else 0)
                        .setSound(resolveNotificationSound(context, soundName))
                        .setCategory(category?.takeIf { it.isNotBlank() } ?: NotificationCompat.CATEGORY_MESSAGE)
                        .build()
                    NotificationManagerCompat.from(context).notify(id.hashCode(), notification)
                }.onFailure { error ->
                    updatePushNotification(context, id, "Failed")
                    log("Could not post local notification: ${error.message}", Log.ERROR)
                }
            }
            if (pushHistory.any { it.id == id && it.status != "Failed" }) {
                updatePushNotification(context, id, "Delivered")
                publishEvent("app", "Local test notification posted: $title")
                if (pushAutoInteraction) {
                    mainHandler.postDelayed({
                        if (pushHistory.any { it.id == id && it.status == "Delivered" }) {
                            updatePushNotification(context, id, "Interacted", "Tap")
                        }
                    }, (pushInteractionDelaySeconds.coerceAtLeast(0.0) * 1_000).toLong())
                }
            }
        }
        if (boundedDelay == 0L) {
            notificationExecutor.execute(deliver)
            return "Local notification queued for immediate delivery: $title."
        }
        pendingPushNotifications[id] = notificationExecutor.schedule(deliver, boundedDelay, TimeUnit.SECONDS)
        return "Local notification scheduled in $boundedDelay seconds (ID: $id)."
    }

    private fun resolveNotificationSound(context: Context, soundName: String): Uri? {
        if (soundName.equals("silent", ignoreCase = true) || soundName.isBlank()) return null
        if (soundName == "default") return android.provider.Settings.System.DEFAULT_NOTIFICATION_URI
        val resourceID = context.resources.getIdentifier(soundName, "raw", context.packageName)
        return if (resourceID != 0) Uri.parse("android.resource://${context.packageName}/$resourceID")
        else android.provider.Settings.System.DEFAULT_NOTIFICATION_URI
    }

    private fun notificationChannelID(context: Context, soundName: String): String {
        if (Build.VERSION.SDK_INT < 26) return NOTIFICATION_CHANNEL
        val safeSound = soundName.lowercase(Locale.ROOT).replace(Regex("[^a-z0-9_]+"), "_").take(24).ifEmpty { "default" }
        val badgeSuffix = if (pushShowBadge) "_badge" else "_no_badge"
        val channelID = "${NOTIFICATION_CHANNEL}_${safeSound}$badgeSuffix"
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(channelID) == null) {
            val silent = soundName.equals("silent", ignoreCase = true)
            val channel = NotificationChannel(channelID, "DebugSwift tests${if (silent) " (silent)" else ""}${if (pushShowBadge) "" else " (no badge)"}", if (silent) NotificationManager.IMPORTANCE_LOW else NotificationManager.IMPORTANCE_DEFAULT)
            channel.setSound(resolveNotificationSound(context, soundName), null)
            channel.setShowBadge(pushShowBadge)
            manager.createNotificationChannel(channel)
        }
        return channelID
    }

    private fun simulatePushTemplate(context: Context, value: String): String {
        val parts = value.split("|", limit = 2).map { it.trim() }
        val name = parts.firstOrNull().orEmpty()
        if (name.isBlank()) return "Enter a template name, optionally followed by |delay seconds."
        val template = pushTemplates.firstOrNull { it.name.equals(name, ignoreCase = true) }
            ?: return "No notification template named '$name'. Available: ${pushTemplates.joinToString { it.name }}"
        val delayValue = parts.getOrNull(1).orEmpty()
        val delay = delayValue.toLongOrNull() ?: if (delayValue.isBlank()) 0L else return "Template delay must be a whole number of seconds."
        if (delay < 0) return "Delay must be zero or more seconds."
        fun render(text: String?) = text?.replace(Regex("\\{\\{([^{}]+)\\}\\}")) { match -> template.userInfo[match.groupValues[1]].orEmpty() }
        return schedulePushNotification(
            context,
            render(template.title).orEmpty(),
            render(template.body).orEmpty(),
            delay,
            render(template.subtitle),
            template.badge,
            template.sound,
            template.category,
            template.userInfo
        )
    }

    private fun runPushScenario(context: Context, value: String): String {
        val parts = value.split("|", limit = 4).map { it.trim() }
        val scenario = parts.firstOrNull().orEmpty().lowercase(Locale.ROOT).replace(Regex("[^a-z]"), "")
        val notifications = when (scenario) {
            "messageflow" -> listOf(
                Triple("New Message", "You have a message from John", 0L),
                Triple("Message Delivered", "Your message was delivered", 3L),
                Triple("John is typing...", "John is composing a message", 6L)
            )
            "newsupdates" -> listOf(
                Triple("Breaking News", "Major technology breakthrough announced", 0L),
                Triple("Sports Update", "Championship game ends in overtime", 5L),
                Triple("Weather Alert", "Severe weather warning in your area", 10L)
            )
            "marketingcampaign" -> listOf(
                Triple("Welcome Offer!", "Get 50% off your first purchase", 0L),
                Triple("Cart Reminder", "You have items waiting in your cart", 300L),
                Triple("Flash Sale! ⚡", "24-hour flash sale starts now", 600L)
            )
            "systemalerts" -> listOf(
                Triple("Security Alert", "New login from unknown device", 0L),
                Triple("Backup Complete", "Your data has been backed up successfully", 2L),
                Triple("Update Available", "A new app update is available", 4L)
            )
            "customflow" -> {
                if (parts.size < 3) return "For customFlow, enter customFlow|title|message|delay seconds."
                val delayValue = parts.getOrNull(3).orEmpty()
                val delay = delayValue.toLongOrNull() ?: if (delayValue.isBlank()) 0L else return "Delay must be a whole number of seconds."
                if (delay < 0) return "Delay must be zero or more seconds."
                return schedulePushNotification(context, parts[1], parts[2], delay)
                    .let { "Custom flow: $it" }
            }
            else -> return "Choose messageFlow, newsUpdates, marketingCampaign, systemAlerts, or customFlow|title|message|delay."
        }
        if (!pushEnabled) return "Enable push notification simulation before running a scenario."
        val permissionMessage = requestNotificationPermission(context)
        if (permissionMessage.isNotEmpty()) return permissionMessage
        val results = notifications.map { (title, body, delay) -> schedulePushNotification(context, title, body, delay) }
        return "Scenario '${parts[0]}' started.\n" + results.joinToString("\n")
    }

    private fun setPushConfiguration(context: Context, value: String): String {
        val parts = value.split("=", limit = 2).map { it.trim() }
        if (parts.size != 2 || parts[0].isBlank()) {
            return "Set one option at a time: showInForeground=true, playSound=true, showBadge=true, autoInteraction=false, interactionDelay=3, simulateRealPush=false, defaultSound=default, maxHistoryCount=100."
        }
        val key = parts[0].lowercase(Locale.ROOT).replace("_", "").replace("-", "")
        val raw = parts[1]
        val bool = raw.toBooleanStrictOrNull()
        when (key) {
            "showinforeground" -> pushShowInForeground = bool ?: return "showInForeground must be true or false."
            "playsound" -> pushPlaySound = bool ?: return "playSound must be true or false."
            "showbadge" -> pushShowBadge = bool ?: return "showBadge must be true or false."
            "autointeraction" -> pushAutoInteraction = bool ?: return "autoInteraction must be true or false."
            "interactiondelay" -> pushInteractionDelaySeconds = raw.toDoubleOrNull()?.takeIf { it in listOf(1.0, 2.0, 3.0, 5.0, 10.0) } ?: return "interactionDelay must be one of 1, 2, 3, 5, or 10 seconds."
            "simulaterealpush" -> pushSimulateRealPush = bool ?: return "simulateRealPush must be true or false."
            "defaultsound" -> {
                if (raw.isBlank()) return "defaultSound cannot be empty. Use default, silent, or a raw resource name."
                pushDefaultSound = raw
            }
            "maxhistorycount" -> pushMaxHistoryCount = raw.toIntOrNull()?.takeIf { it in listOf(50, 100, 200, 500, 1_000) } ?: return "maxHistoryCount must be 50, 100, 200, 500, or 1000."
            else -> return "Unknown notification option '${parts[0]}'."
        }
        persistPushConfiguration(context)
        savePushHistory(context)
        return "Notification configuration updated: ${parts[0]}=$raw."
    }

    private fun addPushTemplate(context: Context, value: String): String {
        val parts = value.split("|", limit = 8).map { it.trim() }
        if (parts.size < 3 || parts[0].isBlank() || parts[1].isBlank() || parts[2].isBlank()) {
            return "Enter name|title|body|subtitle|badge|sound|category|key=value,... to add a template."
        }
        val badgeValue = parts.getOrNull(4).orEmpty()
        val badge = badgeValue.toIntOrNull() ?: if (badgeValue.isBlank()) null else return "Badge must be a whole number."
        val userInfo = parsePushUserInfo(parts.getOrNull(7).orEmpty())
            ?: return "User info must use key=value pairs separated by commas."
        val template = PushNotificationTemplate(
            UUID.randomUUID().toString(),
            parts[0],
            parts[1],
            parts[2],
            parts.getOrNull(3)?.takeIf { it.isNotBlank() },
            badge,
            parts.getOrNull(5)?.takeIf { it.isNotBlank() },
            parts.getOrNull(6)?.takeIf { it.isNotBlank() },
            userInfo,
            false
        )
        return storePushTemplate(context, template)
    }

    private fun storePushTemplate(context: Context, template: PushNotificationTemplate): String {
        if (pushTemplates.any { it.name.equals(template.name, ignoreCase = true) }) return "A template named '${template.name}' already exists."
        pushTemplates.add(template)
        savePushTemplates(context)
        publishEvent("app", "Push notification template added: ${template.name}")
        return "Notification template '${template.name}' added."
    }

    private fun removePushTemplate(context: Context, value: String): String {
        val name = value.trim()
        if (name.isBlank()) return "Enter a notification template name to remove."
        val template = pushTemplates.firstOrNull { it.name.equals(name, ignoreCase = true) }
            ?: return "No notification template named '$name'."
        if (template.isDefault) return "Default notification templates cannot be removed."
        pushTemplates.remove(template)
        savePushTemplates(context)
        publishEvent("app", "Push notification template removed: ${template.name}")
        return "Notification template '${template.name}' removed."
    }

    private fun clearPushHistory(): String {
        val context = appContext ?: return "Android runtime has not been installed."
        pushHistory.clear()
        savePushHistory(context)
        publishEvent("app", "Push notification history cleared")
        return "Push notification history cleared."
    }

    private fun removePushNotification(context: Context, value: String): String {
        val id = value.trim()
        if (id.isBlank()) return "Enter the notification ID shown in its history entry."
        val record = pushHistory.firstOrNull { it.id == id } ?: return "No simulated notification with ID '$id'."
        pendingPushNotifications.remove(id)?.cancel(true)
        notificationExecutor.execute { NotificationManagerCompat.from(context).cancel(id.hashCode()) }
        pushHistory.remove(record)
        savePushHistory(context)
        return "Removed notification '${record.title}' from history."
    }

    private fun interactWithPushNotification(context: Context, value: String): String {
        val id = value.trim()
        if (pushHistory.none { it.id == id }) return "Enter a notification ID from history."
        updatePushNotification(context, id, "Interacted", "Tap")
        return "Interaction recorded for notification $id."
    }

    private fun resendPushNotification(context: Context, value: String): String {
        val id = value.trim()
        val record = pushHistory.firstOrNull { it.id == id }
            ?: return "Enter a notification ID from history."
        return schedulePushNotification(context, record.title, record.body, subtitle = record.subtitle, badge = record.badge, sound = record.sound, category = record.category, userInfo = record.userInfo)
    }

    private fun showPushHistoryPage(context: Context, value: String): String {
        val requestedPage = value.trim().toIntOrNull()
            ?: return "Enter a history page number from 1 to ${((pushHistory.size + PUSH_HISTORY_PAGE_SIZE - 1) / PUSH_HISTORY_PAGE_SIZE).coerceAtLeast(1)}."
        val lastPage = ((pushHistory.size + PUSH_HISTORY_PAGE_SIZE - 1) / PUSH_HISTORY_PAGE_SIZE).coerceAtLeast(1)
        if (requestedPage !in 1..lastPage) return "History page must be between 1 and $lastPage."
        pushHistoryPage = requestedPage
        return pushNotificationSnapshot(context)
    }

    private fun openNotificationSettings(context: Context): String = runCatching {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, context.packageName)
        } else {
            Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        "Opened Android notification settings for ${context.packageName}."
    }.getOrElse { "Could not open notification settings: ${it.message}" }

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

    private fun deletePreference(context: Context, value: String): String {
        val parts = value.split("|", limit = 2)
        if (parts.size != 2 || parts[0].isBlank() || parts[1].isBlank()) return "Enter preferenceStore|key."
        val storeName = parts[0].trim()
        val key = parts[1].trim()
        if (storeName == PREFS || storeName !in registeredPreferences) {
            return "Choose a registered host preference store."
        }
        val store = context.getSharedPreferences(storeName, Context.MODE_PRIVATE)
        if (key !in store.all) return "Preference '$key' was not found in '$storeName'."
        store.edit().remove(key).apply()
        publishEvent("resources", "Preference removed: $storeName.$key")
        return "Preference '$key' removed from '$storeName'."
    }

    private fun clearPreferenceStore(context: Context, value: String): String {
        val parts = value.split("|", limit = 2)
        if (parts.size != 2 || parts[1].trim() != "CLEAR") {
            return "Enter preferenceStore|CLEAR to confirm removing all values from a store."
        }
        val storeName = parts[0].trim()
        if (storeName.isBlank() || storeName == PREFS || storeName !in registeredPreferences) {
            return "Choose a registered host preference store."
        }
        val store = context.getSharedPreferences(storeName, Context.MODE_PRIVATE)
        val removedCount = store.all.size
        store.edit().clear().apply()
        publishEvent("resources", "Preference store cleared: $storeName")
        return "Cleared $removedCount values from '$storeName'."
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

    private fun timestampAt(timestampMs: Long): String = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault()).format(Date(timestampMs))

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
        val notificationID = intent?.getStringExtra(PUSH_NOTIFICATION_ID_EXTRA)
        if (notificationID != null && pushHistory.any { it.id == notificationID }) {
            appContext?.let { updatePushNotification(it, notificationID, "Interacted", "Tap") }
            publishEvent("app", "Simulated notification opened the host app")
        }
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
