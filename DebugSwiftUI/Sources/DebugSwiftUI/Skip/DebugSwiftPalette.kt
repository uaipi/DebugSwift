package debug.swift.android

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.PixelCopy
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Samples the colors of the foreground window. A pixel copy reads what the screen really shows,
 * Compose and hardware layers included; older systems fall back to drawing the view tree.
 */
object DebugSwiftPalette {
    private const val SAMPLE_WIDTH = 180
    private const val MAX_COLORS = 14

    fun capture(): JSONObject {
        val activity = AndroidDebugTools.foregroundActivityOrNull()
            ?: return JSONObject().put("error", "No foreground activity is available.")
        val decor = activity.window.decorView
        if (decor.width <= 0 || decor.height <= 0) return JSONObject().put("error", "The window has no layout yet.")
        val scale = SAMPLE_WIDTH.toFloat() / decor.width
        val bitmap = Bitmap.createBitmap(SAMPLE_WIDTH, (decor.height * scale).toInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        val copied = Build.VERSION.SDK_INT >= 26 && pixelCopy(activity.window, bitmap)
        if (!copied) {
            val canvas = Canvas(bitmap)
            canvas.scale(scale, scale)
            decor.draw(canvas)
        }
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        bitmap.recycle()
        return JSONObject().put("colors", dominantColors(pixels)).put("source", if (copied) "screen" else "view tree")
    }

    /** The whole window as it is shown, at full size, or null when the system will not copy it. */
    fun windowBitmap(activity: android.app.Activity): Bitmap? {
        val decor = activity.window.decorView
        if (decor.width <= 0 || decor.height <= 0 || Build.VERSION.SDK_INT < 26) return null
        val bitmap = Bitmap.createBitmap(decor.width, decor.height, Bitmap.Config.ARGB_8888)
        if (pixelCopy(activity.window, bitmap)) return bitmap
        bitmap.recycle()
        return null
    }

    private fun pixelCopy(window: android.view.Window, bitmap: Bitmap): Boolean {
        // The callback must not run on the main thread: this call may be waiting on it.
        val thread = HandlerThread("DebugSwiftPixelCopy").apply { start() }
        val finished = CountDownLatch(1)
        var success = false
        return try {
            PixelCopy.request(window, bitmap, { result ->
                success = result == PixelCopy.SUCCESS
                finished.countDown()
            }, Handler(thread.looper))
            finished.await(3, TimeUnit.SECONDS) && success
        } catch (failure: Exception) {
            false
        } finally {
            thread.quitSafely()
        }
    }

    /** Groups pixels by their top five bits per channel, averages each group and ranks by share. */
    private fun dominantColors(pixels: IntArray): JSONArray {
        val sums = HashMap<Int, LongArray>()
        pixels.forEach { pixel ->
            if (Color.alpha(pixel) < 200) return@forEach
            val key = (Color.red(pixel) shr 3 shl 10) or (Color.green(pixel) shr 3 shl 5) or (Color.blue(pixel) shr 3)
            val bucket = sums.getOrPut(key) { LongArray(4) }
            bucket[0] += Color.red(pixel).toLong()
            bucket[1] += Color.green(pixel).toLong()
            bucket[2] += Color.blue(pixel).toLong()
            bucket[3]++
        }
        val total = sums.values.sumOf { it[3] }.coerceAtLeast(1)
        val chosen = mutableListOf<Pair<Int, Long>>()
        sums.values.sortedByDescending { it[3] }.forEach { bucket ->
            val color = Color.rgb((bucket[0] / bucket[3]).toInt(), (bucket[1] / bucket[3]).toInt(), (bucket[2] / bucket[3]).toInt())
            // Skip shades too close to one already taken, so the list shows distinct colors.
            if (chosen.size < MAX_COLORS && chosen.none { distance(it.first, color) < 28 }) chosen += color to bucket[3]
        }
        val result = JSONArray()
        chosen.forEach { (color, count) ->
            result.put(
                JSONObject().put("hex", "#%06X".format(color and 0xFFFFFF)).put("red", Color.red(color))
                    .put("green", Color.green(color)).put("blue", Color.blue(color))
                    .put("percent", count * 100.0 / total)
            )
        }
        return result
    }

    private fun distance(a: Int, b: Int): Double {
        val dr = Color.red(a) - Color.red(b)
        val dg = Color.green(a) - Color.green(b)
        val db = Color.blue(a) - Color.blue(b)
        return Math.sqrt((dr * dr + dg * dg + db * db).toDouble())
    }
}
