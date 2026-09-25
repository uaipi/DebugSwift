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
    @State private var selectedArea: DebugSwiftArea = .network

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

            NavigationStack {
                DebugSwiftFeatureList(area: selectedArea)
                    .navigationTitle(selectedArea.title)
            }
            .id(selectedArea.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(ColorScheme.dark)
        .onAppear {
            if !visibleAreas.contains(selectedArea), let firstVisibleArea = visibleAreas.first {
                selectedArea = firstVisibleArea
            }
        }
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
            let features: [DebugSwiftTool] = [
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
            #if os(iOS)
            let availableIDs = Set(DebugSwift.availableNetworkFeatureIDs())
            return features.filter { availableIDs.contains($0.id) }
            #else
            return features
            #endif
        case .performance:
            let features: [DebugSwiftTool] = [
                .init("performance_overview", "Live Metrics", "Track CPU, memory, frames per second, and process activity."),
                .init("performance_widget", "Performance Widget", "Show live CPU, memory, and slow-frame metrics over the host app."),
                .init("battery", "Battery", "Inspect battery level, charging state, and power source."),
                .init("disk", "Disk I/O", "Inspect app storage size and process read/write byte counters."),
                .init("memory_warning", "Memory Warning", "Trigger the platform's low-memory callback path and inspect its response."),
                .init("frame_drops", "Frame Drops", "Record slow frames and inspect their timing on a timeline."),
                .init("hangs", "Hangs and ANRs", "Detect main thread stalls and inspect captured stack traces."),
                .init("backtraces", "Backtraces", "Capture and browse call stacks on demand."),
                .init("leaks", "Leak Detection", "Find UI objects that remain reachable after their expected lifetime."),
                .init("thread_checker", "Thread Checker", "Capture thread violations, inspect details, and configure dispatch handling."),
                .init("super_calls", "Lifecycle Super Calls", "Review lifecycle callback violations reported by the platform.")
            ]
            #if os(iOS)
            let availableIDs = Set(DebugSwift.availablePerformanceFeatureIDs())
            return features.filter { availableIDs.contains($0.id) }
            #else
            return features
            #endif
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
                .init("dark_mode", "Dark Mode", "Override the host app appearance or follow the Android system setting."),
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
                .init("preferences", "Preferences", "View and manage registered Android SharedPreferences values."),
                .init("keychain", "Secure Storage", "Inspect aliases in Android Keystore without exposing private key material."),
                .init("persistent_data", "Persistent Data", "Inspect app preferences and Android Keystore aliases together."),
                .init("sqlite", "Database Browser", "Browse SQLite tables, rows, and run SQL queries."),
                .init("realm", "Realm Browser", "Inspect Realm databases registered by the host app."),
                .init("core_data", "Room Database", "Browse the Android database layer, including registered Room databases."),
                .init("swift_data", "Object Store", "Inspect SQLite or Room storage used in place of SwiftData on Android."),
                .init("cookies", "HTTP Cookies", "Inspect WebView cookies for app-owned domains."),
                .init("security_audit", "Security Audit", "Check app preferences, manifest metadata, bundled credentials, and private text files for sensitive data.")
            ]
            #endif
        case .app:
            let features: [DebugSwiftTool] = [
                .init("crashes", "Crash Reports", "Save uncaught application crashes with stack traces and timestamps."),
                .init("console", "Console", "View, clear, and export messages written through the DebugSwift logger."),
                .init("oslog_console", "System Log", "Browse this app's Android Logcat records, filter messages, and export the results."),
                .init("device_info", "Device Info", "Inspect app version, Android version, device, display, and memory details."),
                .init("push_token", "Push Token", "Register and display an app-provided Firebase Cloud Messaging token."),
                .init("push_simulator", "Push Notifications", "Manage notification permissions, templates, test scenarios, settings, and delivery history."),
                .init("custom_actions", "Custom Actions", "Register host-app actions and run them from the debugger."),
                .init("custom_info", "Custom Info", "Display diagnostic values supplied by the host app."),
                .init("deep_links", "Deep Links", "Inspect the current intent URI and registered app link information."),
                .init("loaded_libraries", "Installed Libraries", "Inspect installed DEX splits, native library paths, ABIs, and the runtime class loader."),
                .init("location", "Location", "Inspect the last location reported by the host app."),
                .init("event_bus", "Event Timeline", "Browse network, performance, interface, app, and resource events."),
                .init("agent_debug_log", "Agent Debug Log", "Stream app events, network activity, console messages, and crashes to an NDJSON file.")
            ]
            #if os(iOS)
            let availableIDs = Set(DebugSwift.availableAppFeatureIDs())
            return features.filter { availableIDs.contains($0.id) }
            #else
            return features
            #endif
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
        } else if feature.id == "network_thresholds" {
            DebugSwiftNetworkThresholdView()
        } else if feature.id == "console" {
            DebugSwiftConsoleView()
        } else if ["http", "websocket", "network_injection", "graphql", "network_encryption", "har_export", "webview_network", "network_history"].contains(feature.id) {
            DebugSwiftIOSNativeNetworkHost(featureID: feature.id)
                .ignoresSafeArea(edges: .bottom)
        } else if ["performance_overview", "performance_widget", "battery", "disk", "memory_warning", "frame_drops", "hangs", "backtraces", "leaks", "thread_checker", "super_calls"].contains(feature.id) {
            DebugSwiftIOSNativePerformanceHost(featureID: feature.id)
                .ignoresSafeArea(edges: .bottom)
        } else if ["touches", "colorize", "animations", "dark_mode", "measurement"].contains(feature.id) {
            DebugSwiftInterfaceSettingView(featureID: feature.id)
        } else if ["swiftui_render", "doc_recorder", "color_palette"].contains(feature.id) {
            DebugSwiftIOSNativeInterfaceHost(featureID: feature.id)
                .ignoresSafeArea(edges: .bottom)
        } else if ["crashes", "oslog_console", "location", "loaded_libraries", "push_simulator", "deep_links", "event_bus", "agent_debug_log"].contains(feature.id) {
            DebugSwiftIOSNativeAppHost(featureID: feature.id)
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
        } else if feature.id == "network_thresholds" {
            DebugSwiftNetworkThresholdView()
        } else if feature.id == "console" {
            DebugSwiftConsoleView()
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

private struct DebugSwiftNetworkThresholdView: View {
    @State private var trackingEnabled = false
    @State private var thresholdLimit = 1000
    @State private var windowSeconds = 60
    @State private var blockingEnabled = false
    @State private var currentRequestCount = 0
    @State private var totalBreaches = 0
    @State private var endpointDetails = "No endpoint limits configured."
    @State private var breachDetails = "No threshold breaches."
    @State private var statusMessage = ""
    @State private var confirmsHistoryClear = false
    @State private var refreshTimer: Timer?

    var body: some View {
        Form {
            Section("Current Status") {
                Toggle("Enable Tracking", isOn: Binding(
                    get: { trackingEnabled },
                    set: { enabled in
                        trackingEnabled = enabled
                        apply("set_threshold_tracking", value: enabled ? "true" : "false")
                    }
                ))

                HStack {
                    Text("Current Requests")
                    Spacer()
                    if trackingEnabled {
                        let percentage = thresholdLimit > 0 ? Int((Double(currentRequestCount) / Double(thresholdLimit)) * 100.0) : 0
                        Text("\(currentRequestCount) / \(thresholdLimit) (\(percentage)%)")
                            .foregroundColor(percentage >= 90 ? Color.red : percentage >= 70 ? Color.orange : Color.green)
                    } else {
                        Text("Disabled per \(windowSeconds)s")
                            .foregroundColor(Color.secondary)
                    }
                }

                HStack {
                    Text("Total Breaches")
                    Spacer()
                    Text("\(totalBreaches)")
                        .foregroundColor(Color.secondary)
                }
            }

            Section("Configuration") {
                Stepper(label: {
                    Text("Threshold Limit: \(thresholdLimit) requests")
                }, onIncrement: {
                    updateThresholdLimit(thresholdLimit + 10)
                }, onDecrement: {
                    updateThresholdLimit(thresholdLimit - 10)
                })

                Stepper(label: {
                    Text("Time Window: \(windowSeconds) seconds")
                }, onIncrement: {
                    updateWindow(windowSeconds + 10)
                }, onDecrement: {
                    updateWindow(windowSeconds - 10)
                })

                Toggle("Block Exceeding Requests", isOn: Binding(
                    get: { blockingEnabled },
                    set: { enabled in
                        blockingEnabled = enabled
                        apply("set_threshold_blocking", value: enabled ? "true" : "false")
                    }
                ))
            }

            Section("Endpoint Limits") {
                Text(endpointDetails)
                    .font(Font.system(Font.TextStyle.footnote, design: Font.Design.monospaced))
                    .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
            }

            Section("Recent Breaches") {
                Text(breachDetails)
                    .font(Font.system(Font.TextStyle.footnote, design: Font.Design.monospaced))
                    .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)
            }

            Section("Actions") {
                Button("Refresh") { refresh() }
                Button("Clear History", role: ButtonRole.destructive) { confirmsHistoryClear = true }
                Button("Export Logs") {
                    statusMessage = DebugSwiftAndroidRuntime.perform(featureID: "network_thresholds", actionID: "export")
                }
            }

            if !statusMessage.isEmpty {
                Section("Status") {
                    Text(statusMessage)
                        .font(Font.caption)
                }
            }
        }
        .navigationTitle("Request Threshold")
        .onAppear {
            refresh()
            refreshTimer?.invalidate()
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in refresh() }
        }
        .onDisappear {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
        .alert("Clear request history?", isPresented: $confirmsHistoryClear) {
            Button("Cancel", role: ButtonRole.cancel) {}
            Button("Clear History", role: ButtonRole.destructive) {
                apply("clear_threshold_history")
            }
        } message: {
            Text("This removes the request history and recorded threshold breaches.")
        }
    }

    private func apply(_ actionID: String, value: String = "") {
        statusMessage = DebugSwiftAndroidRuntime.perform(
            featureID: "network_thresholds",
            actionID: actionID,
            value: value
        )
        refresh()
    }

    private func updateThresholdLimit(_ value: Int) {
        let updatedValue = min(1000, max(1, value))
        guard updatedValue != thresholdLimit else { return }
        thresholdLimit = updatedValue
        apply("set_threshold", value: "\(updatedValue),\(windowSeconds)")
    }

    private func updateWindow(_ value: Int) {
        let updatedValue = min(300, max(10, value))
        guard updatedValue != windowSeconds else { return }
        windowSeconds = updatedValue
        apply("set_threshold", value: "\(thresholdLimit),\(updatedValue)")
    }

    private func refresh() {
        let rows = DebugSwiftAndroidRuntime.snapshot(featureID: "network_thresholds").components(separatedBy: "\n")
        let settings = rows.first?.components(separatedBy: "|") ?? []
        if settings.count >= 7, settings[0] == "threshold" {
            trackingEnabled = settings[1] == "true"
            thresholdLimit = Int(settings[2]) ?? 1000
            windowSeconds = Int(settings[3]) ?? 60
            blockingEnabled = settings[4] == "true"
            currentRequestCount = Int(settings[5]) ?? 0
            totalBreaches = Int(settings[6]) ?? 0
        }

        let details = rows.dropFirst().joined(separator: "\n")
        let sections = details.components(separatedBy: "\n\nRECENT BREACHES\n")
        let endpointText = sections.first?
            .replacingOccurrences(of: "ENDPOINT LIMITS\n", with: "")
        if let endpointText, !endpointText.isEmpty {
            endpointDetails = endpointText
        } else {
            endpointDetails = "No endpoint limits configured."
        }
        breachDetails = sections.count > 1 ? sections[1] : "No threshold breaches."
    }
}

private struct DebugSwiftConsoleEntry: Identifiable {
    let id: Int
    let message: String
}

private struct DebugSwiftConsoleView: View {
    @State private var entries: [DebugSwiftConsoleEntry] = []
    @State private var searchText = ""
    @State private var statusMessage = ""
    @State private var confirmsClear = false

    private var filteredEntries: [DebugSwiftConsoleEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter { $0.message.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search console", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button("Refresh") { refresh() }
            }
            .padding()

            HStack {
                Button("Clear", role: ButtonRole.destructive) {
                    confirmsClear = true
                }
                .disabled(entries.isEmpty)

                Spacer()

                Button("Export Logs") {
                    perform("export")
                }
                .disabled(entries.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            if filteredEntries.isEmpty {
                Spacer()
                Text(entries.isEmpty ? "No console messages captured." : "No messages match this search.")
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        HStack(alignment: VerticalAlignment.top, spacing: 12) {
                            Text(entry.message)
                                .font(Font.system(Font.TextStyle.footnote, design: Font.Design.monospaced))
                                .frame(maxWidth: CGFloat.infinity, alignment: Alignment.leading)

                            Button(role: ButtonRole.destructive) {
                                perform("delete_console_entry", value: "\(entry.id)")
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete console entry")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(Font.caption)
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Console")
        .onAppear { refresh() }
        .alert("Clear all console messages?", isPresented: $confirmsClear) {
            Button("Cancel", role: ButtonRole.cancel) {}
            Button("Clear", role: ButtonRole.destructive) { perform("clear") }
        } message: {
            Text("This removes every captured print and NSLog entry.")
        }
    }

    private func refresh() {
        let snapshot = DebugSwiftAndroidRuntime.snapshot(featureID: "console")
        guard let data = snapshot.data(using: .utf8),
              let messages = try? JSONDecoder().decode([String].self, from: data) else {
            entries = []
            statusMessage = "Console data could not be loaded."
            return
        }
        entries = messages.indices.map { index in DebugSwiftConsoleEntry(id: index, message: messages[index]) }
        statusMessage = entries.count == 1 ? "1 message" : "\(entries.count) messages"
    }

    private func perform(_ actionID: String, value: String = "") {
        statusMessage = DebugSwiftAndroidRuntime.perform(
            featureID: "console",
            actionID: actionID,
            value: value
        )
        refresh()
    }
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

private struct DebugSwiftIOSNativeAppHost: UIViewControllerRepresentable {
    let featureID: String

    func makeUIViewController(context: Context) -> UIViewController {
        DebugSwiftAndroidRuntime.prepareIOSDebugger()
        return DebugSwift.debugAppViewController(for: featureID) ?? UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {}
}

private struct DebugSwiftIOSNativeNetworkHost: UIViewControllerRepresentable {
    let featureID: String

    func makeUIViewController(context: Context) -> UIViewController {
        DebugSwiftAndroidRuntime.prepareIOSDebugger()
        return DebugSwift.debugNetworkViewController(for: featureID) ?? UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {}
}

private struct DebugSwiftIOSNativePerformanceHost: UIViewControllerRepresentable {
    let featureID: String

    func makeUIViewController(context: Context) -> UIViewController {
        DebugSwiftAndroidRuntime.prepareIOSDebugger()
        return DebugSwift.debugPerformanceViewController(for: featureID) ?? UIViewController()
    }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {}
}
#endif

struct DebugSwiftFeatureDetail: View {
    let feature: DebugSwiftTool
    @State private var output = ""
    @State private var command = ""

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
            ["refresh", "filter_requests", "select_request", "clear", "export"]
        case "websocket":
            ["refresh", "filter_websockets", "select_connection", "select_frame", "filter_sent", "filter_received", "filter_all_frames", "copy_url", "copy_payload", "send_frame", "resend_frame", "close_connection", "clear_frames", "back_connections", "clear", "export"]
        case "har_export", "console", "crashes", "backtraces", "event_bus":
            ["refresh", "capture", "clear", "export"]
        case "oslog_console":
            ["refresh", "filter_logs", "export"]
        case "agent_debug_log":
            ["refresh", "toggle", "clear", "export"]
        case "memory_warning":
            ["refresh", "simulate_memory_warning"]
        case "graphql", "network_history":
            ["refresh", "filter_requests", "select_request", "clear", "export"]
        case "network_injection":
            ["refresh", "set_delay", "inject_failure", "set_http_error", "rewrite_response", "block_url", "toggle"]
        case "network_thresholds":
            ["refresh", "set_threshold", "toggle"]
        case "network_encryption":
            ["refresh", "register_key", "clear_keys"]
        case "preferences":
            ["refresh", "set_preference", "delete_preference", "clear_preferences", "export"]
        case "persistent_data":
            ["refresh", "set_preference", "delete_preference", "clear_preferences", "export"]
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
        case "dark_mode":
            ["refresh", "toggle", "reset_dark_mode"]
        case "security_audit":
            ["refresh"]
        case "touches", "view_borders", "thread_checker", "performance_widget":
            ["refresh", "toggle", "capture"]
        case "push_simulator":
            ["refresh", "toggle", "notify", "simulate_template", "run_scenario", "set_notification_config", "add_template", "remove_template", "history_page", "interact_notification", "resend_notification", "remove_notification", "clear_push_history", "export", "open_notification_settings"]
        case "device_info", "push_token":
            ["refresh", "copy_token"]
        case "custom_info":
            #if os(Android)
            ["refresh", "report_info"]
            #else
            ["refresh"]
            #endif
        case "custom_actions":
            ["refresh", "run_custom"]
        default:
            ["refresh", "capture"]
        }
    }

    var inputHint: String? {
        switch feature.id {
        case "http", "graphql", "network_history": "Filter by URL, method, or body; enter a list number for details"
        case "websocket": "Filter URL/payload; enter #connection, #frame, text, or base64:<data>"
        case "oslog_console": "Filter log message or tag"
        case "network_injection": "Value: ms, status, pattern=>body, or URL pattern"
        case "network_thresholds": "Request limit,window seconds"
        case "network_encryption": "URL regex:base64 AES key (body is base64 nonce + AES-GCM ciphertext)"
        case "grid": "Spacing dp, optional color: 24,#663399FF"
        case "preferences", "persistent_data": "Store|key=value to write; Store|key to remove; Store|CLEAR to delete all"
        case "files": "App path: files/, cache/, or databases/"
        case "push_simulator": "Notification command or ID"
        case "sqlite", "core_data", "swift_data": "Database name|SQL statement"
        case "custom_actions": "Registered action title"
        #if os(Android)
        case "custom_info": "Name=value"
        #endif
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
        case "select_request": "Open request details"
        case "filter_websockets": "Filter connections and frames"
        case "select_connection": "Open connection"
        case "select_frame": "Open frame details"
        case "filter_sent": "Show sent frames"
        case "filter_received": "Show received frames"
        case "filter_all_frames": "Show all frames"
        case "copy_url": "Copy connection URL"
        case "copy_payload": "Copy selected payload"
        case "copy_token": "Copy push token"
        case "send_frame": "Send text or binary frame"
        case "resend_frame": "Resend selected frame"
        case "close_connection": "Close connection"
        case "clear_frames": "Clear selected connection frames"
        case "back_connections": "Back to connections"
        case "filter_logs": "Apply log filter"
        case "toggle": feature.id == "network_thresholds" ? "Toggle request blocking" : feature.id == "agent_debug_log" ? "Start / stop capture" : feature.id == "dark_mode" ? "Toggle dark appearance" : feature.id == "push_simulator" ? "Enable / disable simulation" : "Enable / disable"
        case "reset_dark_mode": "Follow system appearance"
        case "set_delay": "Set request delay"
        case "inject_failure": "Fail next request"
        case "set_http_error": "Set HTTP error code"
        case "rewrite_response": "Add response rewrite"
        case "block_url": "Block URL pattern"
        case "clear_keys": "Clear decryption keys"
        case "set_threshold": "Set request threshold"
        case "register_key": "Register AES key"
        case "set_grid": "Set grid spacing and color"
        case "simulate_memory_warning": "Simulate memory warning"
        case "set_preference": "Write preference"
        case "delete_preference": "Remove preference"
        case "clear_preferences": "Clear store (enter Store|CLEAR)"
        case "browse_files": "Open path"
        case "notify": "Post test notification"
        case "simulate_template": "Simulate from template"
        case "run_scenario": "Run test scenario"
        case "set_notification_config": "Update notification setting"
        case "add_template": "Add notification template"
        case "remove_template": "Remove notification template"
        case "history_page": "History page"
        case "interact_notification": "Simulate notification tap"
        case "resend_notification": "Send notification again"
        case "remove_notification": "Remove notification by ID"
        case "clear_push_history": "Clear history (enter CLEAR)"
        case "open_notification_settings": "Open notification permissions"
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

    @MainActor
    public static func snapshot(featureID: String) -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.snapshot(featureID)
        #else
        switch featureID {
        case "console":
            guard let data = try? JSONEncoder().encode(DebugSwift.Console.shared.messages()),
                  let json = String(data: data, encoding: String.Encoding.utf8) else {
                return "[]"
            }
            return json
        case "network_thresholds":
            let snapshot = DebugSwift.Network.shared.getThresholdSnapshot()
            let endpointRows = snapshot.endpointLimits.map { "\($0.endpoint) — \($0.limit) per \(Int($0.timeWindow))s" }
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            let breachRows = snapshot.recentBreaches.map { "\(dateFormatter.string(from: $0.timestamp)) · \($0.message)" }
            let endpoints = endpointRows.isEmpty ? "No endpoint limits configured." : endpointRows.joined(separator: "\n")
            let breaches = breachRows.isEmpty ? "No threshold breaches." : breachRows.joined(separator: "\n")
            return "threshold|\(snapshot.isEnabled)|\(snapshot.limit)|\(Int(snapshot.timeWindow))|\(snapshot.shouldBlockRequests)|\(snapshot.currentRequestCount)|\(snapshot.totalBreaches)\n" +
                "ENDPOINT LIMITS\n\(endpoints)\n\nRECENT BREACHES\n\(breaches)"
        case "device_info":
            return UserInfo.infos.map { "\($0.title) \($0.detail)" }.joined(separator: "\n")
        case "push_token":
            let token = DebugSwift.APNSToken.deviceToken ?? "No APNS token has been reported."
            return "Registration: \(DebugSwift.APNSToken.registrationState.rawValue)\nEnvironment: \(DebugSwift.APNSToken.environment.rawValue)\nToken: \(token)"
        case "custom_info":
            let sections = DebugSwift.App.shared.customInfo?() ?? []
            let lines = sections.flatMap { section in
                [section.title] + section.infos.map { "  \($0.title): \($0.subtitle)" }
            }
            return lines.isEmpty ? "No custom diagnostic data provided." : lines.joined(separator: "\n")
        case "custom_actions":
            let sections = DebugSwift.App.shared.customAction?() ?? []
            let lines = sections.flatMap { section in
                [section.title] + section.actions.map { "  \($0.title)" }
            }
            return lines.isEmpty ? "No custom actions registered by the host app." : lines.joined(separator: "\n")
        default:
            return "Open the UIKit debugger on iOS to inspect live app data."
        }
        #endif
    }

    @MainActor
    public static func perform(featureID: String, actionID: String, value: String = "") -> String {
        #if os(Android)
        return DebugSwiftNativeBridge.perform(featureID, actionID, value)
        #else
        if featureID == "console" {
            switch actionID {
            case "clear":
                DebugSwift.Console.shared.clear()
                return "Console cleared."
            case "delete_console_entry":
                guard let index = Int(value), DebugSwift.Console.shared.messages().indices.contains(index) else {
                    return "Console entry no longer exists."
                }
                DebugSwift.Console.shared.removeMessage(at: index)
                return "Console entry removed."
            case "export":
                DebugSwift.Console.shared.shareMessages()
                return "Sharing console log."
            case "refresh":
                return snapshot(featureID: featureID)
            default:
                return "Unknown Console action: \(actionID)."
            }
        }
        if featureID == "network_thresholds" {
            let network = DebugSwift.Network.shared
            switch actionID {
            case "set_threshold_tracking":
                if value == "true" { network.enableRequestTracking() } else if value == "false" { network.disableRequestTracking() }
                else { return "Set request tracking to true or false." }
                return "Request tracking updated."
            case "set_threshold_blocking":
                guard value == "true" || value == "false" else { return "Set request blocking to true or false." }
                network.setRequestBlocking(value == "true")
                return "Request blocking updated."
            case "set_threshold":
                let parts = value.split(separator: ",", omittingEmptySubsequences: false)
                guard parts.count == 2, let limit = Int(parts[0]), let window = Double(parts[1]), limit > 0, window > 0 else {
                    return "Enter request limit,window seconds."
                }
                network.setThreshold(limit, timeWindow: window)
                return "Request threshold set to \(limit) per \(Int(window))s."
            case "clear_threshold_history":
                network.clearThresholdHistory()
                return "Request threshold history cleared."
            case "export":
                network.exportThresholdLogs()
                return "Sharing request threshold logs."
            default:
                break
            }
        }
        if actionID == "copy_token", ["device_info", "push_token"].contains(featureID) {
            return DebugSwift.APNSToken.copyToClipboard() ? "APNS token copied to the clipboard." : "No registered APNS token is available to copy."
        }
        if featureID == "custom_actions", actionID == "run_custom" {
            let actionGroups = DebugSwift.App.shared.customAction?() ?? []
            let action = actionGroups.flatMap { $0.actions }.first { $0.title == value }
            guard let action, let run = action.action else { return "No registered action named '\(value)'." }
            run()
            return "Action '\(value)' completed."
        }
        return "This action is not available for \(featureID)."
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
