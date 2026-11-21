//
//  DebugSwift.swift
//  DebugSwift
//
//  Created by Matheus Gois on 16/12/23.
//

import UIKit

public class DebugSwift {
    /// Counts visibility requests, so the delayed appearance `show()` schedules is dropped when a
    /// `hide()` or `toggle()` came after it.
    private static let visibilityRequests = FloatingBallRequests()
    
    public init() {}
    
    @discardableResult
    @MainActor
    public func setup(
        hideFeatures features: [DebugSwiftFeature] = [],
        disable methods: [DebugSwiftSwizzleFeature] = [],
        enableBetaFeatures betaFeatures: [DebugSwiftBetaFeature] = []
    ) -> Self {
        FeatureHandling.setup(hide: features, disable: methods, enableBeta: betaFeatures)
        LaunchTimeTracker.shared.measureAppStartUpTime()
        setupEventBusLifecycleListeners()

        return self
    }

    private func setupEventBusLifecycleListeners() {
        let bus = EventBusSubscriber.shared
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            bus.publish(DebugEvent(timestamp: Date(), domain: .app, summary: "App became active"))
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            bus.publish(DebugEvent(timestamp: Date(), domain: .app, summary: "App entered background"))
        }
    }

    @discardableResult
    public func show() -> Self {
        let request = Self.visibilityRequests.next()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard Self.visibilityRequests.isLatest(request) else { return }
            FloatViewManager.show()
        }

        return self
    }

    @discardableResult
    @MainActor
    public func hide() -> Self {
        _ = Self.visibilityRequests.next()
        FloatViewManager.remove()
        return self
    }

    @discardableResult
    @MainActor
    public func toggle() -> Self {
        _ = Self.visibilityRequests.next()
        FloatViewManager.toggle()

        return self
    }

    /// Call this before presenting the view controller returned by `debugViewController()`.
    /// If the floating ball is currently visible it is hidden for the duration of the
    /// presentation so it cannot open a second debug menu on top of yours.
    ///
    /// Always pair with `debugViewControllerDidDismiss()` — safe to call even when
    /// the floating ball is not in use.
    @MainActor
    public static func debugViewControllerWillPresent() {
        if FloatViewManager.isShowing() {
            _floatingBallWasVisible = true
            FloatViewManager.remove()
        }
    }

    /// Call this after dismissing the view controller returned by `debugViewController()`.
    /// Restores the floating ball if it was visible before `debugViewControllerWillPresent()`.
    @MainActor
    public static func debugViewControllerDidDismiss() {
        if _floatingBallWasVisible {
            FloatViewManager.show()
            _floatingBallWasVisible = false
        }
    }

    @MainActor private static var _floatingBallWasVisible = false

    /// Returns a standalone debug menu view controller that you can present
    /// however you like — push, present modally, embed in a tab bar, etc.
    ///
    /// This view controller is independent from the floating ball.
    /// Call `setup()` before using this method.
    ///
    ///     let debugVC = DebugSwift.debugViewController()
    ///     navigationController?.pushViewController(debugVC, animated: true)
    ///
    @MainActor
    public static func debugViewController() -> UIViewController {
        var controllers: [UIViewController & MainFeatureType] = [
            NetworkViewController(),
            InterfaceViewController()
        ]

        let hidden = FeatureHandling.hiddenFeatures
        controllers.removeAll(where: { hidden.contains($0.controllerType) })

        let custom = App.shared.customControllers?() ?? []

        let tabBar = UITabBarController()
        tabBar.viewControllers = (controllers as [UIViewController] + custom).map {
            $0.navigationItem.largeTitleDisplayMode = .always
            let nav = UINavigationController(rootViewController: $0)
            nav.navigationBar.prefersLargeTitles = true
            return nav
        }
        tabBar.tabBar.tintColor = .white
        tabBar.tabBar.unselectedItemTintColor = .gray
        tabBar.tabBar.setBackgroundColor(color: .black)
        tabBar.tabBar.addTopBorderWithColor(color: .gray, thickness: 0.3)
        tabBar.overrideUserInterfaceStyle = .dark
        tabBar.view.backgroundColor = .black

        return tabBar
    }

    /// Returns one native feature screen wrapped in its own navigation controller.
    /// Shared SwiftUI panels can use this to keep category navigation in SwiftUI
    /// while retaining the UIKit implementation for feature screens that have not
    /// been migrated yet.
    @MainActor
    public static func debugFeatureViewController(for feature: DebugSwiftFeature) -> UIViewController {
        let rootController: UIViewController

        switch feature {
        case .network:
            rootController = NetworkViewController()
        case .performance:
            rootController = SharedPanelOnlyViewController(
                title: "Performance",
                message: "The Performance tools are in the shared SwiftUI panel. Add DebugSwiftUI and call DebugSwiftSharedPanel.useForFloatingBall()."
            )
        case .interface:
            rootController = InterfaceViewController()
        case .resources:
            rootController = SharedPanelOnlyViewController(
                title: "Resources",
                message: "The Resources tools are in the shared SwiftUI panel. Add DebugSwiftUI and call DebugSwiftSharedPanel.useForFloatingBall()."
            )
        case .app:
            rootController = SharedPanelOnlyViewController(
                title: "App",
                message: "The App tools are in the shared SwiftUI panel. Add DebugSwiftUI and call DebugSwiftSharedPanel.useForFloatingBall()."
            )
        }

        rootController.navigationItem.largeTitleDisplayMode = .always

        let navigationController = UINavigationController(rootViewController: rootController)
        navigationController.navigationBar.prefersLargeTitles = true
        navigationController.navigationBar.tintColor = .white
        navigationController.view.backgroundColor = .black
        navigationController.overrideUserInterfaceStyle = .dark
        return navigationController
    }

    /// The default feature categories that are currently visible in the debugger.
    @MainActor
    public static func availableDebugFeatures() -> [DebugSwiftFeature] {
        DebugSwiftFeature.allCases.filter { !FeatureHandling.hiddenFeatures.contains($0) }
    }
}

public extension DebugSwift {
    /// The network tools exposed in the shared SwiftUI feature list.
    @MainActor
    static func availableNetworkFeatureIDs() -> [String] {
        var featureIDs = ["http", "network_injection", "network_thresholds", "graphql", "network_encryption", "har_export", "webview_network"]
        let disabledMethods = App.shared.disableMethods
        if !disabledMethods.contains(.webSocket) {
            featureIDs.append("websocket")
        }
        if disabledMethods.contains(.wkWebView) {
            featureIDs.removeAll { $0 == "webview_network" }
        }
        #if canImport(SwiftData)
        if #available(iOS 17.0, *),
           FeatureHandling.enabledBetaFeatures.contains(.networkSessionPersistence),
           NetworkSessionPersistenceManager.isPersistenceEnabledPreference {
            featureIDs.append("network_history")
        }
        #endif
        return featureIDs
    }

    /// Builds an existing UIKit network inspector for a single shared feature row.
    @MainActor
    static func debugNetworkViewController(for featureID: String) -> UIViewController? {
        let rootController: UIViewController
        switch featureID {
        case "http", "graphql", "network_encryption", "har_export":
            rootController = NetworkViewController(mode: .http)
        case "websocket":
            rootController = NetworkViewController(mode: .websocket)
        case "webview_network":
            rootController = NetworkViewController(mode: .webview)
        case "network_injection":
            rootController = NetworkInjectionSettingsController()
        case "network_thresholds":
            rootController = NetworkThresholdController()
        case "network_history":
            #if canImport(SwiftData)
            guard #available(iOS 17.0, *) else { return nil }
            rootController = NetworkSessionHistoryViewController()
            #else
            return nil
            #endif
        default:
            return nil
        }

        rootController.navigationItem.largeTitleDisplayMode = .never
        let navigationController = UINavigationController(rootViewController: rootController)
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.tintColor = .white
        navigationController.view.backgroundColor = .black
        navigationController.overrideUserInterfaceStyle = .dark
        return navigationController
    }

    /// The resource tools exposed in the shared SwiftUI feature list.
    @MainActor
    static func availableResourceFeatureIDs() -> [String] {
        [
            "files", "user_defaults", "keychain", "persistent_data", "core_data", "swift_data",
            "http_cookies", "database", "security_audit"
        ]
    }

    /// The app tools exposed in the shared SwiftUI feature list, without those the host turned off.
    @MainActor
    static func availableAppFeatureIDs() -> [String] {
        let disabled = App.shared.disableMethods
        var featureIDs = ["device_info", "push_token", "custom_actions", "custom_info"]
        if !disabled.contains(.crashManager) { featureIDs.append("crashes") }
        if !disabled.contains(.console) { featureIDs.append("console") }
        featureIDs.append("oslog_console")
        if !disabled.contains(.location) { featureIDs.append("location") }
        featureIDs.append("loaded_libraries")
        if !disabled.contains(.pushNotifications) { featureIDs.append("push_simulator") }
        featureIDs += ["deep_links", "event_bus"]
        if FeatureHandling.enabledBetaFeatures.contains(.agentDebugLog) { featureIDs.append("agent_debug_log") }
        return featureIDs
    }

    /// The performance tools exposed in the shared SwiftUI feature list.
    @MainActor
    static func availablePerformanceFeatureIDs() -> [String] {
        var featureIDs = [
            "performance_overview", "performance_widget", "battery", "disk",
            "memory_warning", "frame_drops", "hangs", "backtraces", "leaks",
            "thread_checker", "super_calls"
        ]
        let disabledMethods = App.shared.disableMethods
        if disabledMethods.contains(.leaksDetector) {
            featureIDs.removeAll { $0 == "leaks" }
        }
        if disabledMethods.contains(.superCallDetector) {
            featureIDs.removeAll { $0 == "super_calls" }
        }
        return featureIDs
    }

}

/// A thread-safe counter of floating-ball visibility requests; the newest one wins.
private final class FloatingBallRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var latest = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        latest += 1
        return latest
    }

    func isLatest(_ request: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return request == latest
    }
}
