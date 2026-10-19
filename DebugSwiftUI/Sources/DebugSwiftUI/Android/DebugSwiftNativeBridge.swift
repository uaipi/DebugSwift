#if os(Android)
import SkipFuse

/// JNI access to the Kotlin tools that have no Swift equivalent on Android. Every call takes and
/// returns strings, the same contract the Kotlin `DebugSwiftNativeBridge` object exposes.
///
/// Each return type is spelled out in its own function: the generic `callStatic` picks its JNI call
/// from the static type, and an optional or generic one lands on the object variant, which the VM
/// aborts on for a primitive return.
enum DebugSwiftNativeBridge {
    private static let className = "debug/swift/android/DebugSwiftNativeBridge"

    /// Installs the Kotlin runtime once, from the running process.
    static func install() -> Bool {
        guard isJNIInitialized else { return false }
        do {
            return try jniContext {
                let javaClass = try JClass(name: className)
                guard let id = javaClass.getStaticMethodID(name: "installFromProcess", sig: "()Z") else {
                    return false
                }
                let installed: Bool = try javaClass.callStatic(method: id, options: [], args: [])
                return installed
            }
        } catch {
            return false
        }
    }

    static func string(_ method: String, _ args: String...) -> String {
        guard isJNIInitialized else { return "" }
        let signature = "(" + String(repeating: "Ljava/lang/String;", count: args.count) + ")Ljava/lang/String;"
        do {
            return try jniContext {
                let javaClass = try JClass(name: className)
                guard let id = javaClass.getStaticMethodID(name: method, sig: signature) else { return "" }
                let value: String = try javaClass.callStatic(
                    method: id,
                    options: [],
                    args: args.map { $0.toJavaParameter(options: []) },
                )
                return value
            }
        } catch {
            return ""
        }
    }
}
#endif
