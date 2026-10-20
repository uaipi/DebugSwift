import Foundation
import Testing
@testable import DebugSwiftCore

@Suite struct NetworkInjectionTests {
    private let url = URL(string: "https://api.example.com/v1/items")!

    private func request() -> URLRequest { URLRequest(url: url) }

    private func real(_ status: Int = 200, body: String = "real") -> @Sendable (URLRequest) async throws -> (Data, URLResponse) {
        { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["X-Real": "1"])!
            return (Data(body.utf8), response)
        }
    }

    @Test func noopDecisionRunsTheRealCall() async throws {
        let (data, response) = try await NetworkInjection.carryOut(
            NetworkInjectionDecision(), for: request(), url: url, perform: real()
        )
        #expect(String(decoding: data, as: UTF8.self) == "real")
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test func blockedAnswers403WithoutSending() async throws {
        let (data, response) = try await NetworkInjection.carryOut(
            NetworkInjectionDecision(isBlocked: true), for: request(), url: url,
            perform: { _ in Issue.record("must not send"); throw CancellationError() }
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 403)
        #expect(String(decoding: data, as: UTF8.self).contains("Blocked"))
    }

    @Test func httpErrorFailureReturnsThatStatus() async throws {
        let decision = NetworkInjectionDecision(failure: .init(kind: "httpError", statusCode: 503))
        let (data, response) = try await NetworkInjection.carryOut(decision, for: request(), url: url, perform: real())
        #expect((response as? HTTPURLResponse)?.statusCode == 503)
        #expect(String(decoding: data, as: UTF8.self).contains("\"injected\":true"))
    }

    @Test func networkFailureThrowsTheMatchingURLError() async {
        let decision = NetworkInjectionDecision(failure: .init(kind: "notConnectedToInternet"))
        do {
            _ = try await NetworkInjection.carryOut(decision, for: request(), url: url, perform: real())
            Issue.record("expected a throw")
        } catch {
            #expect((error as NSError).code == NSURLErrorNotConnectedToInternet)
        }
    }

    @Test func shortCircuitRewriteSkipsTheRealCall() async throws {
        let decision = NetworkInjectionDecision(rewrite: .init(statusCode: 418, body: "{\"teapot\":true}", shortCircuit: true))
        let (data, response) = try await NetworkInjection.carryOut(
            decision, for: request(), url: url,
            perform: { _ in Issue.record("must not send"); throw CancellationError() }
        )
        #expect((response as? HTTPURLResponse)?.statusCode == 418)
        #expect(String(decoding: data, as: UTF8.self) == "{\"teapot\":true}")
    }

    @Test func rewriteAfterSendKeepsHeadersAndSwapsBody() async throws {
        let decision = NetworkInjectionDecision(rewrite: .init(body: "patched", shortCircuit: false))
        let (data, response) = try await NetworkInjection.carryOut(decision, for: request(), url: url, perform: real(201))
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 201)
        #expect(http.value(forHTTPHeaderField: "X-Real") == "1")
        #expect(http.value(forHTTPHeaderField: "Content-Length") == "7")
        #expect(String(decoding: data, as: UTF8.self) == "patched")
    }

    @Test func delayWaitsBeforeSending() async throws {
        let started = Date()
        _ = try await NetworkInjection.carryOut(
            NetworkInjectionDecision(delaySeconds: 0.2), for: request(), url: url, perform: real()
        )
        #expect(Date().timeIntervalSince(started) >= 0.19)
    }

    @Test func applyUsesTheInstalledProviderAndPassesNilThrough() async throws {
        NetworkInjection.install { _, method in
            method == "GET" ? NetworkInjectionDecision(isBlocked: true) : nil
        }
        defer { NetworkInjection.install(nil) }
        let (_, blocked) = try await NetworkInjection.apply(to: request(), perform: real())
        #expect((blocked as? HTTPURLResponse)?.statusCode == 403)
        var post = request()
        post.httpMethod = "POST"
        let (_, passed) = try await NetworkInjection.apply(to: post, perform: real())
        #expect((passed as? HTTPURLResponse)?.statusCode == 200)
    }
}
