package debug.swift.android

import android.app.Activity
import android.view.MotionEvent
import android.view.Window

/**
 * Feeds every touch the window receives to the debug tools, so touch indicators and the documentation
 * recorder work without the host forwarding events from its Activity.
 */
object DebugSwiftTouchCapture {
    fun install(activity: Activity) {
        val window = activity.window
        val current = window.callback ?: return
        if (current is Forwarding) return
        window.callback = Forwarding(current, activity)
    }

    private class Forwarding(private val original: Window.Callback, private val activity: Activity) : Window.Callback by original {
        /** A gesture that starts on the floating button belongs to the debugger, not the app. */
        private var ignoring = false

        override fun dispatchTouchEvent(event: MotionEvent): Boolean {
            if (event.actionMasked == MotionEvent.ACTION_DOWN) {
                ignoring = DebugSwiftFloatingButton.isOver(activity, event.rawX, event.rawY)
            }
            if (!ignoring) runCatching { AndroidDebugTools.recordTouch(event) }
            return original.dispatchTouchEvent(event)
        }
    }
}
