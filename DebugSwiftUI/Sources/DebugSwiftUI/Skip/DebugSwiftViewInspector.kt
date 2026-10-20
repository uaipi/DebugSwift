package debug.swift.android

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.compose.ui.node.RootForTest
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.getOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Reads the foreground window as a tree: Android views, and for Compose content the semantics tree
 * (what text, descriptions, tags and clicks each element has). Also draws a highlight over chosen
 * elements, so a row in the panel can be matched with the thing on screen.
 */
object DebugSwiftViewInspector {
    private const val MAX_NODES = 2500
    private const val HIGHLIGHT_MILLIS = 5_000L

    private val main = Handler(Looper.getMainLooper())
    private var highlight: HighlightView? = null

    /** Runs on the main thread, which View and Compose APIs require, and waits for the result. */
    private fun <T> onMain(block: () -> T): T {
        if (Looper.myLooper() == Looper.getMainLooper()) return block()
        var outcome: Result<T>? = null
        val done = CountDownLatch(1)
        main.post {
            outcome = runCatching(block)
            done.countDown()
        }
        if (!done.await(5, TimeUnit.SECONDS)) throw IllegalStateException("The app did not answer in time.")
        return outcome!!.getOrThrow()
    }

    fun tree(): JSONObject {
        val activity = AndroidDebugTools.foregroundActivityOrNull()
            ?: return JSONObject().put("error", "No foreground activity is available.")
        return onMain {
            val decor = activity.window.decorView
            val budget = IntArray(1)
            JSONObject()
                .put("windowWidth", decor.width)
                .put("windowHeight", decor.height)
                .put("density", activity.resources.displayMetrics.density.toDouble())
                .put("root", viewNode(decor, budget))
                .put("truncated", budget[0] >= MAX_NODES)
        }
    }

    private fun viewNode(view: View, budget: IntArray): JSONObject {
        budget[0]++
        val location = IntArray(2)
        view.getLocationInWindow(location)
        val node = JSONObject()
            .put("kind", "view")
            .put("name", view.javaClass.simpleName.ifEmpty { view.javaClass.name })
            .put("className", view.javaClass.name)
            .put("resourceId", resourceName(view))
            .put("left", location[0]).put("top", location[1])
            .put("width", view.width).put("height", view.height)
            .put("visible", view.visibility == View.VISIBLE && view.isShown)
            .put("alpha", view.alpha.toDouble())
            .put("clickable", view.isClickable)
            .put("enabled", view.isEnabled)
        (view as? TextView)?.text?.toString()?.takeIf { it.isNotEmpty() }?.let { node.put("text", it.take(200)) }
        view.contentDescription?.toString()?.takeIf { it.isNotEmpty() }?.let { node.put("description", it.take(200)) }
        val children = JSONArray()
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                if (budget[0] >= MAX_NODES) break
                children.put(viewNode(view.getChildAt(index), budget))
            }
        }
        if (view is RootForTest && budget[0] < MAX_NODES) {
            children.put(semanticsNode(view.semanticsOwner.unmergedRootSemanticsNode, budget))
        }
        return node.put("children", children)
    }

    private fun semanticsNode(node: SemanticsNode, budget: IntArray): JSONObject {
        budget[0]++
        val bounds = node.boundsInWindow
        val config = node.config
        val text = config.getOrNull(SemanticsProperties.Text)?.joinToString(" ") { it.text }
        val result = JSONObject()
            .put("kind", "compose")
            .put("name", config.getOrNull(SemanticsProperties.Role)?.toString() ?: "Compose node")
            .put("className", "androidx.compose.ui.semantics.SemanticsNode")
            .put("resourceId", config.getOrNull(SemanticsProperties.TestTag).orEmpty())
            .put("left", bounds.left.toInt()).put("top", bounds.top.toInt())
            .put("width", bounds.width.toInt()).put("height", bounds.height.toInt())
            .put("visible", !config.contains(SemanticsProperties.InvisibleToUser))
            .put("alpha", 1.0)
            .put("clickable", config.contains(SemanticsActions.OnClick))
            .put("enabled", !config.contains(SemanticsProperties.Disabled))
        text?.takeIf { it.isNotEmpty() }?.let { result.put("text", it.take(200)) }
        config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(" ")?.takeIf { it.isNotEmpty() }
            ?.let { result.put("description", it.take(200)) }
        val children = JSONArray()
        for (child in node.children) {
            if (budget[0] >= MAX_NODES) break
            children.put(semanticsNode(child, budget))
        }
        return result.put("children", children)
    }

    private fun resourceName(view: View): String {
        if (view.id == View.NO_ID) return ""
        return runCatching { view.resources.getResourceEntryName(view.id) }.getOrDefault("")
    }

    /** Draws a box over each rectangle ("left,top,right,bottom" in window pixels) for a few seconds. */
    fun highlight(rectangles: List<Rect>) {
        val activity = AndroidDebugTools.foregroundActivityOrNull() ?: return
        onMain {
            clearHighlight()
            val decor = activity.window.decorView as? ViewGroup ?: return@onMain
            val overlay = HighlightView(activity, rectangles)
            overlay.layout(0, 0, decor.width, decor.height)
            decor.overlay.add(overlay)
            highlight = overlay
            main.postDelayed({ if (highlight === overlay) clearHighlight() }, HIGHLIGHT_MILLIS)
        }
    }

    fun clearHighlight() {
        onMain {
            val overlay = highlight ?: return@onMain
            (overlay.parent as? ViewGroup)?.overlay?.remove(overlay)
            highlight = null
        }
    }

    private class HighlightView(context: Context, private val rectangles: List<Rect>) : View(context) {
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x33FF3B30 }
        private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFF3B30.toInt()
            style = Paint.Style.STROKE
            strokeWidth = 3f * resources.displayMetrics.density
        }

        override fun onDraw(canvas: Canvas) {
            rectangles.forEach { rect ->
                canvas.drawRect(rect, fill)
                canvas.drawRect(rect, stroke)
            }
        }
    }
}
