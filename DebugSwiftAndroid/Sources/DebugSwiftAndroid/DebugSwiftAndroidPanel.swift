import Foundation

import SwiftUI

#if os(Android)
import debug.swift.android.DebugSwiftNativeBridge
#endif

#if os(iOS)
import DebugSwift
import UIKit
#endif

/// Shared SwiftUI entry point compiled for Android with Skip Lite.
public struct DebugSwiftAndroidPanel: View {
    public init() {}

    public var body: some View {
        DebugSwiftAndroidPanelContent()
    }
}

private struct DebugSwiftAndroidPanelContent: View {
    @State var selectedArea: DebugSwiftArea = .network

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visibleAreas) { area in
                        Button {
                            selectedArea = area
                        } label: {
                            Text(area.title)
                                .font(Font.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .foregroundColor(selectedArea == area ? Color.white : Color.primary)
                                .background(selectedArea == area ? Color.accentColor : Color.secondary.opacity(0.18))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }

            #if os(iOS)
            DebugSwiftIOSFeatureHost(area: selectedArea)
                .id(selectedArea.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            NavigationStack {
                DebugSwiftFeatureList(area: selectedArea)
                    .navigationTitle(selectedArea.title)
            }
            .id(selectedArea.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
        .preferredColorScheme(ColorScheme.dark)
    }

    var visibleAreas: [DebugSwiftArea] {
        #if os(iOS)
        let visibleIDs = Set(DebugSwift.availableDebugFeatures().map(\.rawValue))
        return DebugSwiftArea.allCases.filter { visibleIDs.contains($0.id) }
        #else
        return DebugSwiftArea.allCases
        #endif
    }
}

enum DebugSwiftArea: String, CaseIterable, Identifiable, Hashable {
    case network
    case performance
    case interface
    case resources
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .network: "Network"
        case .performance: "Performance"
        case .interface: "Interface"
        case .resources: "Resources"
        case .app: "App"
        }
    }

    var symbol: String {
        switch self {
        case .network: "point.3.connected.trianglepath.dotted"
        case .performance: "speedometer"
        case .interface: "rectangle.3.group"
        case .resources: "folder"
        case .app: "app.badge"
        }
    }

    var features: [DebugSwiftTool] {
        switch self {
        case .network:
            [
                .init("http", "HTTP Inspector", "Capture requests and responses, inspect bodies, filter traffic, and export request history."),
                .init("websocket", "WebSocket Inspector", "Inspect WebSocket connections, sent frames, and received frames."),
                .init("network_injection", "Network Injection", "Add request delay, failure, HTTP errors, and response body rewrite rules."),
                .init("network_thresholds", "Request Thresholds", "Count requests in a time window and optionally block after the limit."),
                .init("graphql", "GraphQL Inspector", "Identify GraphQL operations and inspect operation names and variables."),
                .init("network_encryption", "Response Decryption", "Register a URL-matched AES-GCM key for base64 response bodies."),
                .init("har_export", "HAR Export", "Export captured requests and responses as an HTTP Archive."),
                .init("webview_network", "WebView Network", "Capture navigation and resource requests made by embedded browser views."),
                .init("network_history", "Session History", "Search saved network sessions and export or clear their request history.")
            ]
        case .performance:
            [
                .init("performance_overview", "Live Metrics", "Track CPU, memory, frames per second, and process activity."),
                .init("performance_widget", "Performance Widget", "Show live CPU, memory, and slow-frame metrics over the host app."),
                .init("battery", "Battery", "Inspect battery level, charging state, and power source."),
                .init("disk", "Disk I/O", "Inspect app storage size and process read/write byte counters."),
                .init("frame_drops", "Frame Drops", "Record slow frames and inspect their timing on a timeline."),
                .init("hangs", "Hangs and ANRs", "Detect main thread stalls and inspect captured stack traces."),
                .init("backtraces", "Backtraces", "Capture and browse call stacks on demand."),
                .init("leaks", "Leak Detection", "Find destroyed Android Activities that remain reachable after a grace period."),
                .init("thread_checker", "Thread Checker", "Capture Android StrictMode thread and VM violations."),
                .init("super_calls", "Lifecycle Super Calls", "Review lifecycle callback violations reported by the platform.")
            ]
        case .interface:
            [
                .init("view_hierarchy", "View Hierarchy", "Inspect the active Android view tree and its measured bounds."),
                .init("grid", "Grid Overlay", "Draw a configurable alignment grid over the current app window."),
                .init("touches", "Touch Indicators", "Record touch locations and show visual feedback during interactions."),
                .init("view_borders", "View Borders", "Outline visible native views to locate spacing and clipping issues."),
                .init("animation_control", "Animation Settings", "Inspect the system animation scales and open Android Developer options to change them."),
                .init("compose_renders", "Compose Render Tracking", "Record Compose composition activity and retain render counts."),
                .init("doc_recorder", "Documentation Recorder", "Capture taps and scrolls, then save a screenshot annotated with numbered markers and arrows."),
                .init("measurement", "Measurement Tool", "Inspect element positions, sizes, and spacing in the active window."),
                .init("color_palette", "Color Palette", "Sample colors from a captured screen image and export the palette.")
            ]
        case .resources:
            [
                .init("files", "File Browser", "Browse the app sandbox, databases, cache, and exported files."),
                .init("preferences", "Preferences", "View and update registered Android SharedPreferences values."),
                .init("keychain", "Secure Storage", "Inspect aliases in Android Keystore without exposing private key material."),
                .init("sqlite", "Database Browser", "Browse SQLite tables, rows, and run SQL queries."),
                .init("realm", "Realm Browser", "Inspect Realm databases registered by the host app."),
                .init("core_data", "Room Database", "Browse the Android database layer, including registered Room databases."),
                .init("swift_data", "Object Store", "Inspect SQLite or Room storage used in place of SwiftData on Android."),
                .init("cookies", "HTTP Cookies", "Inspect WebView cookies for app-owned domains."),
                .init("security_audit", "Security Audit", "Find sensitive-looking keys in registered preferences and app-private text files.")
            ]
        case .app:
            [
                .init("crashes", "Crash Reports", "Save uncaught application crashes with stack traces and timestamps."),
                .init("console", "Console", "View, clear, and export messages written through the DebugSwift logger."),
                .init("device_info", "Device Info", "Inspect app version, Android version, device, display, and memory details."),
                .init("push_token", "Push Token", "Register and display an app-provided Firebase Cloud Messaging token."),
                .init("push_simulator", "Push Simulator", "Create local notification scenarios for app testing."),
                .init("custom_actions", "Custom Actions", "Register host-app actions and run them from the debugger."),
                .init("custom_info", "Custom Info", "Display diagnostic values supplied by the host app."),
                .init("deep_links", "Deep Links", "Inspect the current intent URI and registered app link information."),
                .init("loaded_libraries", "Installed Libraries", "Inspect installed DEX splits, native library paths, ABIs, and the runtime class loader."),
                .init("location", "Location", "Inspect the last location reported by the host app."),
                .init("event_bus", "Event Timeline", "Browse network, performance, interface, app, and resource events."),
                .init("agent_debug_log", "Agent Debug Log", "Stream app events, network activity, console messages, and crashes to an NDJSON file.")
            ]
        }
    }
}

struct DebugSwiftTool: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String

    init(_ id: String, _ title: String, _ summary: String) {
        self.id = id
        self.title = title
        self.summary = summary
    }
}

struct DebugSwiftFeatureList: View {
    let area: DebugSwiftArea

    var body: some View {
        List(area.features) { feature in
            NavigationLink {
                DebugSwiftFeatureDetail(feature: feature)
                    .navigationTitle(feature.title)
            } label: {
                VStack(alignment: HorizontalAlignment.leading, spacing: 5) {
                    Text(feature.title)
                        .font(Font.headline)
                    Text(feature.summary)
                        .font(Font.caption)
                        .foregroundColor(Color.secondary)
                }
                .padding(Edge.Set.vertical, 4)
            }
        }
    }
}

struct DebugSwiftFeatureDetail: View {
    let feature: DebugSwiftTool
    @State var output = ""
    @State var command = ""

    var body: some View {
        ScrollView {
            VStack(alignment: HorizontalAlignment.leading, spacing: 16) {
                Text(feature.summary)
                    .font(Font.body)

                if let inputHint {
                    TextField(inputHint, text: $command)
                }

                ForEach(actionIDs, id: \.self) { actionID in
                    Button(actionTitle(actionID)) {
                        if actionID == "refresh" {
                            refresh()
                        } else {
                            output = DebugSwiftAndroidRuntime.perform(featureID: feature.id, actionID: actionID, value: command)
                        }
                    }
                }

                Text("Live data")
                    .font(Font.headline)
                Text(output.isEmpty ? "Loading…" : output)
                    .font(Font.system(Font.TextStyle.footnote, design: Font.Design.monospaced))
                    .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                #if os(iOS)
                Text("The original UIKit debugger is available from the bug icon in the tab bar.")
                    .font(Font.caption)
                    .foregroundColor(Color.secondary)
                #endif
            }
            .padding()
        }
        .onAppear { refresh() }
    }

    func refresh() {
        output = DebugSwiftAndroidRuntime.snapshot(featureID: feature.id)
    }

    var actionIDs: [String] {
        switch feature.id {
        case "http":
            ["refresh", "filter_requests", "clear", "export"]
        case "websocket", "har_export", "console", "crashes", "backtraces", "event_bus":
            ["refresh", "capture", "clear", "export"]
        case "agent_debug_log":
            ["refresh", "toggle", "clear", "export"]
        case "graphql", "network_history":
            ["refresh", "filter_requests", "clear", "export"]
        case "network_injection":
            ["refresh", "set_delay", "inject_failure", "set_http_error", "rewrite_response", "block_url", "toggle"]
        case "network_thresholds":
            ["refresh", "set_threshold", "toggle"]
        case "network_encryption":
            ["refresh", "register_key", "clear_keys"]
        case "preferences":
            ["refresh", "set_preference"]
        case "files":
            ["refresh", "browse_files", "export"]
        case "realm":
            ["refresh", "export"]
        case "sqlite", "core_data", "swift_data":
            ["refresh", "run_query", "export"]
        case "grid":
            ["refresh", "set_grid", "toggle", "capture"]
        case "doc_recorder":
            ["refresh", "capture", "clear", "export"]
        case "color_palette":
            ["refresh", "capture", "clear", "export"]
        case "animation_control":
            ["refresh", "open_animation_settings"]
        case "touches", "view_borders", "thread_checker", "performance_widget":
            ["refresh", "toggle", "capture"]
        case "push_simulator":
            ["refresh", "notify"]
        case "custom_actions":
            ["refresh", "run_custom"]
        case "custom_info":
            ["refresh", "report_info"]
        default:
            ["refresh", "capture"]
        }
    }

    var inputHint: String? {
        switch feature.id {
        case "http", "graphql", "network_history": "Filter requests by URL, method, or body"
        case "network_injection": "Value: ms, status, pattern=>body, or URL pattern"
        case "network_thresholds": "Request limit,window seconds"
        case "network_encryption": "URL regex:base64 AES key (body is base64 nonce + AES-GCM ciphertext)"
        case "grid": "Spacing dp, optional color: 24,#663399FF"
        case "preferences": "Store|key=value"
        case "files": "App path: files/, cache/, or databases/"
        case "push_simulator": "Notification title | message | delay in seconds"
        case "sqlite", "core_data", "swift_data": "Database name|SQL statement"
        case "custom_actions": "Registered action title"
        case "custom_info": "Name=value"
        default: nil
        }
    }

    func actionTitle(_ actionID: String) -> String {
        switch actionID {
        case "refresh": "Refresh"
        case "capture": "Capture"
        case "clear": "Clear history"
        case "export": "Export"
        case "filter_requests": "Apply filter"
        case "toggle": feature.id == "network_thresholds" ? "Toggle request blocking" : feature.id == "agent_debug_log" ? "Start / stop capture" : "Enable / disable"
        case "set_delay": "Set request delay"
        case "inject_failure": "Fail next request"
        case "set_http_error": "Set HTTP error code"
        case "rewrite_response": "Add response rewrite"
        case "block_url": "Block URL pattern"
        case "clear_keys": "Clear decryption keys"
        case "set_threshold": "Set request threshold"
        case "register_key": "Register AES key"
        case "set_grid": "Set grid spacing and color"
        case "set_preference": "Write preference"
        case "browse_files": "Open path"
        case "notify": "Post test notification"
        case "open_animation_settings": "Open Developer options"
        case "run_query": "Run SQL query"
        case "run_custom": "Run registered action"
        case "report_info": "Save diagnostic value"
        default: actionID
        }
    }
}

/// Platform facade used by the shared panel and by Android host integrations.
public enum DebugSwiftAndroidRuntime {
    #if os(iOS)
    @MainActor private static var isIOSDebuggerPrepared = false

    @MainActor
    static func prepareIOSDebugger() {
        guard !isIOSDebuggerPrepared else { return }
        DebugSwift().setup()
        isIOSDebuggerPrepared = true
    }
    #endif

    public static func log(_ message: String) {
        #if os(Android)
        DebugSwiftNativeBridge.log(message)
        #else
        NSLog("[DebugSwiftAndroid] %@", message)
        #endif
    }

    public static func snapshot(featureID: String) -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.snapshot(featureID)
        #else
        return "Use the UIKit debugger on iOS to inspect live app data."
        #endif
    }

    public static func perform(featureID: String, actionID: String, value: String = "") -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.perform(featureID, actionID, value)
        #else
        return "Open the UIKit debugger on iOS to run this tool."
        #endif
    }
}

#if os(iOS)
private struct DebugSwiftIOSFeatureHost: UIViewControllerRepresentable {
    let area: DebugSwiftArea

    func makeUIViewController(context: Context) -> UIViewController {
        DebugSwiftAndroidRuntime.prepareIOSDebugger()
        let feature = DebugSwiftFeature(rawValue: area.id) ?? .network
        return DebugSwift.debugFeatureViewController(for: feature)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#endif
