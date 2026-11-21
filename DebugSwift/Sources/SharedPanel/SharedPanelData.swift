//
//  SharedPanelData.swift
//  DebugSwift
//

import Foundation
import UIKit

/// The data the shared SwiftUI panel (DebugSwiftUI) shows on iOS. On Android the Kotlin runtime
/// answers the same operations, in the same JSON shapes, so one set of screens serves both.
///
/// Not part of DebugSwift's public API: DebugSwiftUI reaches it with
/// `@_spi(DebugSwiftUI) import DebugSwift`.
@_spi(DebugSwiftUI)
public enum SharedPanelData {
    /// Starts what the shared screens read continuously (frame timing, saved monitors). Called once
    /// when the shared panel is set up.
    @MainActor
    public static func prepare() {
        SharedPanelPerformance.shared.prepare()
        SharedPanelInterface.shared.prepare()
    }

    /// Whether DebugSwift's setup already ran (`DebugSwift().setup(...)` by the host), so the
    /// shared panel doesn't run it again and replace the host's hidden features.
    @MainActor
    public static var isDebugSwiftSetUp: Bool { FeatureHandling.isSetUp }

    /// Answers a data operation (`app.perf.sample`, `app.perf.detail`, …) with its JSON, or
    /// `{"error": …}` when the operation is unknown or fails.
    @MainActor
    public static func resource(_ operation: String, _ arguments: [String: String]) -> String {
        let reply: [String: Any]
        if operation.hasPrefix("app.perf.") {
            reply = SharedPanelPerformance.shared.resource(operation, arguments)
        } else if let app = SharedPanelApp.shared.resource(operation, arguments) {
            reply = app
        } else if let resources = SharedPanelResources.shared.resource(operation, arguments) {
            reply = resources
        } else if let interface = SharedPanelInterface.shared.resource(operation, arguments) {
            reply = interface
        } else {
            reply = ["error": "This tool is not available on iOS."]
        }
        return json(reply)
    }

    /// Runs a screen action, or returns nil when this feature's action is not handled here.
    @MainActor
    public static func perform(featureID: String, actionID: String, value: String) -> String? {
        SharedPanelPerformance.shared.perform(featureID: featureID, actionID: actionID, value: value)
            ?? SharedPanelApp.shared.perform(featureID: featureID, actionID: actionID, value: value)
            ?? SharedPanelResources.shared.perform(featureID: featureID, actionID: actionID, value: value)
            ?? SharedPanelInterface.shared.perform(featureID: featureID, actionID: actionID, value: value)
    }

    /// A feature's text snapshot, or nil when this feature is not handled here.
    @MainActor
    public static func snapshot(featureID: String) -> String? {
        SharedPanelPerformance.shared.snapshot(featureID: featureID)
            ?? SharedPanelApp.shared.snapshot(featureID: featureID)
    }

    /// The empty view the shared panel places in itself, so screen captures can leave it out.
    @MainActor
    public static func makePanelMarker() -> UIView {
        SharedPanelMarkerView()
    }

    static func json(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return #"{"error":"The tool returned data that could not be encoded."}"#
        }
        return text
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
