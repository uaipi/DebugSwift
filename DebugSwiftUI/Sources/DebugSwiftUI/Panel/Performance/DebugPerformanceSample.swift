import Foundation

/// One reading of the app's live metrics, as the Android tools report it.
struct DebugPerformanceSample: Decodable {
    let cpuPercent: Double
    let usedMemory: Int
    let maxMemory: Int
    let nativeHeap: Int
    let systemAvailable: Int
    let systemTotal: Int
    let lowMemory: Bool
    let fps: Int
    let frames: Int
    let slowFrames: Int
    let slowestFrameMs: Int
    let batteryPercent: Int
    let charging: Bool
    let plugged: String
    let readBytes: Int
    let writeBytes: Int
    let appFileCount: Int
    let appFileBytes: Int

    static func read() -> Result<DebugPerformanceSample, DebugResourceFailure> {
        DebugResourceClient.fetch("app.perf.sample", as: DebugPerformanceSample.self)
    }
}

/// The last readings of one metric, newest last, capped so the chart keeps a fixed width.
struct DebugMetricHistory {
    static let capacity = 60

    private(set) var values: [Double] = []

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > Self.capacity { values.removeFirst(values.count - Self.capacity) }
    }
}
