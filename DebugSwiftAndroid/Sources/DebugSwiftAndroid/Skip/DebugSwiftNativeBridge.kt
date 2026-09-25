package debug.swift.android

/** Kotlin calls used by SwiftUI code transpiled into Kotlin with Skip Lite. */
object DebugSwiftNativeBridge {
    @JvmStatic
    fun snapshot(featureID: String): String = AndroidDebugTools.snapshot(featureID)

    @JvmStatic
    fun securityAuditSnapshot(): String = AndroidDebugTools.securityAuditSnapshot()

    @JvmStatic
    fun perform(featureID: String, actionID: String, value: String): String =
        AndroidDebugTools.perform(featureID, actionID, value)

    @JvmStatic
    fun gridSettings(): String = AndroidDebugTools.gridSettings()

    @JvmStatic
    fun setGridSettings(value: String): String = AndroidDebugTools.setGridSettings(value)

    @JvmStatic
    fun interfaceToolEnabled(featureID: String): Boolean =
        AndroidDebugTools.interfaceToolEnabled(featureID)

    @JvmStatic
    fun setInterfaceToolEnabled(featureID: String, enabled: Boolean): String =
        AndroidDebugTools.setInterfaceToolEnabled(featureID, enabled)

    @JvmStatic
    fun log(message: String) = AndroidDebugTools.log(message)
}
