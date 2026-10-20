package debug.swift.android

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationManager
import android.location.provider.ProviderProperties
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject

/**
 * Structured data and actions for the App area: crash reports, Logcat, deep links and a mock
 * location. Like [DebugSwiftResourceAPI], each operation takes and returns a JSON object.
 */
object DebugSwiftAppAPI {
    private val mockProviders = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
    @Volatile private var mocking = false

    @JvmStatic
    fun handle(operation: String, arguments: String): String {
        val context = AndroidDebugTools.contextOrNull()
            ?: return failure("Android runtime has not been installed.").toString()
        val args = runCatching { JSONObject(arguments) }.getOrDefault(JSONObject())
        return try {
            when (operation) {
                "app.perf.sample" -> JSONObject(AndroidDebugTools.performanceSampleJSON())
                "app.crashes" -> crashes(context)
                "app.logcat" -> logcat(args.optString("filter"), args.optString("level"))
                "app.deeplink.open" -> openDeepLink(context, args.optString("uri"))
                "app.location.mock" -> mockLocation(context, args.optDouble("latitude"), args.optDouble("longitude"))
                "app.location.stop" -> stopMocking(context)
                "app.location.state" -> JSONObject().put("mocking", mocking)
                else -> failure("Unknown app operation: $operation")
            }.toString()
        } catch (exception: Exception) {
            failure(exception.message ?: exception.javaClass.simpleName).toString()
        }
    }

    private fun failure(message: String) = JSONObject().put("error", message)

    // MARK: Crashes

    private fun crashes(context: Context): JSONObject {
        val reports = JSONArray()
        AndroidDebugTools.crashReportsNewestFirst().take(20).forEach { reports.put(it) }
        val exits = JSONArray()
        if (Build.VERSION.SDK_INT >= 30) {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            manager.getHistoricalProcessExitReasons(context.packageName, 0, 15).forEach { exit ->
                val trace = runCatching { exit.traceInputStream?.use { it.readBytes() } }.getOrNull()
                // A native crash trace is a binary tombstone; only text traces (ANRs) are worth showing.
                val isText = trace != null && trace.take(4_000).none { it.toInt() == 0 }
                exits.put(
                    JSONObject().put("time", exit.timestamp).put("reason", reasonName(exit.reason))
                        .put("status", exit.status).put("description", exit.description.orEmpty())
                        .put("trace", if (isText) String(trace!!, Charsets.UTF_8).take(32_000) else "")
                        .put("hasBinaryTrace", trace != null && !isText)
                )
            }
        }
        return JSONObject().put("reports", reports).put("exits", exits)
    }

    private fun reasonName(reason: Int): String = when (reason) {
        ApplicationExitInfo.REASON_ANR -> "ANR"
        ApplicationExitInfo.REASON_CRASH -> "Java/Kotlin crash"
        ApplicationExitInfo.REASON_CRASH_NATIVE -> "Native crash"
        ApplicationExitInfo.REASON_LOW_MEMORY -> "Low memory"
        ApplicationExitInfo.REASON_USER_REQUESTED -> "User requested"
        ApplicationExitInfo.REASON_USER_STOPPED -> "User stopped"
        ApplicationExitInfo.REASON_SIGNALED -> "Signaled"
        ApplicationExitInfo.REASON_EXIT_SELF -> "Exited"
        ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "Dependency died"
        ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "Permission change"
        // Newer reasons are matched by number so older SDKs still compile.
        7 -> "Initialization failure"
        9 -> "Excessive resource usage"
        13 -> "Other"
        14 -> "Frozen"
        15 -> "Package state change"
        16 -> "Package updated"
        else -> "Reason $reason"
    }

    // MARK: Logcat

    private val levelOrder = "VDIWEF"

    /** This process's Logcat, newest last, optionally narrowed by a minimum level and a text filter. */
    private fun logcat(filter: String, minimumLevel: String): JSONObject {
        val process = ProcessBuilder("logcat", "-d", "-v", "threadtime", "-t", "2000", "--pid=${android.os.Process.myPid()}")
            .redirectErrorStream(true).start()
        val output = process.inputStream.bufferedReader().use { it.readText() }
        if (process.waitFor() != 0) return failure("Logcat is unavailable: ${output.takeLast(500)}")
        val minimum = levelOrder.indexOf(minimumLevel.firstOrNull() ?: 'V').coerceAtLeast(0)
        val entries = JSONArray()
        // "10-19 21:00:43.109  1234  5678 I Tag     : message"
        val pattern = Regex("""^(\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\s+\d+\s+\d+\s+([VDIWEF])\s+(.*?)\s*: (.*)$""")
        output.lineSequence().mapNotNull { pattern.matchEntire(it) }.filter { match ->
            levelOrder.indexOf(match.groupValues[2][0]) >= minimum &&
                (filter.isBlank() || match.groupValues[3].contains(filter, true) || match.groupValues[4].contains(filter, true))
        }.toList().takeLast(400).forEach { match ->
            entries.put(
                JSONObject().put("time", match.groupValues[1]).put("level", match.groupValues[2])
                    .put("tag", match.groupValues[3]).put("message", match.groupValues[4])
            )
        }
        return JSONObject().put("entries", entries)
    }

    // MARK: Deep links

    private fun openDeepLink(context: Context, uri: String): JSONObject {
        val value = uri.trim()
        if (value.isEmpty()) return failure("Enter a URI.")
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(value)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            JSONObject().put("message", "Opened $value.")
        } catch (missing: android.content.ActivityNotFoundException) {
            failure("No app handles $value.")
        }
    }

    // MARK: Mock location

    /**
     * Feeds a fixed position to the GPS and network providers. Android only accepts this from the app
     * chosen under Developer options > Select mock location app.
     */
    private fun mockLocation(context: Context, latitude: Double, longitude: Double): JSONObject {
        if (latitude.isNaN() || longitude.isNaN() || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) {
            return failure("Enter a latitude from -90 to 90 and a longitude from -180 to 180.")
        }
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        try {
            mockProviders.forEach { provider ->
                runCatching { manager.removeTestProvider(provider) }
                if (Build.VERSION.SDK_INT >= 31) {
                    manager.addTestProvider(provider, false, false, false, false, true, true, true, ProviderProperties.POWER_USAGE_LOW, ProviderProperties.ACCURACY_FINE)
                } else {
                    @Suppress("DEPRECATION")
                    manager.addTestProvider(provider, false, false, false, false, true, true, true, 1, 1)
                }
                manager.setTestProviderEnabled(provider, true)
                val location = Location(provider).apply {
                    this.latitude = latitude
                    this.longitude = longitude
                    accuracy = 5f
                    time = System.currentTimeMillis()
                    elapsedRealtimeNanos = SystemClock.elapsedRealtimeNanos()
                }
                manager.setTestProviderLocation(provider, location)
            }
        } catch (denied: SecurityException) {
            return failure("Android blocked it. Choose this app under Developer options > Select mock location app, then try again.")
        }
        mocking = true
        AndroidDebugTools.reportLocation(latitude, longitude, 5f)
        return JSONObject().put("message", "Location set to $latitude, $longitude.").put("mocking", true)
    }

    private fun stopMocking(context: Context): JSONObject {
        val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        mockProviders.forEach { runCatching { manager.removeTestProvider(it) } }
        mocking = false
        return JSONObject().put("message", "Mock location stopped.").put("mocking", false)
    }
}
