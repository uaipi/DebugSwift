//
//  DebugSwift.App.swift
//  DebugSwift
//
//  Created by Matheus Gois on 11/06/24.
//

import UIKit

extension DebugSwift {
    public class App: @unchecked Sendable {
        public static let shared = App()
        private init() {}
        
        public var customInfo: (() -> [CustomData])?
        public var customAction: (() -> [CustomAction])?
        public var customControllers: (() -> [UIViewController])?

        /// Builds the screen the floating ball opens; `nil` opens the built-in UIKit tab bar.
        /// `DebugSwiftSharedPanel.useForFloatingBall()` in DebugSwiftUI sets it to the shared
        /// SwiftUI panel, the one Android uses. Changes apply the next time the debugger opens.
        @MainActor public var panelProvider: (@MainActor () -> UIViewController)? {
            didSet { FeatureHandling.reloadPanelIfInstalled() }
        }

        @MainActor private var _defaultControllers: [UIViewController & MainFeatureType]?
        
        @MainActor var defaultControllers: [UIViewController & MainFeatureType] {
            get {
                if _defaultControllers == nil {
                    _defaultControllers = [
                        InterfaceViewController()
                    ]
                }
                return _defaultControllers!
            }
            set {
                _defaultControllers = newValue
            }
        }

        var disableMethods: [DebugSwiftSwizzleFeature] = []
        
        @MainActor
        @discardableResult
        public static func presentDebugger() -> App.Type {
            WindowManager.presentDebugger()
            return self
        }

        /// Writes `agent-snapshot.json` next to the agent debug log and returns its location: app,
        /// device, current CPU and memory, and the latest requests with sanitized URLs. Useful from a
        /// test failure handler or a custom action, so a coding agent can read the state it left.
        @MainActor
        @discardableResult
        public static func writeAgentSnapshot() throws -> URL {
            try AgentDebugLog.shared.writeSnapshot()
        }

        @MainActor
        @discardableResult
        public static func removeDebugger() -> App.Type {
            WindowManager.removeDebugger()
            return self
        }
    }
}
