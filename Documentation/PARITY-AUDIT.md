# iOS and Android parity audit

Goal: every DebugSwift capability works on iOS and on Android, with the same shape of screen, and the
code stays in Skip Fuse (Swift) wherever it can. Compose, Android views or Kotlin are used only where
Swift cannot reach the platform.

How each Android entry is rated:

- **Dedicated**: a purpose-built SwiftUI screen, comparable to the iOS one.
- **Generic**: the shared detail screen (a text snapshot plus Refresh/Capture/Export buttons and one
  input field). It runs, but it is not the iOS experience.
- **Gap**: the iOS capability does not exist on Android yet.

The state below was measured on an Android 17 emulator by opening every entry of the Voltrace debug
panel: 52 of 52 entries opened without crashing the app. This says the screens load and render;
it does not say each button does what the iOS one does.

## Summary

| Area | iOS entries | Android entries | Dedicated | Generic | Capability gaps |
| --- | --- | --- | --- | --- | --- |
| Network | 9 | 9 | 9 | 0 | none known |
| Performance | 11 | 11 | 11 | 0 | none known; the rates on the Disk screen are process wide |
| Interface | 9 | 10 | 10 | 0 | no 3D view debugger |
| Resources | 9 | 10 | 10 | 0 | the Realm browser shows only what the host registers, since Realm lives on the JVM |
| App | 13 | 13 | 13 | 0 | none known |

Android has 53 entries and every one has a dedicated screen.

## Done so far (verified on an Android 17 emulator)

- Swift network traffic reaches the Kotlin network tools, and the injection rules (delay, HTTP error,
  network error, rewrite) act on Swift requests.
- Resources: files with preview, share and delete; preferences with edit and add; databases with
  tables, paged rows and a SQL console; Keystore aliases; cookies.
- App: crash reports and process exits (no more binary dump), filterable Logcat, deep link opener,
  mock location (confirmed at the OS level on the GPS, network and fused providers), device info,
  custom info and actions, event timeline.
- Performance: live CPU, memory and frame charts, battery, disk throughput, slow frame timeline, main
  thread stalls with the stack the thread was stuck in, ANR reports, backtraces of the main thread or
  all threads, retained Activities with a GC recheck, StrictMode violations, memory warning
  simulation and the on-screen widget.
- Push: a simulator that posts real notifications (scenarios, templates, behavior options, a live
  history with per-entry actions), and the registration token with a copy button; Voltrace reports
  its Firebase token to it.
- Installed libraries from the process maps and from the APK, the agent debug log with capture on and
  off and the newest entries, and the Realm browser for what the host registers.
- Floating debug button: a draggable button over the app that opens the panel. The setting and the
  position are remembered, and taps on it are kept out of the recorded gestures.
- Interface: a window tree with Android views and Compose semantics (text, description, test tag,
  clicks), a highlight drawn in the app, a measurement tool that gives the gap between two
  elements, a color palette sampled from the screen, the system animation scales, a live
  recomposition rate for Compose that needs no wrapper in the host's UI, and the documentation
  recorder (taps and scrolls are captured by the library itself, and the screenshot is a pixel copy).

## Known defects found while testing

1. **Crash Reports shows raw binary.** Fixed. Recent Android process exits include the tombstone protobuf
   verbatim, so the screen prints control characters (and crashes `uiautomator` when it reads them).
   The exit record should show reason, description, time and a decoded abort message only.
2. **Swift traffic is invisible to the Kotlin network tools.** Fixed. Capture on Android hooks OkHttp and
   WebView. An app whose networking is Swift (Foundation on Android, like Voltrace) never reaches
   them, so HTTP, GraphQL, HAR, history and thresholds look empty even while requests happen. The
   Core-based inspector (`NetworkInspectorView`) does see that traffic.
3. **Network injection cannot touch Swift networking.** Fixed; the host wraps its transport call in `NetworkInjection.apply`.
4. **A saved rewrite rule with no method never matched after a restart** (org.json read a JSON null as the string "null"). Fixed.
5. **The hang detector sampled the wrong stack.** It read the main thread after the thread had recovered, so every stall pointed at the detector itself. Fixed: the stack is sampled while the thread is still stuck.
6. **Frames per second reads 0 on an idle screen**, because the Choreographer only counts frames that draw. Left as is.

Before the fix, injection rules were applied only by the OkHttp interceptor; on iOS a URL protocol
applies them to every session.

## Data plumbing (done)

Completed `DebugSwiftCore.NetworkRecord`s are fed into the Kotlin network store over JNI, so the
inspector, GraphQL, HAR, history and thresholds cover Swift traffic as well as OkHttp. The injection
rules reach Swift requests through the same path. The older Core inspector now duplicates the Kotlin
one and can be retired.

## Area by area

### Network (all dedicated)

| Feature | Rating | Remaining work |
| --- | --- | --- |
| http, graphql, har_export, webview_network, network_encryption | Dedicated | feed Swift records (above) |
| websocket | Dedicated | none beyond OkHttp-only capture |
| network_injection | Dedicated | apply rules to Swift requests |
| network_thresholds | Dedicated | count Swift requests |
| network_history | Dedicated | persist Swift records |

### Performance (all dedicated)

| Feature | Rating | Notes |
| --- | --- | --- |
| performance_overview, battery, disk | Dedicated | live charts; battery and disk keep history only while the screen is open |
| frame_drops | Dedicated | summary, sparkline and a timeline of slow frames. Reads 0 fps on an idle screen |
| hangs | Dedicated | stalls with the stack sampled while the main thread was stuck, plus Android ANR reports |
| backtraces | Dedicated | main thread or all threads |
| leaks | Dedicated | reachability heuristic with a GC recheck; confirm with the Memory Profiler |
| thread_checker | Dedicated | StrictMode on or off and the recorded violations |
| super_calls, memory_warning, performance_widget | Dedicated | |

### Interface

| Feature | Rating | Notes |
| --- | --- | --- |
| touches, view_borders, dark_mode, grid | Dedicated | toggles and settings |
| view_hierarchy | Dedicated | tree of views and Compose semantics with element detail and a highlight in the app. No 3D view, and Compose layout nodes without semantics are not listed |
| measurement | Dedicated | pick two elements, read gaps, centers and size difference in dp |
| color_palette | Dedicated | dominant colors from a pixel copy of the window; tap to copy a hex value |
| animation_control | Dedicated | sets the three system scales when `WRITE_SECURE_SETTINGS` is granted by adb; otherwise slows View animations in the app and says what is missing |
| compose_renders | Dedicated | recompositions per second and totals for the whole app; a `DebugSwiftComposeProbe` still counts one screen |
| doc_recorder | Dedicated | start recording, close the panel, use the app, capture a screenshot numbered with each tap and scroll |

### Resources

| Feature | Rating | Plan |
| --- | --- | --- |
| security_audit | Dedicated | none |
| files | Generic | browsable list, preview, share, delete |
| preferences, persistent_data | Generic | key/value list with edit, replacing the `Store|key=value` text field |
| keychain (Keystore) | Generic | alias list with detail |
| sqlite, core_data (Room), swift_data (object store), realm | Generic | table and row browsers, SQL console |
| cookies | Generic | list with detail and delete |

### App

| Feature | Rating | Plan |
| --- | --- | --- |
| console | Dedicated | none |
| crashes | Generic | list and detail, fix defect 1 |
| oslog_console (Logcat) | Generic | filterable list |
| device_info, push_token, custom_info, custom_actions | Generic | simple lists. Host custom actions already have a native Swift route through `DebugTool` and `DebugActionGroup` in the panel |
| push_simulator | Dedicated | permission, send, scenarios, templates, behavior options and history |
| deep_links | Generic, Gap | add an opener: type a URI and fire the intent |
| location | Generic, Gap | iOS can simulate locations; add mock location via the Android test provider |
| loaded_libraries, event_bus, agent_debug_log | Dedicated | mapped files, packed native libraries, capture state and newest entries |

### Outside the feature IDs

- **Floating debug button** (iOS): done on Android as `DebugFloatingButton`. The host sets `onTap` to
  open its panel; the person turns it on from the panel.
- **View debugger** (iOS): see `view_hierarchy`.
- **Custom controllers** (iOS `customControllers`): parity already exists in Fuse as `DebugTool`.

## Order of work

1. Data plumbing for Swift network traffic.
2. Resources screens (most used, simplest to make native lists).
3. App screens: crashes, Logcat, location, deep links.
4. Performance charts.
5. Interface: view hierarchy explorer, measurement, color palette, animation control.
6. Floating button (done).
