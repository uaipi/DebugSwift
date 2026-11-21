//
//  SharedPanelPerformance.swift
//  DebugSwift
//

import QuartzCore
import UIKit

/// The Performance area of the shared panel on iOS: the `app.perf.*` operations, in the shapes the
/// Android runtime returns them, read from DebugSwift's own monitors.
@MainActor
final class SharedPanelPerformance: NSObject {
    static let shared = SharedPanelPerformance()

    /// A frame slower than this is counted as slow, as on Android.
    private static let slowFrameMs = 32
    private static let slowFrameCapacity = 200
    private static let hangMonitoringKey = "debugswift.hang.monitoringEnabled"

    private var prepared = false
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var secondStart: CFTimeInterval = 0
    private var framesThisSecond = 0
    private var framesPerSecond = 0
    private var frameCount = 0
    /// Frames drawn since the sampler started (or frame timing was last cleared).
    var framesDrawn: Int { frameCount }
    private var slowFrameCount = 0
    private var slowestFrameMs = 0
    private var slowFrames: [(date: Date, ms: Int)] = []

    private let memoryWarning = PerformanceMemoryWarning()
    private var memoryWarningsSimulated = 0
    private var widgetToolkit: PerformanceToolkit?
    /// What the screen asked for: the widget only changes `isHidden` once its animation ends.
    private var widgetShown = false

    /// App storage, walked off the main actor at most every few seconds; the screens ask once a
    /// second and get the last totals meanwhile.
    private var appFiles: (count: Int, bytes: Int, at: Date)?
    private var isWalkingAppFiles = false

    override private init() {
        super.init()
    }

    func prepare() {
        guard !prepared else { return }
        prepared = true
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        if UserDefaults.standard.bool(forKey: Self.hangMonitoringKey) {
            HangDetectorRunner.shared.start()
        }
        // Time spent suspended is not a frame: start timing again when the app comes back.
        NotificationCenter.default.addObserver(
            self, selector: #selector(resumeFrameTiming), name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    @objc private func resumeFrameTiming() {
        lastFrameTimestamp = 0
        framesThisSecond = 0
    }

    @objc private func frame(_ link: CADisplayLink) {
        defer { lastFrameTimestamp = link.timestamp }
        guard lastFrameTimestamp > 0 else {
            secondStart = link.timestamp
            return
        }
        frameCount += 1
        framesThisSecond += 1
        let ms = Int(((link.timestamp - lastFrameTimestamp) * 1000).rounded())
        if ms > Self.slowFrameMs {
            slowFrameCount += 1
            slowestFrameMs = max(slowestFrameMs, ms)
            slowFrames.append((Date(), ms))
            if slowFrames.count > Self.slowFrameCapacity {
                slowFrames.removeFirst(slowFrames.count - Self.slowFrameCapacity)
            }
        }
        if link.timestamp - secondStart >= 1 {
            framesPerSecond = Int((Double(framesThisSecond) / (link.timestamp - secondStart)).rounded())
            framesThisSecond = 0
            secondStart = link.timestamp
        }
    }

    // MARK: - Operations

    func resource(_ operation: String, _ arguments: [String: String]) -> [String: Any] {
        prepare()
        switch operation {
        case "app.perf.sample":
            return sample()
        case "app.perf.detail":
            return detail(arguments["kind"] ?? "")
        case "app.perf.captureBacktrace":
            let capture = BacktraceManager.shared.capture(label: "Main thread")
            let note = arguments["all"] == "true" ? " iOS captures the calling thread only." : ""
            return ["message": "Captured \(capture.frames.count) frames.\(note)"]
        case "app.perf.clearBacktraces":
            BacktraceManager.shared.clear()
            return ["message": "Backtraces cleared."]
        case "app.perf.gc":
            let held = PerformanceLeakDetector.shared.leaks.filter(\.isActive).count
            return ["message": held == 1 ? "1 object is still in memory." : "\(held) objects are still in memory."]
        case "app.perf.stall":
            let ms = min(max(Int(arguments["ms"] ?? "") ?? 1000, 1), 10000)
            Thread.sleep(forTimeInterval: Double(ms) / 1000)
            return ["message": "Blocked the main thread for \(ms) ms."]
        case "app.perf.violation":
            guard PerformanceThreadChecker.shared.isEnabled else {
                return ["message": "Turn on Detect violations first."]
            }
            DispatchQueue.global().async {
                PerformanceThreadChecker.shared.checkMainThread(methodName: "setNeedsLayout", className: "UIView")
            }
            return ["message": "Called UIView.setNeedsLayout() off the main thread."]
        default:
            return ["error": "Unknown performance operation: \(operation)."]
        }
    }

    func perform(featureID: String, actionID: String, value: String) -> String? {
        switch (featureID, actionID) {
        case ("frame_drops", "clear"):
            frameCount = 0
            slowFrameCount = 0
            slowestFrameMs = 0
            slowFrames.removeAll()
            return "Frame timing cleared."
        case ("hangs", "clear"):
            HangDetectorRunner.shared.clearEvents()
            return "Stalls cleared."
        case ("hangs", "set_monitoring"):
            let enabled = value == "true"
            UserDefaults.standard.set(enabled, forKey: Self.hangMonitoringKey)
            if enabled { HangDetectorRunner.shared.start() } else { HangDetectorRunner.shared.stop() }
            return enabled ? "Stall detection on." : "Stall detection off."
        case ("thread_checker", "toggle"):
            let checker = PerformanceThreadChecker.shared
            if checker.isEnabled { checker.disable() } else { checker.enable() }
            return checker.isEnabled ? "Thread checking on." : "Thread checking off."
        case ("thread_checker", "clear"):
            PerformanceThreadChecker.shared.clearViolations()
            return "Violations cleared."
        case ("memory_warning", "simulate_memory_warning"):
            memoryWarning.generate()
            memoryWarningsSimulated += 1
            return "Memory warning sent to the app."
        case ("super_calls", "clear"):
            SuperCallDetector.shared.clearViolations()
            return "Violations cleared."
        case ("performance_widget", "toggle"):
            let toolkit = widgetToolkit ?? PerformanceToolkit(widgetDelegate: self)
            widgetToolkit = toolkit
            widgetShown.toggle()
            toolkit.isWidgetShown = widgetShown
            return widgetShown ? "Widget shown." : "Widget hidden."
        default:
            return nil
        }
    }

    func snapshot(featureID: String) -> String? {
        guard featureID == "performance_widget" else { return nil }
        return widgetShown ? "Widget is active." : "Widget is hidden."
    }

    // MARK: - Readings

    private func sample() -> [String: Any] {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        let footprint = ProcessMetrics.footprintBytes()
        let physical = ProcessInfo.processInfo.physicalMemory
        // The simulator sets no memory limit (0 available): the device's memory is the ceiling there.
        let limit = ProcessMetrics.availableBytes()
        let available = limit > 0 ? limit : physical - min(footprint, physical)
        let io = ProcessMetrics.diskIO()
        let files = appStorage()
        return [
            "cpuPercent": ProcessMetrics.cpuPercent(),
            "usedMemory": Int(clamping: footprint),
            "maxMemory": Int(clamping: footprint + available),
            "systemAvailable": Int(clamping: available),
            "systemTotal": Int(clamping: physical),
            "lowMemory": false,
            "fps": framesPerSecond,
            "frames": frameCount,
            "slowFrames": slowFrameCount,
            "slowestFrameMs": slowestFrameMs,
            "batteryPercent": level >= 0 ? Int((level * 100).rounded()) : -1,
            "charging": device.batteryState == .charging || device.batteryState == .full,
            "plugged": device.batteryState == .unknown ? "Unknown" : device.batteryState.displayName,
            "readBytes": Int(clamping: io.read),
            "writeBytes": Int(clamping: io.written),
            "appFileCount": files.count,
            "appFileBytes": files.bytes
        ]
    }

    private func detail(_ kind: String) -> [String: Any] {
        let time = SharedPanelData.timeFormatter
        switch kind {
        case "frames":
            return [
                "frames": frameCount,
                "slow": slowFrameCount,
                "slowest": slowestFrameMs,
                // Newest first, as the shared screen and Android list them.
                "events": slowFrames.reversed().map { ["time": time.string(from: $0.date), "ms": $0.ms] }
            ]
        case "hangs":
            return [
                "thresholdMs": 250,
                "monitoring": UserDefaults.standard.bool(forKey: Self.hangMonitoringKey),
                "stalls": HangDetectorRunner.shared.events.reversed().map {
                    [
                        "time": time.string(from: $0.timestamp),
                        "ms": Int(($0.duration * 1000).rounded()),
                        "stack": $0.backtrace.joined(separator: "\n")
                    ]
                }
            ]
        case "threads":
            let checker = PerformanceThreadChecker.shared
            return [
                "enabled": checker.isEnabled,
                "violations": checker.getViolations().reversed().map {
                    [
                        "title": "\($0.className).\($0.methodName) on \($0.threadName) · \(time.string(from: $0.timestamp))",
                        "stack": $0.stackTrace.joined(separator: "\n")
                    ]
                }
            ]
        case "memory":
            let physical = ProcessInfo.processInfo.physicalMemory
            let limit = ProcessMetrics.availableBytes()
            let footprint = min(ProcessMetrics.footprintBytes(), physical)
            return [
                "simulated": memoryWarningsSimulated,
                "systemAvailable": Int(clamping: limit > 0 ? limit : physical - footprint),
                "systemTotal": Int(clamping: ProcessInfo.processInfo.physicalMemory),
                "lowMemory": false
            ]
        case "backtraces":
            return [
                "captures": BacktraceManager.shared.backtraces.map { capture in
                    [
                        "title": "\(capture.label ?? "Backtrace") · \(time.string(from: capture.timestamp))",
                        "stack": capture.frames.map(\.symbol).joined(separator: "\n")
                    ]
                }
            ]
        case "leaks":
            let leaks = PerformanceLeakDetector.shared.leaks
            return [
                "destroyed": leaks.count,
                "candidates": leaks.filter(\.isActive).map { leak in
                    [
                        "className": String(leak.details.split(separator: "\n").first ?? "Object"),
                        "ageSeconds": 0,
                        "detail": leak.details
                    ]
                }
            ]
        case "supercalls":
            return [
                "crashes": [String](),
                "violations": SuperCallDetector.shared.violations.reversed().map {
                    ["title": $0.message, "stack": "Revealed by \($0.revealedBy)() at \(time.string(from: $0.timestamp))"]
                }
            ]
        default:
            return ["error": "Unknown performance detail: \(kind)."]
        }
    }

    /// Files and bytes under the app's home directory: the last totals, refreshed in the
    /// background when they are a few seconds old, one walk at a time.
    private func appStorage() -> (count: Int, bytes: Int) {
        let stale = appFiles.map { Date().timeIntervalSince($0.at) >= 5 } ?? true
        if stale, !isWalkingAppFiles {
            isWalkingAppFiles = true
            Task.detached(priority: .utility) {
                let totals = Self.walkAppFiles()
                await MainActor.run {
                    SharedPanelPerformance.shared.appFiles = (totals.count, totals.bytes, Date())
                    SharedPanelPerformance.shared.isWalkingAppFiles = false
                }
            }
        }
        return appFiles.map { ($0.count, $0.bytes) } ?? (0, 0)
    }

    nonisolated private static func walkAppFiles() -> (count: Int, bytes: Int) {
        var count = 0
        var bytes = 0
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        if let files = FileManager.default.enumerator(at: home, includingPropertiesForKeys: keys) {
            for case let url as URL in files {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                count += 1
                bytes += values.fileSize ?? 0
            }
        }
        return (count, bytes)
    }
}

extension SharedPanelPerformance: PerformanceWidgetViewDelegate {
    func performanceWidgetView(_ performanceWidgetView: PerformanceWidgetView, didTapOnSection section: PerformanceSection) {}
}
