import Foundation
import Testing
@testable import DebugSwiftCore

struct NetworkRecordSummaryTests {
    private func record(status: Int = 200, url: String = "https://x.test/", body: Data? = nil) -> NetworkRecord {
        NetworkRecord(
            duration: 0.25,
            method: "GET",
            url: url,
            outcome: .response(statusCode: status, headers: [:], body: body)
        )
    }

    @Test func statusClassesMapToStatus() {
        let expected: [(Int, NetworkRecordSummary.Status)] = [(200, .success), (302, .redirect), (404, .error), (503, .error)]
        for (code, status) in expected {
            #expect(NetworkRecordSummary(record: record(status: code)).status == status)
        }
        let failed = NetworkRecord(duration: 1, method: "GET", url: "https://x.test/", outcome: .failure(description: "boom"))
        let summary = NetworkRecordSummary(record: failed)
        #expect(summary.status == .failed)
        #expect(summary.failureDescription == "boom")
        #expect(summary.statusTitle == "—")
    }

    @Test func splitsHostAndPathAndPrettyPrintsJSON() {
        let summary = NetworkRecordSummary(record: record(url: "https://api.example.com/v1/items?page=2", body: Data(#"{"b":1,"a":2}"#.utf8)))
        #expect(summary.host == "api.example.com")
        #expect(summary.path == "/v1/items?page=2")
        #expect(summary.responseBody == "{\n  \"a\" : 2,\n  \"b\" : 1\n}")
        #expect(summary.durationMilliseconds == 250)
    }

    @Test func summarizesBinaryAndOmitsEmptyBodies() {
        #expect(NetworkRecordSummary(record: record(body: Data([0xFF, 0xFE, 0xFD]))).responseBody == "<3 bytes>")
        #expect(NetworkRecordSummary(record: record(body: Data())).responseBody == nil)
    }
}
