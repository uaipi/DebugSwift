import Foundation
import UIKit

/// Settings in the Interface section that can be controlled from shared UI.
public enum DebugSwiftInterfaceSetting: String, CaseIterable, Sendable {
    case touches
    case colorizedBorders
    case slowAnimations
    case darkMode
    case measurement
    case swiftUIRenderTracking
}

/// Shared configuration for the native grid overlay.
public struct DebugSwiftGridOverlaySettings: Equatable, Sendable {
    public var isEnabled: Bool
    public var size: Double
    public var opacity: Double
    public var colorIndex: Int

    public init(isEnabled: Bool, size: Double, opacity: Double, colorIndex: Int) {
        self.isEnabled = isEnabled
        self.size = size
        self.opacity = opacity
        self.colorIndex = colorIndex
    }
}

public extension DebugSwift {
    @MainActor
    static func interfaceSettingIsEnabled(_ setting: DebugSwiftInterfaceSetting) -> Bool {
        switch setting {
        case .touches:
            UserInterfaceToolkit.shared.showingTouchesEnabled
        case .colorizedBorders:
            UserInterfaceToolkit.colorizedViewBordersEnabled
        case .slowAnimations:
            UserInterfaceToolkit.shared.slowAnimationsEnabled
        case .darkMode:
            UserInterfaceToolkit.shared.darkModeEnabled
        case .measurement:
            Measurement.isActive
        case .swiftUIRenderTracking:
            UserInterfaceToolkit.shared.swiftUIRenderTrackingEnabled
        }
    }

    @MainActor
    static func setInterfaceSetting(_ setting: DebugSwiftInterfaceSetting, enabled: Bool) {
        switch setting {
        case .touches:
            UserInterfaceToolkit.shared.showingTouchesEnabled = enabled
        case .colorizedBorders:
            UserInterfaceToolkit.colorizedViewBordersEnabled = enabled
        case .slowAnimations:
            UserInterfaceToolkit.shared.slowAnimationsEnabled = enabled
        case .darkMode:
            UserInterfaceToolkit.shared.darkModeEnabled = enabled
        case .measurement:
            if enabled {
                Measurement.activate()
            } else {
                Measurement.deactivate()
            }
        case .swiftUIRenderTracking:
            UserInterfaceToolkit.shared.swiftUIRenderTrackingEnabled = enabled
        }
    }

    @MainActor
    static func gridOverlaySettings() -> DebugSwiftGridOverlaySettings {
        let toolkit = UserInterfaceToolkit.shared
        return DebugSwiftGridOverlaySettings(
            isEnabled: toolkit.isGridOverlayShown,
            size: Double(toolkit.gridOverlay.gridSize),
            opacity: Double(toolkit.gridOverlay.opacity),
            colorIndex: toolkit.selectedGridOverlayColorSchemeIndex
        )
    }

    @MainActor
    static func setGridOverlaySettings(_ settings: DebugSwiftGridOverlaySettings) {
        let toolkit = UserInterfaceToolkit.shared
        toolkit.isGridOverlayShown = settings.isEnabled
        toolkit.gridOverlay.gridSize = NSInteger(min(max(settings.size.rounded(), 4), 64))
        toolkit.gridOverlay.opacity = CGFloat(min(max(settings.opacity, 0.1), 1.0))
        toolkit.selectedGridOverlayColorSchemeIndex = min(
            max(settings.colorIndex, 0),
            toolkit.gridOverlayColorSchemes.count - 1
        )
    }

    /// The SwiftUI render, documentation recorder and color palette tools are in the shared SwiftUI
    /// panel; this returns a screen that says so, or nil for any other ID.
    @MainActor
    static func debugInterfaceViewController(for featureID: String) -> UIViewController? {
        let titles = ["swiftui_render": "SwiftUI Render Tracking", "doc_recorder": "Documentation Recorder", "color_palette": "Color Palette"]
        guard let title = titles[featureID] else { return nil }
        let rootController = SharedPanelOnlyViewController(
            title: title,
            message: "This tool is in the shared SwiftUI panel. Add DebugSwiftUI and call DebugSwiftSharedPanel.useForFloatingBall()."
        )
        let navigationController = UINavigationController(rootViewController: rootController)
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.tintColor = .white
        navigationController.view.backgroundColor = .black
        navigationController.overrideUserInterfaceStyle = .dark
        return navigationController
    }

    /// Interface options currently visible in the native debugger configuration.
    @MainActor
    static func availableInterfaceFeatureIDs() -> [String] {
        var featureIDs = InterfaceViewController.Features.allCasesWithPermissions.map { feature in
            switch feature {
            case .colorize: "colorize"
            case .animations: "animations"
            case .touches: "touches"
            case .grid: "grid"
            case .darkMode: "dark_mode"
            case .measurement: "measurement"
            }
        }
        // Tools with only a shared SwiftUI screen.
        if !App.shared.disableMethods.contains(.swiftUIRender),
           FeatureHandling.enabledBetaFeatures.contains(.swiftUIRenderTracking) {
            featureIDs.append("swiftui_render")
        }
        featureIDs += ["doc_recorder", "color_palette"]
        return featureIDs
    }
}
