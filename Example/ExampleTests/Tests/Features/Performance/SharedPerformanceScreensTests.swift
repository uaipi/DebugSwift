//
//  SharedPerformanceScreensTests.swift
//  ExampleTests
//

@_spi(DebugSwiftUI) @testable import DebugSwift
@testable import DebugSwiftUI
import Foundation
import Testing

/// The shared SwiftUI Performance screens read the same operations on iOS as on Android. These
/// check that DebugSwift's iOS answers decode into the models the screens use.
@MainActor
struct SharedPerformanceScreensTests {
    init() {
        SharedPanelData.prepare()
    }

    @Test("Live metrics read the process on iOS")
    func liveMetrics() throws {
        let sample = try DebugPerformanceSample.read().get()
        #expect(sample.usedMemory > 0)
        #expect(sample.maxMemory >= sample.usedMemory)
        #expect(sample.systemTotal > 0)
        #expect(sample.nativeHeap == nil)
        #expect(sample.appFileCount >= 0)
    }

    @Test("Every detail kind decodes into its screen's model")
    func details() throws {
        _ = try DebugPerformanceDetail.fetch("frames", as: DebugFrameDetail.self).get()
        let hangs = try DebugPerformanceDetail.fetch("hangs", as: DebugHangDetail.self).get()
        #expect(hangs.monitoring != nil)
        _ = try DebugPerformanceDetail.fetch("threads", as: DebugThreadDetail.self).get()
        _ = try DebugPerformanceDetail.fetch("memory", as: DebugMemoryDetail.self).get()
        _ = try DebugPerformanceDetail.fetch("backtraces", as: DebugBacktraceDetail.self).get()
        _ = try DebugPerformanceDetail.fetch("leaks", as: DebugLeakDetail.self).get()
        let superCalls = try DebugPerformanceDetail.fetch("supercalls", as: DebugSuperCallDetail.self).get()
        #expect(superCalls.violations != nil)
    }

    @Test("Opening the panel sets up DebugSwift on iOS, as the UIKit screens did")
    func panelPreparesTheDebugger() {
        DebugSwiftRuntime.startRuntime()
        #expect(DebugSwiftRuntime.isIOSDebuggerPrepared)
    }

    @Test("A host's own setup marks DebugSwift as set up, so the panel keeps its hidden features")
    func hostSetupIsKept() {
        _ = DebugSwift().setup(hideFeatures: FeatureHandling.hiddenFeatures)
        #expect(SharedPanelData.isDebugSwiftSetUp)
    }

    @Test("Opening the panel keeps an area the host hid with its own setup")
    func panelKeepsHostHiddenFeatures() {
        let hidden = FeatureHandling.hiddenFeatures
        let prepared = DebugSwiftRuntime.isIOSDebuggerPrepared
        defer {
            FeatureHandling.hiddenFeatures = hidden
            DebugSwiftRuntime.isIOSDebuggerPrepared = prepared
        }
        _ = DebugSwift().setup(hideFeatures: [.resources])
        DebugSwiftRuntime.isIOSDebuggerPrepared = false
        DebugSwiftRuntime.startRuntime()
        #expect(FeatureHandling.hiddenFeatures.contains(.resources))
    }

    @Test("Slow frames are listed newest first")
    func slowFramesOrder() async throws {
        _ = DebugSwiftRuntime.perform(featureID: "frame_drops", actionID: "clear")
        for _ in 0..<2 {
            try await Task.sleep(nanoseconds: 150_000_000)
            _ = DebugPerformanceDetail.act("app.perf.stall", ["ms": "80"])
        }
        // A stall is counted when the next frame is drawn, which takes longer on a busy machine.
        var events = try DebugPerformanceDetail.fetch("frames", as: DebugFrameDetail.self).get().events
        for _ in 0..<30 where events.count < 2 {
            try await Task.sleep(nanoseconds: 100_000_000)
            events = try DebugPerformanceDetail.fetch("frames", as: DebugFrameDetail.self).get().events
        }
        #expect(events.count >= 2)
        if events.count >= 2 { #expect(events[0].time >= events[1].time) }
    }

    @Test("A captured backtrace is listed first, and clearing empties the list")
    func backtraces() throws {
        _ = DebugPerformanceDetail.act("app.perf.captureBacktrace", ["all": "false"])
        let captures = try DebugPerformanceDetail.fetch("backtraces", as: DebugBacktraceDetail.self).get().captures
        #expect(captures.first?.title.hasPrefix("Main thread") == true)
        #expect(captures.first?.stack.isEmpty == false)
        _ = DebugPerformanceDetail.act("app.perf.clearBacktraces")
        #expect(try DebugPerformanceDetail.fetch("backtraces", as: DebugBacktraceDetail.self).get().captures.isEmpty)
    }

    @Test("The thread checker toggles and records a test violation")
    func threadChecker() async throws {
        let checker = PerformanceThreadChecker.shared
        let wasEnabled = checker.isEnabled
        defer { if wasEnabled { checker.enable() } else { checker.disable() } }
        checker.disable()
        _ = DebugSwiftRuntime.perform(featureID: "thread_checker", actionID: "clear")
        #expect(DebugPerformanceDetail.act("app.perf.violation") == "Turn on Detect violations first.")

        _ = DebugSwiftRuntime.perform(featureID: "thread_checker", actionID: "toggle")
        #expect(try DebugPerformanceDetail.fetch("threads", as: DebugThreadDetail.self).get().enabled)
        _ = DebugPerformanceDetail.act("app.perf.violation")
        var violations: [DebugStackEntry] = []
        for _ in 0..<50 where violations.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
            violations = try DebugPerformanceDetail.fetch("threads", as: DebugThreadDetail.self).get().violations
        }
        #expect(violations.first?.title.hasPrefix("UIView.setNeedsLayout") == true)
    }

    @Test("Simulated memory warnings are counted")
    func memoryWarning() throws {
        let before = try DebugPerformanceDetail.fetch("memory", as: DebugMemoryDetail.self).get().simulated
        _ = DebugSwiftRuntime.perform(featureID: "memory_warning", actionID: "simulate_memory_warning")
        let after = try DebugPerformanceDetail.fetch("memory", as: DebugMemoryDetail.self).get().simulated
        #expect(after == before + 1)
    }

    @Test("The widget toggles on and off")
    func widget() {
        let wasShown = DebugSwiftRuntime.snapshot(featureID: "performance_widget").hasPrefix("Widget is active")
        _ = DebugSwiftRuntime.perform(featureID: "performance_widget", actionID: "toggle")
        #expect(DebugSwiftRuntime.snapshot(featureID: "performance_widget").hasPrefix("Widget is active") != wasShown)
        _ = DebugSwiftRuntime.perform(featureID: "performance_widget", actionID: "toggle")
        #expect(DebugSwiftRuntime.snapshot(featureID: "performance_widget").hasPrefix("Widget is active") == wasShown)
    }

    @Test("Ticks of one stall are recorded as a single event")
    func stallTicksMerge() async throws {
        let runner = HangDetectorRunner.shared
        runner.clearEvents()
        try await Task.sleep(nanoseconds: 50_000_000)
        let started = Date()
        // Three watchdog reports of one stall that began at `started`, as the timer sends them.
        for elapsed in [0.3, 0.55, 0.8] {
            runner.record(HangEvent(timestamp: started.addingTimeInterval(elapsed), duration: elapsed, backtrace: []))
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(runner.events.count == 1)
        #expect(runner.events.first?.duration == 0.8)
    }
}
