package debug.swift.android

/** Kotlin calls used by SwiftUI code transpiled into Kotlin with Skip Lite. */
object DebugSwiftNativeBridge {
    @JvmStatic
    fun snapshot(featureID: String): String = AndroidDebugTools.snapshot(featureID)

    @JvmStatic
    fun perform(featureID: String, actionID: String, value: String): String =
        AndroidDebugTools.perform(featureID, actionID, value)

    @JvmStatic
    fun log(message: String) = AndroidDebugTools.log(message)
}
