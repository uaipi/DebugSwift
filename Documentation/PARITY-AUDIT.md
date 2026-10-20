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
| Performance | 11 | 11 | 3 | 8 | frame drops, hangs, backtraces, leaks, thread checker, super calls, memory warning, widget settings |
| Interface | 9 | 10 | 3 | 7 | view debugger (3D), slow animations toggle, colorize |
| Resources | 9 | 10 | 6 | 4 | realm browser (needs host registry) |
| App | 13 | 13 | 8 | 5 | push simulator, push token, installed libraries, agent debug log |

Android has 53 entries, 29 of them dedicated and 24 generic. Almost all the gap is the generic
screens, not missing features.

## Done so far (verified on an Android 17 emulator)

- Swift network traffic reaches the Kotlin network tools, and the injection rules (delay, HTTP error,
  network error, rewrite) act on Swift requests.
- Resources: files with preview, share and delete; preferences with edit and add; databases with
  tables, paged rows and a SQL console; Keystore aliases; cookies.
- App: crash reports and process exits (no more binary dump), filterable Logcat, deep link opener,
  mock location (confirmed at the OS level on the GPS, network and fused providers), device info,
  custom info and actions, event timeline.
- Performance: live CPU, memory and frame charts, battery, disk throughput.

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
5. **Frames per second reads 0 on an idle screen**, because the Choreographer only counts frames that draw. Left as is.
6. **The earlier notes below describe the state before these fixes.** On iOS a URLProtocol applies delay, failure and
   rewrite rules. On Android the rules are applied only by the OkHttp interceptor.

## Data plumbing (first, because every Network screen depends on it)

Feed completed `DebugSwiftCore.NetworkRecord`s into the Kotlin network store over JNI, so the
inspector, GraphQL, HAR, history and thresholds cover Swift traffic as well as OkHttp. Apply the Core
injection config to Swift requests through the same JNI path. After this, the older Core inspector
duplicates the Kotlin one and can be retired.

## Area by area

### Network (all dedicated)

| Feature | Rating | Remaining work |
| --- | --- | --- |
| http, graphql, har_export, webview_network, network_encryption | Dedicated | feed Swift records (above) |
| websocket | Dedicated | none beyond OkHttp-only capture |
| network_injection | Dedicated | apply rules to Swift requests |
| network_thresholds | Dedicated | count Swift requests |
| network_history | Dedicated | persist Swift records |

### Performance (all generic)

| Feature | iOS | Android today | Plan |
| --- | --- | --- | --- |
| performance_overview | live CPU, memory, FPS charts | text snapshot | SwiftUI `Path` charts fed by a polled snapshot |
| performance_widget | floating metrics | Kotlin overlay | keep Kotlin overlay, add a settings screen |
| battery | level, state, history | instant reading | history list and charts |
| disk | storage size, I/O rates, open descriptors | size and byte counters | rates series, descriptor list |
| memory_warning | trigger and inspect | text and button | result list |
| frame_drops, hangs, backtraces | timeline and stack browser | text | list plus detail screens |
| leaks, thread_checker, super_calls | lists with detail | text | list plus detail screens |

### Interface

| Feature | Rating | Notes |
| --- | --- | --- |
| touches, view_borders, dark_mode, grid | Dedicated | toggles and settings |
| view_hierarchy | Generic | iOS has a 3D view debugger (3.4k lines). Needs an Android layer explorer; Compose or Android View hosted from Swift |
| animation_control | Generic, Gap | iOS toggles slow animations for the app; Android can only open Developer options |
| compose_renders | Generic | needs the host to wrap content in `DebugSwiftComposeProbe` |
| doc_recorder, measurement, color_palette | Generic | interactive overlay screens |

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
| push_simulator | Generic | permission, templates, history screens |
| deep_links | Generic, Gap | add an opener: type a URI and fire the intent |
| location | Generic, Gap | iOS can simulate locations; add mock location via the Android test provider |
| loaded_libraries, event_bus, agent_debug_log | Generic | lists |

### Outside the feature IDs

- **Floating debug button** (iOS): a draggable button that opens the debugger. Android opens from a
  shake or from the host. Add an overlay button in Kotlin.
- **View debugger** (iOS): see `view_hierarchy`.
- **Custom controllers** (iOS `customControllers`): parity already exists in Fuse as `DebugTool`.

## Order of work

1. Data plumbing for Swift network traffic.
2. Resources screens (most used, simplest to make native lists).
3. App screens: crashes, Logcat, location, deep links.
4. Performance charts.
5. Interface: view hierarchy explorer, measurement, color palette, animation control.
6. Floating button.
