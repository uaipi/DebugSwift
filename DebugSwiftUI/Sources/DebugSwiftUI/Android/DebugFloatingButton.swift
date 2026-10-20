import Foundation

/// A draggable round button over the app that opens the debug panel. It exists on Android, where
/// there is no shake gesture to rely on in an emulator; the iOS debugger has its own.
///
/// The person turns it on from the panel, and the choice and the button's position are remembered.
/// The host decides what a tap does:
///
///     DebugFloatingButton.onTap = { isPanelPresented = true }
@MainActor
public enum DebugFloatingButton {
    /// Called when the button is tapped. Open the debug panel here.
    public static var onTap: (@MainActor () -> Void)?

    private static var listener: Task<Void, Never>?

    public static var isEnabled: Bool {
        #if os(Android)
            return DebugSwiftNativeBridge.floatingButtonEnabled()
        #else
            return false
        #endif
    }

    public static func setEnabled(_ enabled: Bool) {
        #if os(Android)
            DebugSwiftNativeBridge.setFloatingButtonEnabled(enabled)
        #endif
    }

    /// Watches for taps. The Kotlin button only records that it was tapped, so this reads that flag.
    static func startListening() {
        #if os(Android)
            guard listener == nil else { return }
            listener = Task { @MainActor in
                while !Task.isCancelled {
                    if DebugSwiftNativeBridge.consumeFloatingButtonTap() { onTap?() }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        #endif
    }
}
