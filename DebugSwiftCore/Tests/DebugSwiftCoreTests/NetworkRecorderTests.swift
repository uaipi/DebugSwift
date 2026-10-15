import Foundation
import Testing
@testable import DebugSwiftCore

struct NetworkRecorderTests {
    private func record(
        url: String = "https://example.test/a",
        status: Int = 200,
        requestHeaders: [String: String] = [:],
        responseHeaders: [String: String] = [:],
        requestBody: Data? = nil,
        responseBody: Data? = nil
    ) -> NetworkRecord {
        NetworkRecord(
            duration: 0.25,
            method: "GET",
            url: url,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            outcome: .response(statusCode: status, headers: responseHeaders, body: responseBody)
        )
    }

    @Test func keepsOnlyTheMostRecentRecords() async {
        let recorder = NetworkRecorder(capacity: 3)
        for index in 0..<5 {
            await recorder.record(record(url: "https://example.test/\(index)"))
        }
        let urls = await recorder.snapshot().map(\.url)
        #expect(urls == ["https://example.test/2", "https://example.test/3", "https://example.test/4"])
    }

    @Test func masksSensitiveHeadersCaseInsensitively() async {
        let recorder = NetworkRecorder()
        await recorder.record(record(
            requestHeaders: ["authorization": "Bearer secret", "Accept": "application/json"],
            responseHeaders: ["SET-COOKIE": "session=secret", "Content-Type": "application/json"]
        ))
        let stored = await recorder.snapshot()[0]
        #expect(stored.requestHeaders["authorization"] == "<redacted>")
        #expect(stored.requestHeaders["Accept"] == "application/json")
        if case let .response(_, headers, _) = stored.outcome {
            #expect(headers["SET-COOKIE"] == "<redacted>")
            #expect(headers["Content-Type"] == "application/json")
        } else {
            Issue.record("expected a response outcome")
        }
    }

    @Test func truncatesLongBodies() async {
        let recorder = NetworkRecorder(bodyLimit: 4)
        await recorder.record(record(requestBody: Data("abcdefgh".utf8), responseBody: Data("12345678".utf8)))
        let stored = await recorder.snapshot()[0]
        #expect(stored.requestBody == Data("abcd".utf8))
        #expect(stored.responseBody == Data("1234".utf8))
    }

    @Test func exportsRecordsAsHAR() async throws {
        let recorder = NetworkRecorder()
        await recorder.record(record(status: 404, responseBody: Data("missing".utf8)))
        await recorder.record(NetworkRecord(
            duration: 1,
            method: "POST",
            url: "https://example.test/b",
            outcome: .failure(description: "timed out")
        ))
        let json = try #require(await recorder.harJSON(pretty: false))
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let log = try #require(object["log"] as? [String: Any])
        let entries = try #require(log["entries"] as? [[String: Any]])
        #expect(entries.count == 2)
        let statuses = entries.compactMap { ($0["response"] as? [String: Any])?["status"] as? Int }
        #expect(statuses == [404, 0])
    }

    @Test func clearEmptiesTheStoreAndNotifiesObservers() async {
        let recorder = NetworkRecorder()
        var changes = await recorder.changes().makeAsyncIterator()
        await recorder.record(record())
        _ = await changes.next()
        await recorder.clear()
        _ = await changes.next()
        #expect(await recorder.snapshot().isEmpty)
    }

    @Test func derivesSuccessFromStatusCode() {
        #expect(record(status: 204).isSuccess)
        #expect(!record(status: 500).isSuccess)
        let failure = NetworkRecord(duration: 0, method: "GET", url: "x", outcome: .failure(description: "boom"))
        #expect(!failure.isSuccess)
        #expect(failure.statusCode == nil)
    }
}
