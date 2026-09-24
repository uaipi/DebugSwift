# DebugSwift Android sample

This sample consumes the `DebugSwiftAndroid` product from the main DebugSwift package and renders its SwiftUI panel as native Android Compose UI. The same category navigation runs on iOS; existing feature screens stay in UIKit behind one `UIViewControllerRepresentable` per category while they are migrated to shared SwiftUI.

## Build the sample

Install Xcode, the Skip CLI, Android Studio, and an Android SDK. Then run:

```sh
skip export --project Example/Android --no-ios --android --arch aarch64 --dir build/skip-android
```

The export directory contains debug and release APK/AAB artifacts. Install the debug APK on a connected device or emulator with:

```sh
adb install -r build/skip-android/DebugSwiftAndroidSample-debug.apk
```

## Add the debugger to an Android host app

The `DebugSwiftAndroid` product is part of the repository’s root Swift package. Add the DebugSwift repository as a Swift package dependency, add the `DebugSwiftAndroid` product, and use `DebugSwiftAndroidPanel()` as the app’s shared SwiftUI root. The sample package and Android Activity show how Skip generates the Compose host.

Install the runtime once from the host `Application`:

```kotlin
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        AndroidDebugTools.install(this)
        AndroidDebugTools.registerPreferences("user_preferences")
        DebugSwiftDatabaseBrowser.registerRoomDatabase("app_database")
    }
}
```

Add `DebugSwiftOkHttpInterceptor()` to each OkHttp client whose traffic should be captured. Wrap WebSocket listeners with `DebugSwiftWebSocketListener(url, listener)`; route outgoing frames through its `sendText` and `sendBinary` helpers as well. Install `DebugSwiftWebViewClient` on host WebViews. Android cannot intercept every networking stack globally, so clients using a different stack need an equivalent integration hook.

The runtime also exposes host hooks for custom actions and diagnostic values (`registerAction`, `registerInfo`), FCM tokens (`reportPushToken`), location (`reportLocation`), Room databases, and Realm projections (`DebugSwiftRealmRegistry.register`). Forward Activity touch events to `AndroidDebugTools.recordTouch(event)` and wrap a Compose subtree in `DebugSwiftComposeProbe` to collect those interface diagnostics.

Use `DebugSwiftAndroidRuntime.log("message")` or `AndroidDebugTools.log("message")` to add app messages to Console. The optional Agent Debug Log can be enabled in the panel; it writes NDJSON to the app-private `files/agent-debug.ndjson` and can be exported from the same screen. The Performance Widget draws live metrics inside the host Activity. Grid spacing and color are set in the Grid Overlay detail, for example `24,#663399FF`.

## Platform equivalents

The debugger category navigation is shared SwiftUI on iOS and Android. Skip Lite turns the Android SwiftUI screens into Compose; Android uses Kotlin platform implementations for lifecycle, performance, overlays, storage, notifications, and Compose diagnostics. iOS UIKit screens are contained behind category-sized representables, which lets each compatible screen move to shared SwiftUI without rewriting platform-only inspectors.

Android Room/SQLite is the storage equivalent for Core Data and SwiftData. Android Keystore aliases replace Keychain inspection; secret key material remains non-exportable. Some platform data, such as a push token or a Realm schema projection, must be supplied by the host app through the hooks above. Network capture also requires the host networking integration described above.
