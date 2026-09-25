import Foundation

private struct NetworkInjectionSettingsPayload: Codable {
    var delay: Delay
    var failure: Failure
    var rewrite: Rewrite

    struct Delay: Codable {
        var isEnabled = false
        var fixedDelay: Double? = nil
        var minDelay = 1.0
        var maxDelay = 3.0
        var urlPatterns: [String] = []
        var httpMethods: [String] = []
    }

    struct Failure: Codable {
        var isEnabled = false
        var failureRate = 0.5
        var failureType = "timeout"
        var customStatusCodes = [400, 401, 403, 404, 500, 502, 503]
        var urlPatterns: [String] = []
        var httpMethods: [String] = []
        var customDomain = "DebugSwift.CustomNetworkError"
        var customCode = -1
        var customDescription = "Injected custom network error."
    }

    struct Rewrite: Codable {
        var isEnabled = false
        var rules: [Rule] = []
        var autoEnableOnRun = false
        var shortCircuitEnabled = true
        var multipleMatchEnabled = false
    }

    struct Rule: Codable {
        var id: String
        var urlPattern: String
        var responseBody: String
        var responseStatusCode: Int?
        var httpMethod: String?
        var isEnabled: Bool
        var matchType: String
    }
}

extension DebugSwift.Network {
    /// Returns the current delay, failure, and response rewrite settings as JSON for shared UI.
    public func networkInjectionSettingsJSON() -> String {
        let delay = NetworkInjectionManager.shared.getDelayConfig()
        let failure = NetworkInjectionManager.shared.getFailureConfig()
        let rewrite = NetworkInjectionManager.shared.getRewriteConfig()
        let failureValues = Self.failurePayloadValues(failure.failureType)
        let rules = rewrite.rules.enumerated().map { index, rule in
            NetworkInjectionSettingsPayload.Rule(
                id: "\(index):\(rule.urlPattern):\(rule.httpMethod?.rawValue ?? "ALL")",
                urlPattern: rule.urlPattern,
                responseBody: rule.responseBody,
                responseStatusCode: rule.responseStatusCode,
                httpMethod: rule.httpMethod?.rawValue,
                isEnabled: rule.isEnabled,
                matchType: rule.matchType.rawValue
            )
        }
        let payload = NetworkInjectionSettingsPayload(
            delay: .init(
                isEnabled: delay.isEnabled,
                fixedDelay: delay.fixedDelay,
                minDelay: delay.minDelay,
                maxDelay: delay.maxDelay,
                urlPatterns: delay.urlPatterns,
                httpMethods: delay.httpMethods
            ),
            failure: .init(
                isEnabled: failure.isEnabled,
                failureRate: failure.failureRate,
                failureType: failureValues.type,
                customStatusCodes: failure.customStatusCodes,
                urlPatterns: failure.urlPatterns,
                httpMethods: failure.httpMethods,
                customDomain: failureValues.domain,
                customCode: failureValues.code,
                customDescription: failureValues.description
            ),
            rewrite: .init(
                isEnabled: rewrite.isEnabled,
                rules: rules,
                autoEnableOnRun: NetworkInjectionManager.shared.shouldAutoEnableRewriteOnRun(),
                shortCircuitEnabled: NetworkInjectionManager.shared.isRewriteShortCircuitEnabled(),
                multipleMatchEnabled: NetworkInjectionManager.shared.isRewriteMultipleMatchEnabled()
            )
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    /// Applies settings produced by the shared SwiftUI form.
    @discardableResult
    public func applyNetworkInjectionSettingsJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(NetworkInjectionSettingsPayload.self, from: data) else {
            return false
        }

        let minimumDelay = min(max(payload.delay.minDelay, 0), 60)
        let maximumDelay = min(max(payload.delay.maxDelay, minimumDelay), 60)
        let delay = RequestDelayConfig(
            isEnabled: payload.delay.isEnabled,
            fixedDelay: payload.delay.fixedDelay.map { min(max($0, 0), 60) },
            minDelay: minimumDelay,
            maxDelay: maximumDelay,
            urlPatterns: payload.delay.urlPatterns,
            httpMethods: payload.delay.httpMethods
        )
        var failure = NetworkFailureConfig(
            isEnabled: payload.failure.isEnabled,
            failureRate: payload.failure.failureRate,
            failureType: Self.failureType(from: payload.failure),
            urlPatterns: payload.failure.urlPatterns,
            httpMethods: payload.failure.httpMethods,
            customStatusCodes: payload.failure.customStatusCodes
        )
        failure.customStatusCodes = payload.failure.customStatusCodes.filter { (400...599).contains($0) }
        let rules = payload.rewrite.rules.map { rule in
            ResponseBodyRewriteRule(
                urlPattern: rule.urlPattern,
                responseBody: rule.responseBody,
                responseStatusCode: rule.responseStatusCode.flatMap { (100...599).contains($0) ? $0 : nil },
                httpMethod: rule.httpMethod.flatMap(HTTPMethod.init(rawValue:)),
                isEnabled: rule.isEnabled,
                matchType: rule.matchType == "wildcard" ? .wildcard : .exact
            )
        }

        NetworkInjectionManager.shared.setDelayConfig(delay)
        NetworkInjectionManager.shared.setFailureConfig(failure)
        NetworkInjectionManager.shared.setRewriteConfig(.init(isEnabled: payload.rewrite.isEnabled, rules: rules))
        NetworkInjectionManager.shared.setRewriteAutoEnableOnRun(payload.rewrite.autoEnableOnRun)
        NetworkInjectionManager.shared.setRewriteShortCircuitEnabled(payload.rewrite.shortCircuitEnabled)
        NetworkInjectionManager.shared.setRewriteMultipleMatchEnabled(payload.rewrite.multipleMatchEnabled)
        return true
    }

    /// Exports response modifier rules in the CSV format used by the iOS settings screen.
    public func responseRewriteRulesCSV() -> String {
        RewriteRulesCSV.export(rules: NetworkInjectionManager.shared.getRewriteConfig().rules)
    }

    /// Imports response modifier rules from CSV, updating existing URL and method pairs.
    public func importResponseRewriteRulesCSV(_ csv: String) -> String {
        do {
            let importedRules = try RewriteRulesCSV.parse(csv)
            var config = NetworkInjectionManager.shared.getRewriteConfig()
            var created = 0
            var updated = 0
            for importedRule in importedRules {
                if let index = config.rules.firstIndex(where: {
                    $0.urlPattern == importedRule.urlPattern && $0.httpMethod == importedRule.httpMethod
                }) {
                    config.rules[index].responseBody = importedRule.responseBody
                    config.rules[index].responseStatusCode = importedRule.responseStatusCode
                    config.rules[index].httpMethod = importedRule.httpMethod
                    updated += 1
                } else {
                    config.rules.append(importedRule)
                    created += 1
                }
            }
            NetworkInjectionManager.shared.setRewriteConfig(config)
            return "Imported \(created) new rule(s) and updated \(updated) existing rule(s)."
        } catch {
            return error.localizedDescription
        }
    }

    /// Opens the platform share sheet for the exported response modifier CSV.
    @MainActor
    public func shareResponseRewriteRulesCSV() {
        FileSharingManager.generateFileAndShare(text: responseRewriteRulesCSV(), fileName: "response-modifier-rules")
    }

    private static func failurePayloadValues(_ type: NetworkFailureConfig.FailureType) -> (type: String, domain: String, code: Int, description: String) {
        switch type {
        case .timeout: ("timeout", "", 0, "")
        case .connectionLost: ("connectionLost", "", 0, "")
        case .notConnectedToInternet: ("notConnectedToInternet", "", 0, "")
        case .cannotFindHost: ("cannotFindHost", "", 0, "")
        case .dnsLookupFailed: ("dnsLookupFailed", "", 0, "")
        case .httpError: ("httpError", "", 0, "")
        case .sslError: ("sslError", "", 0, "")
        case .cancelled: ("cancelled", "", 0, "")
        case .custom(let domain, let code, let description): ("custom", domain, code, description)
        }
    }

    private static func failureType(from payload: NetworkInjectionSettingsPayload.Failure) -> NetworkFailureConfig.FailureType {
        switch payload.failureType {
        case "connectionLost": .connectionLost
        case "notConnectedToInternet": .notConnectedToInternet
        case "cannotFindHost": .cannotFindHost
        case "dnsLookupFailed": .dnsLookupFailed
        case "httpError": .httpError(statusCode: nil)
        case "sslError": .sslError
        case "cancelled": .cancelled
        case "custom": .custom(domain: payload.customDomain, code: payload.customCode, description: payload.customDescription)
        default: .timeout
        }
    }
}
