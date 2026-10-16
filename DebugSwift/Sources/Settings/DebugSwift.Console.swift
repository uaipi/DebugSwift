//
//  DebugSwift.Console.swift
//  DebugSwift
//
//  Created by Matheus Gois on 11/06/24.
//

import UIKit

extension DebugSwift {
    public class Console: @unchecked Sendable {
        public static let shared = Console()
        private init() {}
        
        public var ignoredLogs = [String]()
        public var onlyLogs = [String]()

        /// Returns captured print and NSLog entries in their original order.
        public func messages() -> [String] {
            ConsoleOutput.shared.getPrintAndNSLogOutput()
        }

        /// Removes one captured console entry by its current array index.
        public func removeMessage(at index: Int) {
            let messages = ConsoleOutput.shared.getPrintAndNSLogOutput()
            guard messages.indices.contains(index) else { return }
            ConsoleOutput.shared.removePrintAndNSLogOutput(at: index)
        }

        /// Removes every captured print and NSLog entry.
        public func clear() {
            ConsoleOutput.shared.removeAll()
        }

        /// Shares the captured print and NSLog entries as a text file.
        @MainActor
        public func shareMessages() {
            let text = messages().joined(separator: "\n")
            FileSharingManager.generateFileAndShare(text: text, fileName: "console")
        }
    }
}
