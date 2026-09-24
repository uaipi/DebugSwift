# DebugSwift Android sample

This sample consumes the `DebugSwiftAndroid` Skip Lite package and renders its shared SwiftUI panel as native Android Compose UI. On iOS, the same entry point can present the existing UIKit debugger through `UIViewControllerRepresentable`.

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

The Skip module lives in `DebugSwiftAndroid/`. Add it as a local Swift package dependency and use `DebugSwiftAndroidPanel()` as the app’s shared SwiftUI root. The sample package and Android Activity show how Skip generates the Compose host.

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

## Platform equivalents

The app screens and navigation are SwiftUI shared through Skip Lite. UIKit remains the iOS implementation for debugger screens that use UIKit APIs. Android uses platform implementations for lifecycle, performance, overlays, storage, notifications, and Compose diagnostics.

Android Room/SQLite is the storage equivalent for Core Data and SwiftData. Android Keystore aliases replace Keychain inspection; secret key material remains non-exportable. Some platform data, such as a push token or a Realm schema projection, must be supplied by the host app through the hooks above. Network capture also requires the host networking integration described above.
