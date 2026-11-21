//
//  SharedNetworkEntryTests.swift
//  ExampleTests
//

@testable import DebugSwift
import Testing
import UIKit

/// The Network tools have only shared SwiftUI screens now; the UIKit entry points say so.
@MainActor
struct SharedNetworkEntryTests {
    @Test("Each network tool's UIKit entry point points to the shared panel")
    func networkEntryPoints() {
        for id in DebugSwift.availableNetworkFeatureIDs() + ["network_history"] {
            let navigation = DebugSwift.debugNetworkViewController(for: id) as? UINavigationController
            #expect(navigation?.viewControllers.first is SharedPanelOnlyViewController, "\(id)")
        }
        #expect(DebugSwift.debugNetworkViewController(for: "grid") == nil)
        let feature = DebugSwift.debugFeatureViewController(for: .network) as? UINavigationController
        #expect(feature?.viewControllers.first is SharedPanelOnlyViewController)
    }

    @Test("The UIKit tab bar keeps only the Interface tab")
    func uikitTabs() {
        let tabs = DebugSwift.debugViewController() as? UITabBarController
        let roots = tabs?.viewControllers?.compactMap { ($0 as? UINavigationController)?.viewControllers.first } ?? []
        #expect(roots.contains { $0 is InterfaceViewController })
        #expect(!roots.contains { $0 is SharedPanelOnlyViewController })
    }
}
