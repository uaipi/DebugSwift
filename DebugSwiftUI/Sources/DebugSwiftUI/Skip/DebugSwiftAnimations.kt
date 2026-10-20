package debug.swift.android

import android.content.Context
import android.content.pm.PackageManager
import android.provider.Settings
import org.json.JSONObject

/**
 * The three system animation scales. Changing them system-wide needs the WRITE_SECURE_SETTINGS
 * permission, which only adb can grant; without it, View animations can still be slowed in this
 * process, and Compose animations cannot.
 */
object DebugSwiftAnimations {
    private val keys = listOf(
        Settings.Global.WINDOW_ANIMATION_SCALE,
        Settings.Global.TRANSITION_ANIMATION_SCALE,
        Settings.Global.ANIMATOR_DURATION_SCALE
    )

    private fun canWriteSettings(context: Context) =
        context.checkSelfPermission("android.permission.WRITE_SECURE_SETTINGS") == PackageManager.PERMISSION_GRANTED

    fun state(context: Context): JSONObject {
        val resolver = context.contentResolver
        fun scale(key: String) = runCatching { Settings.Global.getFloat(resolver, key, 1f) }.getOrDefault(1f).toDouble()
        return JSONObject()
            .put("window", scale(Settings.Global.WINDOW_ANIMATION_SCALE))
            .put("transition", scale(Settings.Global.TRANSITION_ANIMATION_SCALE))
            .put("animator", scale(Settings.Global.ANIMATOR_DURATION_SCALE))
            .put("canWriteSystem", canWriteSettings(context))
            .put("packageName", context.packageName)
    }

    fun set(context: Context, scale: Float): JSONObject {
        val value = scale.coerceIn(0f, 10f)
        if (canWriteSettings(context)) {
            keys.forEach { Settings.Global.putFloat(context.contentResolver, it, value) }
            return state(context).put("message", "Set all animation scales to ${value}×, system-wide.")
        }
        val applied = runCatching {
            android.animation.ValueAnimator::class.java.getMethod("setDurationScale", Float::class.javaPrimitiveType).invoke(null, value)
        }.isSuccess
        val message = if (applied) {
            "Slowed View animations in this app to ${value}×. Compose animations need the system setting: " +
                "run adb shell pm grant ${context.packageName} android.permission.WRITE_SECURE_SETTINGS and try again."
        } else {
            "Android would not change the animation speed. Grant the permission with adb shell pm grant " +
                "${context.packageName} android.permission.WRITE_SECURE_SETTINGS, or use Developer options."
        }
        return state(context).put("message", message)
    }
}
