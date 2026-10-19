import Foundation

/// Platform facade for the Kotlin tools. On Android it calls them through JNI; on iOS the native
/// DebugSwift screens provide the same features, so nothing is available here.
enum DebugAndroidTools {
    static let isAvailable: Bool = {
        #if os(Android)
            return DebugSwiftNativeBridge.install()
        #else
            return false
        #endif
    }()

    static func snapshot(_ featureID: String) -> String {
        #if os(Android)
            return DebugSwiftNativeBridge.string("snapshot", featureID)
        #else
            return ""
        #endif
    }
}
