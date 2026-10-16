import Foundation
import DebugSwiftAndroid
import SwiftUI

/// The shared top-level view for the app, loaded from the platform-specific App delegates below.
///
/// The default implementation merely loads the `ContentView` for the app and logs a message.
public struct DebugSwiftAndroidSampleRootView : View {
    public init() {
    }

    public var body: some View {
        DebugSwiftAndroidPanel()
    }
}

/// Global application delegate functions.
///
/// These functions can update a shared observable object to communicate app state changes to interested views.
public final class DebugSwiftAndroidSampleAppDelegate : Sendable {
    public static let shared = DebugSwiftAndroidSampleAppDelegate()

    private init() {
    }

    public func onInit() {
    }

    public func onLaunch() {
        DebugSwiftAndroidRuntime.log("Example app launched")
    }

    public func onResume() {
    }

    public func onPause() {
    }

    public func onStop() {
    }

    public func onDestroy() {
    }

    public func onLowMemory() {
    }
}
