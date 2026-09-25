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
            if selectedArea == .interface || selectedArea == .resources {
                NavigationStack {
                    DebugSwiftFeatureList(area: selectedArea)
                        .navigationTitle(selectedArea.title)
                }
                .id(selectedArea.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DebugSwiftIOSFeatureHost(area: selectedArea)
                    .id(selectedArea.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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

    @MainActor
    var features: [DebugSwiftTool] {
        switch self {
        case .network:
            return [
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
            return [
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
            #if os(iOS)
            let availableIDs = Set(DebugSwift.availableInterfaceFeatureIDs())
            return [
                .init("touches", "Showing touches", "Show touch feedback in the active app window."),
                .init("grid", "Grid overlay", "Draw a configurable alignment grid over the active app window."),
                .init("colorize", "Colorized view borders", "Colorize native view borders to help identify layout boundaries."),
                .init("animations", "Slow animations", "Slow app animations to inspect transitions and motion."),
                .init("dark_mode", "Dark Mode", "Override the active app window appearance."),
                .init("measurement", "UI measurements", "Show element positions, sizes, and spacing."),
                .init("swiftui_render", "SwiftUI render tracking", "Track SwiftUI rendering activity."),
                .init("doc_recorder", "Documentation Recorder", "Capture and annotate interactions for documentation."),
                .init("color_palette", "Color palette extractor", "Sample and export colors from the active screen.")
            ].filter { availableIDs.contains($0.id) }
            #else
            return [
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
            #endif
        case .resources:
            #if os(iOS)
            let availableIDs = Set(DebugSwift.availableResourceFeatureIDs())
            return [
                .init("files", "Files", "Browse files in the app sandbox and shared containers."),
                .init("user_defaults", "User Defaults", "Inspect and compare registered preferences."),
                .init("keychain", "Keychain", "Browse app keychain items."),
                .init("persistent_data", "Persistent Data", "Inspect persistent app data."),
                .init("core_data", "Core Data", "Browse Core Data stores and entities."),
                .init("swift_data", "SwiftData Browser", "Inspect SwiftData models and records."),
                .init("http_cookies", "HTTP Cookies", "Inspect cookies stored by the app."),
                .init("database", "Database Browser", "Browse SQLite tables and rows."),
                .init("security_audit", "Security Audit", "Scan app resources for sensitive data.")
            ].filter { availableIDs.contains($0.id) }
            #else
            return [
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
            #endif
        case .app:
            return [
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
                DebugSwiftFeatureDestination(feature: feature)
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

private struct DebugSwiftFeatureDestination: View {
    let feature: DebugSwiftTool

    @ViewBuilder
    var body: some View {
        #if os(iOS)
        if feature.id == "grid" {
            DebugSwiftGridOverlaySettingsView()
        } else if ["touches", "colorize", "animations", "dark_mode", "measurement"].contains(feature.id) {
            DebugSwiftInterfaceSettingView(featureID: feature.id)
        } else if ["swiftui_render", "doc_recorder", "color_palette"].contains(feature.id) {
            DebugSwiftIOSNativeInterfaceHost(featureID: feature.id)
                .ignoresSafeArea(edges: .bottom)
        } else if ["files", "user_defaults", "keychain", "persistent_data", "core_data", "swift_data", "http_cookies", "database", "security_audit"].contains(feature.id) {
            if feature.id == "swift_data" {
                if #available(iOS 17.0, *) {
                    DebugSwiftIOSNativeResourceHost(featureID: feature.id)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Text("SwiftData Browser requires iOS 17 or newer.")
                }
            } else {
                DebugSwiftIOSNativeResourceHost(featureID: feature.id)
                    .ignoresSafeArea(edges: .bottom)
            }
        } else {
            DebugSwiftFeatureDetail(feature: feature)
        }
        #else
        if feature.id == "grid" {
            DebugSwiftGridOverlaySettingsView()
        } else {
            DebugSwiftFeatureDetail(feature: feature)
        }
        #endif
    }
}

private struct DebugSwiftGridOverlaySettingsView: View {
    @State private var settings = DebugSwiftGridOverlayState()

    private let colorNames = ["Red", "Blue", "Green", "Yellow", "White", "Gray"]
    private let colors: [Color] = [.red, .blue, .green, .yellow, .white, .gray]

    var body: some View {
        Form {
            Section("Overlay") {
                Toggle("Show grid overlay", isOn: Binding(
                    get: { settings.isEnabled },
                    set: { value in update { $0.isEnabled = value } }
                ))
            }

            if settings.isEnabled {
                Section("Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Slider(value: Binding(
                            get: { settings.size },
                            set: { value in update { $0.size = value } }
                        ), in: 4.0...64.0, step: 1.0)
                        Text("Size: \(Int(settings.size.rounded())) dp")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Slider(value: Binding(
                            get: { settings.opacity },
                            set: { value in update { $0.opacity = value } }
                        ), in: 0.1...1.0)
                        Text("Opacity: \(Int((settings.opacity * 100).rounded()))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Color") {
                    HStack(spacing: 14) {
                        ForEach(0..<colors.count, id: \.self) { index in
                            Button {
                                update { $0.colorIndex = index }
                            } label: {
                                Circle()
                                    .fill(colors[index])
                                    .frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.6), lineWidth: settings.colorIndex == index ? 2.0 : 0.0))
                                    .overlay {
                                        if settings.colorIndex == index {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundColor(index == 4 ? .black : .white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(colorNames[index])
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Grid overlay")
        .onAppear { settings = DebugSwiftAndroidRuntime.gridOverlaySettings() }
    }

    private func update(_ change: (inout DebugSwiftGridOverlayState) -> Void) {
        var updated = settings
        change(&updated)
        settings = updated
        _ = DebugSwiftAndroidRuntime.setGridOverlaySettings(updated)
    }
}

private struct DebugSwiftInterfaceSettingView: View {
    let featureID: String
    @State private var isEnabled = false

    private var title: String {
        switch featureID {
        case "touches": "Showing touches"
        case "colorize": "Colorized view borders"
        case "animations": "Slow animations"
        case "dark_mode": "Dark Mode"
        case "measurement": "UI measurements"
        default: "Interface setting"
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(title, isOn: Binding(
                    get: { isEnabled },
                    set: { enabled in
                        isEnabled = enabled
                        DebugSwiftAndroidRuntime.setInterfaceSetting(featureID: featureID, enabled: enabled)
                    }
                ))
            }
        }
        .onAppear { isEnabled = DebugSwiftAndroidRuntime.interfaceSettingIsEnabled(featureID: featureID) }
    }
}

struct DebugSwiftGridOverlayState {
    var isEnabled = false
    var size = 28.0
    var opacity = 0.5
    var colorIndex = 0
}

#if os(iOS)
private struct DebugSwiftIOSNativeInterfaceHost: UIViewControllerRepresentable {
    let featureID: String

    func makeUIViewController(context: Context) -> UIViewController {
        DebugSwiftAndroidRuntime.prepareIOSDebugger()
        return DebugSwift.debugInterfaceViewController(for: featureID) ?? UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {}
}

private struct DebugSwiftIOSNativeResourceHost: UIViewControllerRepresentable {
    let featureID: String

    func makeUIViewController(context: Context) -> UIViewController {
        DebugSwiftAndroidRuntime.prepareIOSDebugger()
        return DebugSwift.debugResourceViewController(for: featureID) ?? UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {}
}
#endif

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

    @MainActor
    static func gridOverlaySettings() -> DebugSwiftGridOverlayState {
        #if os(Android)
        let parts = DebugSwiftNativeBridge.gridSettings().components(separatedBy: "|")
        guard parts.count == 4 else { return DebugSwiftGridOverlayState() }
        return DebugSwiftGridOverlayState(
            isEnabled: parts[0] == "true",
            size: Double(parts[1]) ?? 28.0,
            opacity: Double(parts[2]) ?? 0.5,
            colorIndex: Int(parts[3]) ?? 0
        )
        #else
        let settings = DebugSwift.gridOverlaySettings()
        return DebugSwiftGridOverlayState(
            isEnabled: settings.isEnabled,
            size: settings.size,
            opacity: settings.opacity,
            colorIndex: settings.colorIndex
        )
        #endif
    }

    @MainActor
    @discardableResult
    static func setGridOverlaySettings(_ settings: DebugSwiftGridOverlayState) -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.setGridSettings(
            "\(settings.isEnabled)|\(settings.size)|\(settings.opacity)|\(settings.colorIndex)"
        )
        #else
        DebugSwift.setGridOverlaySettings(
            DebugSwiftGridOverlaySettings(
                isEnabled: settings.isEnabled,
                size: settings.size,
                opacity: settings.opacity,
                colorIndex: settings.colorIndex
            )
        )
        return "Grid settings updated."
        #endif
    }

    @MainActor
    static func interfaceSettingIsEnabled(featureID: String) -> Bool {
        #if os(Android)
        return DebugSwiftNativeBridge.interfaceToolEnabled(featureID)
        #else
        guard let setting = iosInterfaceSetting(for: featureID) else { return false }
        return DebugSwift.interfaceSettingIsEnabled(setting)
        #endif
    }

    @MainActor
    @discardableResult
    static func setInterfaceSetting(featureID: String, enabled: Bool) -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.setInterfaceToolEnabled(featureID, enabled)
        #else
        guard let setting = iosInterfaceSetting(for: featureID) else {
            return "Unknown interface setting: \(featureID)"
        }
        DebugSwift.setInterfaceSetting(setting, enabled: enabled)
        return "\(featureID) \(enabled ? "enabled" : "disabled")."
        #endif
    }

    #if os(iOS)
    @MainActor
    private static func iosInterfaceSetting(for featureID: String) -> DebugSwiftInterfaceSetting? {
        switch featureID {
        case "touches": .touches
        case "colorize": .colorizedBorders
        case "animations": .slowAnimations
        case "dark_mode": .darkMode
        case "measurement": .measurement
        case "swiftui_render": .swiftUIRenderTracking
        default: nil
        }
    }
    #endif
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
