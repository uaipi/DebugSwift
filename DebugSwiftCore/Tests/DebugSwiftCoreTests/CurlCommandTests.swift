import Testing
@testable import DebugSwiftCore

struct CurlCommandTests {
    private func capture(url: String, headers: [String: String] = [:], body: String? = nil) -> HARCapture {
        HARCapture(
            request: HARRequest(method: "POST", url: url, headers: headers, body: body),
            response: HARResponse(status: 200, headers: [:])
        )
    }

    @Test func escapesSingleQuotesInUrlHeadersAndBody() {
        let command = HAREncoder.curlCommand(for: capture(
            url: "https://example.test/?q=it's",
            headers: ["X-Name": "O'Brien"],
            body: #"{"note":"don't"}"#
        ))
        #expect(command == #"curl -X POST 'https://example.test/?q=it'\''s' -H 'X-Name: O'\''Brien' -d '{"note":"don'\''t"}'"#)
    }

    @Test func listsHeadersInAlphabeticalOrder() {
        let command = HAREncoder.curlCommand(for: capture(
            url: "https://example.test",
            headers: ["Zeta": "1", "Accept": "2", "Middle": "3"]
        ))
        #expect(command == "curl -X POST 'https://example.test' -H 'Accept: 2' -H 'Middle: 3' -H 'Zeta: 1'")
    }
}
