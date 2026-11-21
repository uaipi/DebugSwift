//
//  SharedInterfaceScreensTests.swift
//  ExampleTests
//

@_spi(DebugSwiftUI) @testable import DebugSwift
@testable import DebugSwiftUI
import Foundation
import Testing
import UIKit

/// The shared SwiftUI Interface screens read the same operations on iOS as on Android. These check
/// that DebugSwift's iOS answers decode into the models the screens use.
@MainActor
@Suite(.serialized)
struct SharedInterfaceScreensTests {
    @Test("SwiftUI render tracking turns on, counts renders by view type, and clears")
    func renderTracking() async throws {
        SharedPanelData.prepare()
        let tracker = SwiftUIRenderTracker.shared
        let wasEnabled = tracker.isEnabled
        let previousStyle = tracker.overlayStyle
        defer {
            UserInterfaceToolkit.shared.swiftUIRenderTrackingEnabled = wasEnabled
            tracker.overlayStyle = previousStyle
            tracker.clearStats()
        }
        _ = DebugSwiftRuntime.perform(featureID: "swiftui_render", actionID: "tracking", value: "true")
        _ = DebugSwiftRuntime.perform(featureID: "swiftui_render", actionID: "style", value: "none")
        _ = DebugSwiftRuntime.perform(featureID: "swiftui_render", actionID: "clear")
        #expect(DebugSwiftRuntime.perform(featureID: "swiftui_render", actionID: "style", value: "sparkles").contains("Unknown"))

        let first = UIView()
        let second = UIView()
        tracker.trackRender(for: first, viewType: "CardView")
        tracker.trackRender(for: first, viewType: "CardView")
        tracker.trackRender(for: second, viewType: "CardView")
        tracker.trackRender(for: second, viewType: "RowView")

        var state = try DebugResourceClient.fetch("app.compose.state", as: DebugComposeState.self).get()
        #expect(state.tracking == true)
        #expect(state.style == "none")
        #expect(state.total == 4)
        #expect(state.recomposers == 3)
        #expect(state.views?.first?.name == "CardView")
        #expect(state.views?.first?.count == 3)
        #expect(state.views?.last?.name == "RowView")

        // Only renders counted by `.trackRenders()` are probe renders, not every hosting view.
        let probesBefore = state.probeRenders
        NotificationCenter.default.post(name: .swiftUIViewDidRender, object: ["viewName": "Probe", "renderCount": 1])
        try await Task.sleep(nanoseconds: 100_000_000)
        state = try DebugResourceClient.fetch("app.compose.state", as: DebugComposeState.self).get()
        #expect(state.probeRenders == probesBefore + 1)

        _ = DebugSwiftRuntime.perform(featureID: "swiftui_render", actionID: "clear")
        state = try DebugResourceClient.fetch("app.compose.state", as: DebugComposeState.self).get()
        #expect(state.total == 0)
        #expect(state.views?.isEmpty == true)

        _ = DebugSwiftRuntime.perform(featureID: "swiftui_render", actionID: "tracking", value: "false")
        tracker.trackRender(for: first, viewType: "CardView")
        state = try DebugResourceClient.fetch("app.compose.state", as: DebugComposeState.self).get()
        #expect(state.tracking == false)
        #expect(state.total == 0)
    }

    @Test("The documentation recorder keeps taps and scrolls only while on, and saves an annotated screenshot")
    func documentationRecorder() async throws {
        let recorder = SharedPanelInterface.shared
        _ = DebugPerformanceDetail.act("app.doc.clear")
        defer {
            _ = DebugPerformanceDetail.act("app.doc.record", ["on": "false"])
            _ = DebugPerformanceDetail.act("app.doc.clear")
        }
        recorder.recordTouch(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 12, y: 10))
        _ = DebugPerformanceDetail.act("app.doc.record", ["on": "true"])
        recorder.recordTouch(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 103, y: 202))
        recorder.recordTouch(from: CGPoint(x: 150, y: 500), to: CGPoint(x: 150, y: 300))

        var state = try DebugResourceClient.fetch("app.doc.state", as: DebugDocState.self).get()
        #expect(state.recording)
        #expect(state.density == 1)
        #expect(state.gestures.map(\.kind) == ["tap", "scroll"])
        #expect(state.gestures.last?.startY == 500)
        #expect(state.gestures.last?.endY == 300)
        #expect(DebugDocRecorderView().describe(state.gestures[0], density: state.density) == "Tap at (103, 202) pt")

        let message = DebugPerformanceDetail.act("app.doc.capture")
        #expect(message.contains("Screenshot saved"))
        state = try DebugResourceClient.fetch("app.doc.state", as: DebugDocState.self).get()
        let image = try #require(UIImage(contentsOfFile: state.screenshot)?.cgImage)
        let window = try #require(SharedPanelInterface.appWindow())
        #expect(CGFloat(image.width) == window.bounds.width * window.screen.scale)

        let saved = state.screenshot
        _ = DebugPerformanceDetail.act("app.doc.clear")
        #expect(!FileManager.default.fileExists(atPath: saved))
        state = try DebugResourceClient.fetch("app.doc.state", as: DebugDocState.self).get()
        #expect(state.gestures.isEmpty)
        #expect(state.screenshot.isEmpty)
        #expect(DebugSwiftRuntime.perform(featureID: "doc_recorder", actionID: "export") == "Capture a screenshot first.")
    }

    @Test("A capture numbers the last 24 gestures as the recorder's list does")
    func gestureNumbers() {
        let recorder = SharedPanelInterface.shared
        _ = DebugPerformanceDetail.act("app.doc.clear")
        _ = DebugPerformanceDetail.act("app.doc.record", ["on": "true"])
        defer {
            _ = DebugPerformanceDetail.act("app.doc.record", ["on": "false"])
            _ = DebugPerformanceDetail.act("app.doc.clear")
        }
        for index in 0..<30 {
            recorder.recordTouch(from: CGPoint(x: index, y: 0), to: CGPoint(x: index, y: 0))
        }
        let (marks, firstNumber) = recorder.annotatedGestures()
        #expect(marks.count == 24)
        #expect(firstNumber == 7)
        #expect(marks.first?.end.x == 6)
    }

    @Test("Captures leave out the shared panel when it is presented in the app's window")
    func capturesSkipThePanel() throws {
        let window = try #require(SharedPanelInterface.appWindow())
        // A sheet puts the panel in a container of its own, a direct subview of the app's window.
        let container = UIView(frame: window.bounds)
        container.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        container.addSubview(SharedPanelData.makePanelMarker())
        window.addSubview(container)
        defer { container.removeFromSuperview() }

        #expect(SharedPanelInterface.panelContainers(in: window) == [container])
        // Touches on the panel are not the app's.
        let button = UIView()
        container.addSubview(button)
        let panels = SharedPanelInterface.panelContainers(in: window)
        #expect(!SharedPanelInterface.isAppTouch(on: button, panels: panels))
        #expect(SharedPanelInterface.isAppTouch(on: window.rootViewController?.view, panels: panels))
        let result = try DebugResourceClient.fetch("app.ui.palette", as: DebugPaletteResult.self).get()
        let red = result.colors.first { $0.hex == "#FF0000" }?.percent ?? 0
        #expect(red < 50)
        #expect(!container.isHidden)
    }

    @Test("The palette ranks colors by share, merges close shades, and skips see-through pixels")
    func paletteRanking() {
        func pixels(_ color: (UInt8, UInt8, UInt8, UInt8), _ count: Int) -> [UInt8] {
            Array(repeating: [color.0, color.1, color.2, color.3], count: count).flatMap { $0 }
        }
        // (235, 10, 10) falls in another bucket but is too close to red to be listed.
        let rgba = pixels((255, 0, 0, 255), 60) + pixels((235, 10, 10, 255), 15)
            + pixels((0, 0, 255, 255), 25) + pixels((0, 255, 0, 10), 50)
        let colors = SharedPanelInterface.dominantColors(rgba)
        #expect(colors.count == 2)
        #expect(colors.first?["hex"] as? String == "#FF0000")
        #expect(colors.first?["percent"] as? Double == 60)
        #expect(colors.last?["hex"] as? String == "#0000FF")
        #expect(colors.last?["percent"] as? Double == 25)
    }

    @Test("The palette reads the app's window")
    func paletteFromScreen() throws {
        let result = try DebugResourceClient.fetch("app.ui.palette", as: DebugPaletteResult.self).get()
        #expect(result.source == "screen")
        #expect(!result.colors.isEmpty)
        #expect(result.colors.allSatisfy { $0.hex.count == 7 && $0.hex.hasPrefix("#") })
    }

    @Test("The three tools are listed for the shared panel, and the UIKit entry point points there")
    func listing() {
        let ids = DebugSwift.availableInterfaceFeatureIDs()
        #expect(ids.contains("doc_recorder"))
        #expect(ids.contains("color_palette"))
        for id in ["swiftui_render", "doc_recorder", "color_palette"] {
            let navigation = DebugSwift.debugInterfaceViewController(for: id) as? UINavigationController
            #expect(navigation?.viewControllers.first is SharedPanelOnlyViewController)
        }
        #expect(DebugSwift.debugInterfaceViewController(for: "grid") == nil)
    }
}
