import UIKit

public extension DebugSwift {
    /// Resource pages that currently provide native UIKit browsing and editing.
    @MainActor
    static func availableResourceFeatureIDs() -> [String] {
        [
            "files",
            "user_defaults",
            "keychain",
            "persistent_data",
            "core_data",
            "swift_data",
            "http_cookies",
            "database",
            "security_audit"
        ]
    }

    /// Builds a UIKit resource detail page for embedding in the shared SwiftUI navigation.
    @MainActor
    static func debugResourceViewController(for featureID: String) -> UIViewController? {
        let rootController: UIViewController
        switch featureID {
        case "files":
            rootController = ResourcesFilesViewController()
        case "user_defaults":
            let controller = ResourcesGenericController(viewModel: ResourcesUserDefaultsViewModel())
            controller.addDefaultsDiffButton()
            rootController = controller
        case "keychain":
            rootController = ResourcesGenericController(viewModel: ResourcesKeychainViewModel())
        case "persistent_data":
            rootController = ResourcesTabbedController()
        case "core_data":
            rootController = CoreDataBrowserViewController()
        case "swift_data":
            guard #available(iOS 17.0, *) else { return nil }
            rootController = SwiftDataBrowserViewController()
        case "http_cookies":
            rootController = ResourcesGenericController(viewModel: ResourcesHTTPCookiesViewModel())
        case "database":
            rootController = DatabaseBrowserViewController()
        case "security_audit":
            rootController = SecurityAuditViewController()
        default:
            return nil
        }

        let navigationController = UINavigationController(rootViewController: rootController)
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.navigationBar.tintColor = .white
        navigationController.view.backgroundColor = .black
        navigationController.overrideUserInterfaceStyle = .dark
        return navigationController
    }
}
