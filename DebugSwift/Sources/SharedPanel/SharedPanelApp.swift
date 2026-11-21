//
//  SharedPanelApp.swift
//  DebugSwift
//

import CoreLocation
import MachO
import ObjectiveC
import OSLog
import UIKit
import UserNotifications

/// The App area of the shared panel on iOS: crash reports, the system log, deep links, location,
/// the event timeline and the agent debug log, in the shapes the Android runtime returns them.
@MainActor
final class SharedPanelApp {
    static let shared = SharedPanelApp()

    private static let logLimit = 500
    private static let simulationOff = "Enable push notification simulation before sending a notification."
    /// The longest delay a simulated notification accepts: a day, as on Android.
    private static let maxDelay: TimeInterval = 86_400
    private let deepLinks = DeepLinkViewModel()
    /// Links still opening; their outcome lands in the history when open answers.
    private var deepLinksOpening = 0

    private init() {}

    // MARK: - Operations

    func resource(_ operation: String, _ arguments: [String: String]) -> [String: Any]? {
        switch operation {
        case "app.crashes":
            return crashes()
        case "app.logcat.clear":
            logClearedAt = Date()
            return ["message": "Log cleared."]
        case "app.logcat":
            return log(filter: arguments["filter"] ?? "", minimumLevel: arguments["level"] ?? "V", includeApple: arguments["apple"] == "true")
        case "app.deeplink.open":
            return openDeepLink(arguments["uri"] ?? "")
        case "app.deeplink.history":
            return [
                "pending": deepLinksOpening > 0,
                "entries": deepLinks.history.map {
                    [
                        "url": $0.urlString,
                        "time": SharedPanelData.timeFormatter.string(from: $0.timestamp),
                        "status": $0.statusRawValue,
                        "error": $0.errorMessage ?? ""
                    ]
                }
            ]
        case "app.location.state":
            return ["mocking": LocationToolkit.shared.simulatedLocation != nil]
        case "app.location.mock":
            guard let latitude = Double(arguments["latitude"] ?? ""), let longitude = Double(arguments["longitude"] ?? ""),
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else {
                return ["message": "Enter a latitude from -90 to 90 and a longitude from -180 to 180.", "mocking": LocationToolkit.shared.simulatedLocation != nil]
            }
            LocationToolkit.shared.simulatedLocation = CLLocation(latitude: latitude, longitude: longitude)
            return ["message": "The app now gets \(latitude), \(longitude).", "mocking": true]
        case "app.location.stop":
            LocationToolkit.shared.simulatedLocation = nil
            return ["message": "The app gets the real location again.", "mocking": false]
        case "app.agentlog.state":
            return agentLogState()
        case "app.libraries":
            return libraries()
        case "app.libraries.classes":
            return ["classes": classes(in: arguments["path"] ?? "")]
        case "app.libraries.class":
            return ["text": describeClass(arguments["name"] ?? "")]
        case "app.push.state":
            return pushState()
        case "app.agentlog.snapshot":
            do {
                let url = try AgentDebugLog.shared.writeSnapshot()
                return ["path": url.path, "message": "Snapshot written."]
            } catch {
                return ["error": "The snapshot could not be written: \(error.localizedDescription)"]
            }
        default:
            return nil
        }
    }

    func perform(featureID: String, actionID: String, value: String) -> String? {
        switch (featureID, actionID) {
        case ("crashes", "clear"):
            CrashManager.shared.deleteAll(ofType: .nsexception)
            CrashManager.shared.deleteAll(ofType: .signal)
            return "Crash reports cleared."
        case ("crashes", "export"):
            let text = crashReports().joined(separator: "\n\n---\n\n")
            return share(text, named: "debugswift-crashes.txt") ? "Sharing crash reports." : "No crash reports to export."
        case ("event_bus", "clear"):
            EventBusSubscriber.shared.bus.clear()
            return "Events cleared."
        case ("deep_links", "clear_history"):
            deepLinks.clearHistory()
            return "History cleared."
        case ("push_simulator", _):
            return pushAction(actionID, value)
        case ("agent_debug_log", "toggle"):
            let log = AgentDebugLog.shared
            if log.enabled { log.disable() } else { log.enable() }
            return log.enabled ? "Agent debug log on." : "Agent debug log off."
        case ("agent_debug_log", "clear"):
            AgentDebugLog.shared.clear()
            return "Agent debug log cleared."
        case ("agent_debug_log", "export"):
            let url = AgentDebugLog.shared.currentLogPath()
            guard FileManager.default.fileExists(atPath: url.path) else { return "The agent debug log is empty." }
            FileSharingManager.share(url)
            return "Sharing the agent debug log."
        default:
            return nil
        }
    }

    func snapshot(featureID: String) -> String? {
        switch featureID {
        case "event_bus":
            let time = SharedPanelData.timeFormatter
            let lines = EventBusSubscriber.shared.bus.events.reversed().map {
                "\(time.string(from: $0.timestamp)) [\($0.domain.rawValue)] \($0.summary)"
            }
            return lines.isEmpty ? "No diagnostic events published yet." : lines.joined(separator: "\n")
        case "location":
            if let location = LocationToolkit.shared.simulatedLocation {
                return "Simulated: \(location.coordinate.latitude), \(location.coordinate.longitude)"
            }
            return "The app gets the device's real location."
        case "deep_links":
            guard let last = deepLinks.history.first else { return "No link opened from DebugSwift yet." }
            return "\(last.urlString)\n\(last.statusRawValue) · \(last.formattedTimestamp)"
        default:
            return nil
        }
    }

    // MARK: - Crashes

    /// Whether the bundled symbol map is loaded, trying once.
    private lazy var symbolsLoaded: Bool = {
        if !SymbolicatorAdapter.shared.isSymbolTableLoaded,
           let map = Bundle.main.url(forResource: "symbol_map", withExtension: "json") {
            _ = SymbolicatorAdapter.shared.load(from: map.path)
        }
        return SymbolicatorAdapter.shared.isSymbolTableLoaded
    }()

    private func crashModels() -> [CrashModel] {
        (CrashManager.shared.recover(ofType: .nsexception) + CrashManager.shared.recover(ofType: .signal))
            .sorted { $0.details.date > $1.details.date }
    }

    private func crashReports() -> [String] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return crashModels().map { crash in
            var lines = [
                crash.details.name,
                formatter.string(from: crash.details.date),
                "App \(crash.details.appVersion ?? "?") (\(crash.details.appBuild ?? "?")) · iOS \(crash.details.iosVersion) · \(crash.details.deviceModel)",
                "Connection: \(crash.details.reachability)"
            ]
            // With the app's symbol_map.json, traces show function names and source locations.
            let titles = symbolsLoaded ? SymbolicatorAdapter.shared.symbolicate(traces: crash.traces) : crash.traces.map(\.title)
            for (title, trace) in zip(titles, crash.traces) {
                lines.append("\n\(title)\n\(trace.detail)")
            }
            if !crash.context.errorOutput.isEmpty {
                lines.append("\nError log\n\(crash.context.errorOutput)")
            }
            if !crash.context.consoleOutput.isEmpty {
                lines.append("\nConsole\n\(crash.context.consoleOutput)")
            }
            return lines.joined(separator: "\n")
        }
    }

    private func crashes() -> [String: Any] {
        let models = crashModels()
        return [
            "reports": crashReports(),
            // The screen at the moment of each crash, when it could be taken.
            "screenshots": models.map { $0.context.image?.base64EncodedString() ?? "" },
            "exits": [[String: Any]]()
        ]
    }

    // MARK: - System log

    /// One system log entry, kept between reads.
    private struct LogItem: Sendable {
        let date: Date
        let level: String
        let tag: String
        let message: String
    }

    /// The newest entries, oldest first, read off the main actor: the first read covers the last
    /// five minutes, each later one only what was logged after the last entry kept, and the cache
    /// holds at most this many.
    nonisolated private static let logCapacity = 2000
    private var logItems: [LogItem] = []
    private var logIncludesApple = false
    private var logReading = false
    private var logReadAt = Date.distantPast
    /// Why the last read failed, until a read succeeds.
    private var logError: String?
    /// The system log can't be erased; Clear hides what was logged before it.
    private var logClearedAt: Date?

    private func log(filter: String, minimumLevel: String, includeApple: Bool) -> [String: Any] {
        if includeApple != logIncludesApple {
            logIncludesApple = includeApple
            logItems = []
            // Read again right away: the cache was just emptied. A read already running for the
            // old filter is discarded when it ends, and the screen keeps asking meanwhile.
            logReadAt = .distantPast
        }
        readNewLogEntries()
        if let logError, logItems.isEmpty { return ["error": logError] }
        let minimumRank = Self.rank(minimumLevel)
        let time = SharedPanelData.timeFormatter
        let entries: [[String: Any]] = logItems.filter { item in
            (logClearedAt.map { item.date >= $0 } ?? true)
                && Self.rank(item.level) >= minimumRank
                && (filter.isEmpty || item.message.localizedCaseInsensitiveContains(filter) || item.tag.localizedCaseInsensitiveContains(filter))
        }.suffix(Self.logLimit).map {
            ["time": time.string(from: $0.date), "level": $0.level, "tag": $0.tag, "message": $0.message]
        }
        // The screen asks again every second while it is shown (live), so new entries appear.
        return ["entries": entries, "pending": logReading, "live": true]
    }

    private func readNewLogEntries() {
        guard !logReading, Date().timeIntervalSince(logReadAt) >= 0.5 else { return }
        logReading = true
        let since = logItems.last?.date
        let includeApple = logIncludesApple
        Task.detached(priority: .utility) {
            let read = Self.readLog(since: since, includeApple: includeApple, limit: Self.logCapacity)
            await MainActor.run {
                let app = SharedPanelApp.shared
                if let error = read.error {
                    app.logError = "The system log could not be read: \(error)"
                } else if includeApple == app.logIncludesApple {
                    app.logError = nil
                    app.logItems.append(contentsOf: read.items)
                    if app.logItems.count > Self.logCapacity {
                        app.logItems.removeFirst(app.logItems.count - Self.logCapacity)
                    }
                }
                app.logReading = false
                app.logReadAt = Date()
            }
        }
    }

    /// Entries logged after `since`, oldest first; the first read covers the last five minutes.
    /// Only the newest `limit` are kept.
    nonisolated private static func readLog(since: Date?, includeApple: Bool, limit: Int) -> (items: [LogItem], error: String?) {
        let start = since ?? Date().addingTimeInterval(-300)
        // The process store may ignore the position, so the store filters by date (and subsystem)
        // too: without it each read walks the whole process log, which grows as the app runs.
        var conditions = [NSPredicate(format: "date > %@", start as NSDate)]
        if !includeApple { conditions.append(NSPredicate(format: "NOT (subsystem BEGINSWITH 'com.apple')")) }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: conditions)
        let opened = Result {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            return try store.getEntries(at: store.position(date: start), matching: predicate)
        }
        guard case let .success(entries) = opened else {
            if case let .failure(error) = opened { return ([], error.localizedDescription) }
            return ([], nil)
        }
        var items: [LogItem] = []
        for case let entry as OSLogEntryLog in entries {
            // The process store may ignore the position: check each entry's own date, after the
            // last entry kept, or within the five minutes on the first read.
            if let since, entry.date <= since { continue }
            if since == nil, entry.date < start { continue }
            if !includeApple, entry.subsystem.hasPrefix("com.apple") { continue }
            let tag = [entry.subsystem, entry.category].filter { !$0.isEmpty }.joined(separator: " · ")
            items.append(LogItem(date: entry.date, level: levelLetter(entry.level), tag: tag, message: entry.composedMessage))
            if items.count > limit * 2 { items.removeFirst(items.count - limit) }
        }
        return (Array(items.suffix(limit)), nil)
    }

    /// The screen's levels (Logcat's V D I W E) and OSLog's notice and fault, in order.
    private static func rank(_ letter: String) -> Int {
        ["V": 0, "D": 1, "I": 2, "N": 3, "W": 3, "E": 4, "F": 5][letter] ?? 0
    }

    nonisolated private static func levelLetter(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "D"
        case .info: "I"
        case .notice: "N"
        case .error: "E"
        case .fault: "F"
        default: "V"
        }
    }

    // MARK: - Deep links

    private func openDeepLink(_ uri: String) -> [String: Any] {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        let validation = deepLinks.validateURL(trimmed)
        guard validation.isValid else {
            return ["message": validation.error ?? "Enter a valid URL."]
        }
        // A link no app handles fails at once; opening one that can be opened finishes later and
        // shows in the history.
        var immediate: (opened: Bool, error: String?)?
        deepLinksOpening += 1
        deepLinks.openDeepLink(trimmed) { [weak self] opened, error in
            immediate = (opened, error)
            self?.deepLinksOpening -= 1
        }
        if let immediate {
            return ["message": immediate.opened ? "Opened \(trimmed)." : (immediate.error ?? "Could not open \(trimmed).")]
        }
        return ["message": "Opening \(trimmed)."]
    }

    // MARK: - Agent debug log

    private func agentLogState() -> [String: Any] {
        let log = AgentDebugLog.shared
        let url = log.currentLogPath()
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let lines = Self.tail(of: url).suffix(100)
        let entries: [[String: Any]] = lines.reversed().compactMap { line in
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return [
                "time": (json["timestamp"] as? Double) ?? 0,
                "kind": json["kind"] as? String ?? "",
                "location": json["location"] as? String ?? "",
                "message": json["message"] as? String ?? ""
            ]
        }
        return [
            "enabled": log.enabled,
            "session": ProcessInfo.processInfo.environment["AGENT_DEBUG_SESSION_ID"] ?? "",
            "path": url.path,
            "size": size,
            "entries": entries
        ]
    }

    // MARK: - Libraries

    private func libraries() -> [String: Any] {
        var images: [[String: Any]] = []
        for index in 0..<_dyld_image_count() {
            guard let cName = _dyld_get_image_name(index) else { continue }
            let path = String(cString: cName)
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            let address = _dyld_get_image_header(index).map { String(format: "0x%lX", Int(bitPattern: $0)) } ?? ""
            images.append([
                "path": path,
                "name": (path as NSString).lastPathComponent,
                "size": size,
                "origin": Self.isSystemImage(path) ? "System" : "App",
                "address": address
            ])
        }
        let frameworks = Bundle.main.privateFrameworksPath.flatMap {
            try? FileManager.default.contentsOfDirectory(atPath: $0)
        } ?? []
        return [
            "packageName": Bundle.main.bundleIdentifier ?? "",
            "appLibraries": frameworks.sorted().map { name in
                ["name": name, "size": Self.directorySize((Bundle.main.privateFrameworksPath ?? "") + "/" + name)]
            },
            "libraries": images,
            "classesAvailable": true
        ]
    }

    /// Images the OS provides; everything else (the app, its frameworks, frameworks Xcode loads
    /// from DerivedData while debugging) belongs to the app.
    private static func isSystemImage(_ path: String) -> Bool {
        path.contains("/System/Library/") || path.contains("/usr/lib/") || path.hasPrefix("/Developer/")
    }

    private static func directorySize(_ path: String) -> Int {
        guard let files = FileManager.default.enumerator(atPath: path) else { return 0 }
        var total = 0
        for case let file as String in files {
            total += (try? FileManager.default.attributesOfItem(atPath: path + "/" + file)[.size] as? Int) ?? 0
        }
        return total
    }

    /// The Objective-C classes an image defines, sorted.
    private func classes(in path: String) -> [String] {
        var count: UInt32 = 0
        guard let names = objc_copyClassNamesForImage(path, &count) else { return [] }
        defer { free(names) }
        return (0..<Int(count)).map { String(cString: names[$0]) }.sorted()
    }

    /// A class's superclasses, properties and methods, as the iOS class explorer showed them.
    private func describeClass(_ name: String) -> String {
        guard let cls = NSClassFromString(name) else { return "No class named \(name)." }
        var lines: [String] = [name]
        var chain: [String] = []
        var parent: AnyClass? = class_getSuperclass(cls)
        while let current = parent {
            chain.append(String(cString: class_getName(current)))
            parent = class_getSuperclass(current)
        }
        if !chain.isEmpty { lines.append("Inherits from " + chain.joined(separator: " → ")) }

        var propertyCount: UInt32 = 0
        if let properties = class_copyPropertyList(cls, &propertyCount) {
            defer { free(properties) }
            lines.append("\nProperties (\(propertyCount))")
            for index in 0..<Int(propertyCount) {
                let property = properties[index]
                let attributes = property_getAttributes(property).map { String(cString: $0) } ?? ""
                lines.append("  \(String(cString: property_getName(property)))  \(attributes)")
            }
        }
        for (title, target, prefix) in [("Instance methods", cls as AnyClass?, "-"), ("Class methods", object_getClass(cls), "+")] {
            var methodCount: UInt32 = 0
            guard let target, let methods = class_copyMethodList(target, &methodCount) else { continue }
            defer { free(methods) }
            lines.append("\n\(title) (\(methodCount))")
            for index in 0..<Int(methodCount) {
                lines.append("  \(prefix)\(NSStringFromSelector(method_getName(methods[index])))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Push notifications

    private var pushPermission = "Checking"

    private func refreshPushPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let permission: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: permission = "Allowed"
            case .denied: permission = "Disabled in system settings"
            default: permission = "Not granted"
            }
            Task { @MainActor in SharedPanelApp.shared.pushPermission = permission }
        }
    }

    private func pushState() -> [String: Any] {
        refreshPushPermission()
        let push = DebugSwift.PushNotification.self
        let config = push.configuration
        return [
            "enabled": push.isEnabled,
            "permission": pushPermission,
            "channel": "",
            "showInForeground": config.showInForeground,
            "playSound": config.playSound,
            "showBadge": config.showBadge,
            "autoInteraction": config.autoInteraction,
            // Safe for any stored value: an older or out-of-range delay must not trap here.
            "interactionDelay": config.interactionDelay.isFinite ? Int(min(max(config.interactionDelay, 0), Self.maxDelay).rounded()) : 0,
            "simulateRealPush": config.simulateRealPush,
            "maxHistory": config.maxHistoryCount,
            "templates": push.templates.map { template -> [String: Any] in
                var json: [String: Any] = [
                    "name": template.name, "title": template.title, "body": template.body,
                    "isDefault": template.isDefault, "templateID": template.id
                ]
                if let subtitle = template.subtitle { json["subtitle"] = subtitle }
                return json
            },
            "history": push.history.map { notification -> [String: Any] in
                var json: [String: Any] = [
                    "id": notification.id,
                    "title": notification.title,
                    "body": notification.body,
                    "status": notification.status.rawValue,
                    "trigger": notification.trigger.description,
                    "scheduledMs": notification.scheduledDate.timeIntervalSince1970 * 1000,
                    "userInfo": notification.userInfo
                ]
                if let subtitle = notification.subtitle { json["subtitle"] = subtitle }
                if let badge = notification.badge { json["badge"] = badge }
                if let sound = notification.sound { json["sound"] = sound }
                if let delivered = notification.deliveryDate { json["deliveredMs"] = delivered.timeIntervalSince1970 * 1000 }
                if let interaction = notification.interactionType { json["interaction"] = interaction.rawValue }
                return json
            }
        ]
    }

    private func pushAction(_ actionID: String, _ value: String) -> String {
        // The simulator itself, not the public API: that applies changes in a later main-actor
        // task, and the screen reads the state right after the action.
        let push = DebugSwift.PushNotification.self
        let simulator = PushNotificationSimulator.shared
        let parts = value.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        switch actionID {
        case "toggle":
            if simulator.isEnabled { simulator.disable() } else { simulator.enable() }
            return push.isEnabled ? "Push simulation on." : "Push simulation off."
        case "notify":
            // title|message|delay|subtitle|badge|sound|category|key=value,key=value, as on Android.
            guard simulator.isEnabled else { return Self.simulationOff }
            guard parts.count >= 2, !parts[0].isEmpty else { return "Enter a title and a message." }
            let delayText = parts[safe: 2] ?? ""
            guard let delay = delayText.isEmpty ? 0 : TimeInterval(delayText), delay.isFinite, (0...Self.maxDelay).contains(delay) else {
                return "Delay must be from 0 to \(Int(Self.maxDelay)) seconds."
            }
            let badgeText = parts[safe: 4] ?? ""
            let badge = Int(badgeText)
            guard badgeText.isEmpty || badge != nil else { return "Badge must be a whole number." }
            guard let userInfo = Self.payload(parts[safe: 7] ?? "") else {
                return "User info must use key=value pairs separated by commas."
            }
            let notification = SimulatedNotification(
                title: parts[0],
                body: parts[1],
                subtitle: (parts[safe: 3] ?? "").nilIfEmpty,
                badge: badge,
                sound: (parts[safe: 5] ?? "").nilIfEmpty,
                category: (parts[safe: 6] ?? "").nilIfEmpty,
                userInfo: userInfo,
                trigger: delay > 0 ? .timeInterval(delay) : .immediate
            )
            Task { await simulator.simulateNotification(notification) }
            return "Notification sent: \(parts[0])."
        case "simulate_template":
            guard simulator.isEnabled else { return Self.simulationOff }
            // Named by its ID (names can repeat), or by its name from older callers.
            let reference = parts.first ?? ""
            guard let template = push.templates.first(where: { $0.id == reference }) ?? push.templates.first(where: { $0.name == reference }) else {
                return "No template named \(reference)."
            }
            let delayText = parts[safe: 1] ?? ""
            guard let delay = delayText.isEmpty ? 0 : TimeInterval(delayText), delay.isFinite, (0...Self.maxDelay).contains(delay) else {
                return "Delay must be from 0 to \(Int(Self.maxDelay)) seconds."
            }
            Task { await simulator.simulateFromTemplate(template, trigger: delay > 0 ? .timeInterval(delay) : .immediate) }
            return "Sent the \(template.name) template."
        case "run_scenario":
            let scenarios: [String: DebugSwift.PushNotification.TestScenario] = [
                "messageflow": .messageFlow, "newsupdates": .newsUpdates,
                "marketingcampaign": .marketingCampaign, "systemalerts": .systemAlerts
            ]
            guard let scenario = scenarios[value] else { return "Unknown scenario: \(value)." }
            push.runTestScenario(scenario)
            return "Running the scenario."
        case "set_notification_config":
            let pair = value.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return "Set one option at a time, as key=value." }
            var config = push.configuration
            switch pair[0] {
            case "showInForeground": config.showInForeground = pair[1] == "true"
            case "playSound": config.playSound = pair[1] == "true"
            case "showBadge": config.showBadge = pair[1] == "true"
            case "autoInteraction": config.autoInteraction = pair[1] == "true"
            case "simulateRealPush": config.simulateRealPush = pair[1] == "true"
            case "interactionDelay":
                guard let delay = Double(pair[1]), delay.isFinite, (0...Self.maxDelay).contains(delay) else {
                    return "interactionDelay must be from 0 to \(Int(Self.maxDelay)) seconds."
                }
                config.interactionDelay = delay
            case "maxHistoryCount":
                guard let count = Int(pair[1]), count > 0 else { return "maxHistoryCount must be a whole number above 0." }
                config.maxHistoryCount = count
            default:
                return "Unknown option: \(pair[0])."
            }
            simulator.updateConfiguration(config)
            return "Updated \(pair[0])."
        case "add_template":
            guard parts.count >= 3, !parts[0].isEmpty, !parts[1].isEmpty else { return "Enter a name, a title and a message." }
            simulator.addTemplate(NotificationTemplate(name: parts[0], title: parts[1], body: parts[2]))
            return "Template \(parts[0]) added."
        case "remove_template":
            guard let template = push.templates.first(where: { $0.id == value }) ?? push.templates.first(where: { $0.name == value }) else {
                return "No template named \(value)."
            }
            simulator.removeTemplate(id: template.id)
            return "Template \(template.name) removed."
        case "interact_notification":
            guard push.history.contains(where: { $0.id == value }) else { return "No simulated notification with ID '\(value)'." }
            simulator.simulateInteraction(identifier: value)
            return "Interaction recorded for notification \(value)."
        case "remove_notification":
            guard push.history.contains(where: { $0.id == value }) else { return "No simulated notification with ID '\(value)'." }
            simulator.removeNotification(id: value)
            return "Removed the notification."
        case "resend_notification":
            guard let record = push.history.first(where: { $0.id == value }) else { return "No simulated notification with ID '\(value)'." }
            guard simulator.isEnabled else { return Self.simulationOff }
            // The same content and payload under a new identity, delivered now.
            let copy = SimulatedNotification(
                title: record.title,
                body: record.body,
                subtitle: record.subtitle,
                badge: record.badge,
                sound: record.sound,
                category: record.category,
                userInfo: record.userInfo
            )
            Task { await simulator.simulateNotification(copy) }
            return "Sent it again."
        case "clear_push_history":
            guard value == "CLEAR" else { return "Type CLEAR to remove notification history." }
            simulator.clearHistory()
            return "Push notification history cleared."
        case "open_notification_settings":
            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                UIApplication.shared.open(url)
            }
            return "Opened the app's notification settings."
        default:
            return "Unknown push action: \(actionID)."
        }
    }

    /// The last whole lines of a file, read from at most its final 64 KB: the log grows without a
    /// limit. The byte before the window tells whether the window starts on a line boundary.
    private static func tail(of url: URL) -> [Substring] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return [] }
        let window: UInt64 = 64 * 1024
        let start = end > window ? end - window - 1 : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              var data = try? handle.read(upToCount: Int(end - start)) else { return [] }
        if start > 0, let before = data.first {
            data = data.dropFirst()
            // Starting mid-line (maybe mid-character), drop the cut line's bytes before decoding.
            if before != UInt8(ascii: "\n") {
                guard let newline = data.firstIndex(of: UInt8(ascii: "\n")) else { return [] }
                data = data[data.index(after: newline)...]
            }
        }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
    }

    /// "key=value, key=value" as a dictionary; nil when a pair has no "=" or an empty key.
    private static func payload(_ text: String) -> [String: String]? {
        var values: [String: String] = [:]
        for pair in text.split(separator: ",") {
            // Empty pieces kept: "token=" is an empty value, and "=order=42" has no key.
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            values[parts[0]] = parts[1]
        }
        return values
    }

    // MARK: - Sharing

    private func share(_ text: String, named name: String) -> Bool {
        guard !text.isEmpty else { return false }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return false }
        FileSharingManager.share(url)
        return true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
