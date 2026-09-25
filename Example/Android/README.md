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

To share exported files from the Android system Sharesheet, merge the sample's `FileProvider` entry into the host app manifest and add `debugswift_file_paths.xml` under `res/xml`. Use authority `${applicationId}.debugswift.fileprovider`, disable provider export, enable URI grants, and expose only app-private `cache-path` and `files-path` locations. The sample manifest and resource file show the exact configuration. Export actions then open the native Android Sharesheet with a read-only content URI.

### Push notification simulation

The Push Notifications tool supports local notifications without an FCM server. Add `POST_NOTIFICATIONS` to the host manifest and enable the simulator before posting. Android 13 and newer request permission at runtime:

```kotlin
AndroidDebugTools.setPushSimulationEnabled(true)
AndroidDebugTools.simulatePushNotification(
    title = "New Message",
    body = "You have a message from Alex",
    subtitle = "Inbox",
    delaySeconds = 3,
    userInfo = mapOf("type" to "message", "sender" to "Alex")
)
AndroidDebugTools.simulatePushNotificationFromTemplate("Message")
AndroidDebugTools.runPushNotificationScenario("messageFlow")
AndroidDebugTools.updatePushNotificationSetting("playSound", "false")
```

The panel's Create action accepts `title|body|delay|subtitle|badge|sound|category|key=value,key2=value2`. Scenarios are `messageFlow`, `newsUpdates`, `marketingCampaign`, `systemAlerts`, or a single `customFlow|title|body|delay`. The History page action browses all retained records in pages of 20; export includes the full history.

Kotlin hosts can also use `simulateMessagePush`, `simulateReminderPush`, `simulateNewsPush`, and `simulateMarketingPush`; manage detailed templates with `addPushNotificationTemplate` and `removePushNotificationTemplate`; and inspect, clear, remove, resend, or mark a notification interacted with through the corresponding `AndroidDebugTools` methods. Delayed local notifications run while the app process remains alive. Configuration, templates, and notification history are stored in app-private preferences.

Use `DebugSwiftAndroidRuntime.log("message")` or `AndroidDebugTools.log("message")` to add app messages to Console. The optional Agent Debug Log can be enabled in the panel; it writes NDJSON to the app-private `files/agent-debug.ndjson` and can be exported from the same screen. The Performance Widget draws live metrics inside the host Activity. Grid spacing and color are set in the Grid Overlay detail, for example `24,#663399FF`.

## Platform equivalents

The debugger category navigation and feature catalogues are shared SwiftUI on iOS and Android. Skip Lite turns those views into Compose on Android. iOS Interface and Resources inspectors, plus App detail tools, keep their existing UIKit implementations behind feature-sized representables. Network and Performance still use their existing iOS category controllers while their Android counterparts use the shared catalogue with Kotlin platform implementations for lifecycle, performance, storage, notifications, and Compose diagnostics.

Android Room/SQLite is the storage equivalent for Core Data and SwiftData. Android Keystore aliases replace Keychain inspection; secret key material remains non-exportable. Some platform data, such as a push token or a Realm schema projection, must be supplied by the host app through the hooks above. Network capture also requires the host networking integration described above.
