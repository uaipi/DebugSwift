//
//  DebugSwift.swift
//  DebugSwift
//
//  Created by Matheus Gois on 16/12/23.
//

import UIKit

public class DebugSwift {
    
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            FloatViewManager.show()
        }

        return self
    }

    @discardableResult
    @MainActor
    public func hide() -> Self {
        FloatViewManager.remove()
        return self
    }

    @discardableResult
    @MainActor
    public func toggle() -> Self {
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
            PerformanceViewController(),
            InterfaceViewController(),
            ResourcesViewController(),
            AppViewController()
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
            rootController = PerformanceViewController()
        case .interface:
            rootController = InterfaceViewController()
        case .resources:
            rootController = ResourcesViewController()
        case .app:
            rootController = AppViewController()
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
