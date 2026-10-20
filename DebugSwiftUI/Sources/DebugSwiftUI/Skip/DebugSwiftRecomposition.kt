package debug.swift.android

import androidx.compose.runtime.ExperimentalComposeApi
import androidx.compose.runtime.Recomposer
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Counts how often Compose recomposes in this process, with no wrapper in the host's UI. Compose
 * exposes the running recomposers, and each one counts the changes it has applied; sampling that once
 * a second gives a rate over time.
 */
object DebugSwiftRecomposition {
    private const val HISTORY = 60
    private val history = ArrayDeque<Long>()
    private var lastTotal = -1L
    private var started = false

    @Synchronized
    fun start() {
        if (started) return
        started = true
        Executors.newSingleThreadScheduledExecutor { task -> Thread(task, "DebugSwiftRecomposition").apply { isDaemon = true } }
            .scheduleAtFixedRate({ sample() }, 1, 1, TimeUnit.SECONDS)
    }

    @OptIn(ExperimentalComposeApi::class)
    private fun total(): Long = runCatching { Recomposer.runningRecomposers.value.sumOf { it.changeCount } }.getOrDefault(0L)

    @Synchronized
    private fun sample() {
        val now = total()
        if (lastTotal >= 0) history.addLast((now - lastTotal).coerceAtLeast(0))
        while (history.size > HISTORY) history.removeFirst()
        lastTotal = now
    }

    @OptIn(ExperimentalComposeApi::class)
    @Synchronized
    fun state(): JSONObject {
        val recomposers = runCatching { Recomposer.runningRecomposers.value.size }.getOrDefault(0)
        return JSONObject()
            .put("total", total())
            .put("recomposers", recomposers)
            .put("perSecond", JSONArray(history.toList()))
            .put("probeRenders", AndroidDebugTools.composeProbeCount())
            .put("frames", AndroidDebugTools.frameTotal())
    }
}
