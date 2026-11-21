//
//  FileSharingManager.swift
//  DebugSwift
//
//  Created by Matheus Gois on 19/05/24.
//

import UIKit

enum FileSharingManager {
    static func generateFileAndShare(text: String, fileName: String) {
        let tempURL = URL(
            fileURLWithPath: NSTemporaryDirectory()
        ).appendingPathComponent("\(fileName).txt")

        do {
            try text.write(to: tempURL, atomically: true, encoding: .utf8)
            Task { @MainActor in
                share(tempURL)
            }
        } catch {
            Debug.print("Error: \(error.localizedDescription)")
        }
    }

    /// Presents the share sheet; `completion` runs when it closes, shared or cancelled, or at once
    /// when there is nothing to present it from.
    @MainActor
    static func share(_ tempURL: URL, completion: (@MainActor () -> Void)? = nil) {
        let activity = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        activity.completionWithItemsHandler = { _, _, _, _ in
            MainActor.assumeIsolated { completion?() }
        }

        guard let controller = UIApplication.topViewController() else {
            completion?()
            return
        }

        if let popover = activity.popoverPresentationController {
            popover.sourceView = controller.view
            popover.permittedArrowDirections = .up
        }

        controller.present(activity, animated: true, completion: nil)
    }
}
