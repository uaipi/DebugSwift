import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Copies text to the system pasteboard; SkipFuseUI supplies `UIPasteboard` on Android.
enum DebugClipboard {
    @MainActor static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
