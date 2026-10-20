import DebugSwiftCore
import Foundation
import Observation
import SkipFuse

/// Keeps the inspector's list in step with a `NetworkRecorder`, newest request first.
@Observable @MainActor public final class NetworkInspectorModel {
    public private(set) var requests: [NetworkRecordSummary] = []
    public var query = ""
    public private(set) var hasLoaded = false
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private let recorder: NetworkRecorder

    public init(recorder: NetworkRecorder = .shared) {
        self.recorder = recorder
    }

    deinit { observation?.cancel() }

    public var filteredRequests: [NetworkRecordSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return requests }
        return requests.filter { $0.searchableText.contains(trimmed) }
    }

    public func start() {
        guard observation == nil else { return }
        let recorder = recorder
        observation = Task { [weak self] in
            let changes = await recorder.changes()
            await self?.refresh()
            for await _ in changes {
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    public func clear() {
        let recorder = recorder
        Task { await recorder.clear() }
    }

    private func refresh() async {
        let records = await recorder.snapshot()
        requests = records.reversed().map { NetworkRecordSummary(record: $0) }
        hasLoaded = true
    }
}
