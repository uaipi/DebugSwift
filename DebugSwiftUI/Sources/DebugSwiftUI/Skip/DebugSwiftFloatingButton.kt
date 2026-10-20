package debug.swift.android

import android.app.Activity
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.ViewGroup
import android.widget.FrameLayout
import java.util.concurrent.atomic.AtomicBoolean

/**
 * A small round button drawn over the app that can be dragged anywhere. A tap is reported to the host
 * (see [consumeTap]) so it can open its debug panel. The setting and the position survive restarts.
 */
object DebugSwiftFloatingButton {
    private const val PREFS = "DebugSwift.FloatingButton"
    private val tapped = AtomicBoolean(false)
    @Volatile private var enabled: Boolean? = null

    fun isEnabled(context: Context): Boolean =
        enabled ?: context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean("enabled", false).also { enabled = it }

    fun setEnabled(context: Context, value: Boolean) {
        enabled = value
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean("enabled", value).apply()
        val activity = AndroidDebugTools.foregroundActivityOrNull() ?: return
        activity.runOnUiThread { if (value) attach(activity) else detach(activity) }
    }

    /** True once per tap since the last call. */
    fun consumeTap(): Boolean = tapped.getAndSet(false)

    /** Shows the button on this Activity if the setting is on. */
    fun attach(activity: Activity) {
        if (!isEnabled(activity)) return
        val decor = activity.window.decorView as? ViewGroup ?: return
        if (decor.findViewWithTag<View>(TAG) != null) return
        val size = (52 * activity.resources.displayMetrics.density).toInt()
        val button = ButtonView(activity)
        button.tag = TAG
        decor.addView(button, FrameLayout.LayoutParams(size, size, Gravity.TOP or Gravity.START))
        button.post { button.restorePosition(decor) }
    }

    fun detach(activity: Activity) {
        val decor = activity.window.decorView as? ViewGroup ?: return
        decor.findViewWithTag<View>(TAG)?.let(decor::removeView)
    }

    /** True when a screen position (in screen pixels) falls on the button, so it can be told from the app's own touches. */
    fun isOver(activity: Activity, rawX: Float, rawY: Float): Boolean {
        val button = (activity.window.decorView as? ViewGroup)?.findViewWithTag<View>(TAG) ?: return false
        if (button.visibility != View.VISIBLE) return false
        val location = IntArray(2)
        button.getLocationOnScreen(location)
        return rawX >= location[0] && rawX <= location[0] + button.width && rawY >= location[1] && rawY <= location[1] + button.height
    }

    /** Hides the button while something captures the screen, and shows it again after. Main thread only. */
    fun setSuppressed(activity: Activity, suppressed: Boolean) {
        val button = (activity.window.decorView as? ViewGroup)?.findViewWithTag<View>(TAG) ?: return
        button.visibility = if (suppressed) View.INVISIBLE else View.VISIBLE
    }

    private const val TAG = "debugswift.floating.button"

    private class ButtonView(context: Context) : View(context) {
        private val density = resources.displayMetrics.density
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xE61C2128.toInt() }
        private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFBAF146.toInt()
            style = Paint.Style.STROKE
            strokeWidth = 2.5f * density
        }
        private val glyph = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFBAF146.toInt()
            textAlign = Paint.Align.CENTER
            textSize = 22 * density
            isFakeBoldText = true
        }
        private val slop = ViewConfiguration.get(context).scaledTouchSlop
        private var downX = 0f
        private var downY = 0f
        private var originX = 0f
        private var originY = 0f
        private var dragging = false

        init {
            elevation = 8 * density
            contentDescription = "DebugSwift"
        }

        override fun onDraw(canvas: Canvas) {
            val radius = width / 2f
            canvas.drawCircle(radius, radius, radius - ring.strokeWidth, fill)
            canvas.drawCircle(radius, radius, radius - ring.strokeWidth, ring)
            canvas.drawText("D", radius, radius + glyph.textSize / 3f, glyph)
        }

        override fun onTouchEvent(event: MotionEvent): Boolean {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downX = event.rawX
                    downY = event.rawY
                    originX = x
                    originY = y
                    dragging = false
                    parent?.requestDisallowInterceptTouchEvent(true)
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downX
                    val dy = event.rawY - downY
                    if (!dragging && dx * dx + dy * dy > slop * slop) dragging = true
                    if (dragging) {
                        val host = parent as? ViewGroup
                        x = (originX + dx).coerceIn(0f, ((host?.width ?: width) - width).toFloat().coerceAtLeast(0f))
                        y = (originY + dy).coerceIn(0f, ((host?.height ?: height) - height).toFloat().coerceAtLeast(0f))
                    }
                }
                MotionEvent.ACTION_UP -> {
                    if (dragging) savePosition() else {
                        tapped.set(true)
                        performClick()
                    }
                }
            }
            return true
        }

        private fun savePosition() {
            val host = parent as? ViewGroup ?: return
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putFloat("x", x / host.width.coerceAtLeast(1)).putFloat("y", y / host.height.coerceAtLeast(1)).apply()
        }

        fun restorePosition(host: ViewGroup) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            // Right edge, a bit below the top, until the person has moved it.
            x = (prefs.getFloat("x", 0.82f) * host.width).coerceIn(0f, (host.width - width).toFloat().coerceAtLeast(0f))
            y = (prefs.getFloat("y", 0.2f) * host.height).coerceIn(0f, (host.height - height).toFloat().coerceAtLeast(0f))
        }
    }
}
