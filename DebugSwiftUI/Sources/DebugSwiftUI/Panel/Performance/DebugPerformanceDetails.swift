import Foundation

struct DebugFrameEvent: Decodable {
    let time: String
    let ms: Int
}

struct DebugFrameDetail: Decodable {
    let frames: Int
    let slow: Int
    let slowest: Int
    let events: [DebugFrameEvent]
}

struct DebugStall: Decodable {
    let time: String
    let ms: Int
    let stack: String
}

struct DebugHangDetail: Decodable {
    let thresholdMs: Int
    let stalls: [DebugStall]
}

/// A titled call stack: a backtrace capture or a StrictMode violation.
struct DebugStackEntry: Decodable {
    let title: String
    let stack: String
}

struct DebugBacktraceDetail: Decodable {
    let captures: [DebugStackEntry]
}

struct DebugLeakCandidate: Decodable {
    let className: String
    let ageSeconds: Int
}

struct DebugLeakDetail: Decodable {
    let destroyed: Int
    let candidates: [DebugLeakCandidate]
}

struct DebugThreadDetail: Decodable {
    let enabled: Bool
    let violations: [DebugStackEntry]
}

struct DebugSuperCallDetail: Decodable {
    let crashes: [String]
}

struct DebugMemoryDetail: Decodable {
    let simulated: Int
    let systemAvailable: Int
    let systemTotal: Int
    let lowMemory: Bool
}

enum DebugPerformanceDetail {
    static func fetch<T: Decodable>(_ kind: String, as type: T.Type = T.self) -> Result<T, DebugResourceFailure> {
        DebugResourceClient.fetch("app.perf.detail", ["kind": kind], as: type)
    }

    /// Runs an action that answers with a message, and returns that message.
    static func act(_ operation: String, _ arguments: [String: String] = [:]) -> String {
        switch DebugResourceClient.fetch(operation, arguments, as: DebugActionReply.self) {
        case let .success(reply): reply.message ?? ""
        case let .failure(error): error.message
        }
    }
}
