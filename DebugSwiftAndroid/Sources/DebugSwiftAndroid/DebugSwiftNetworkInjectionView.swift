import Foundation
import SwiftUI
#if os(iOS)
import UniformTypeIdentifiers
#endif

struct DebugSwiftNetworkInjectionSettings: Codable {
    var delay = Delay()
    var failure = Failure()
    var rewrite = Rewrite()

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

    struct Rule: Codable, Identifiable {
        var id: String
        var urlPattern: String
        var responseBody: String
        var responseStatusCode: Int?
        var httpMethod: String?
        var isEnabled: Bool
        var matchType: String
    }
}

private struct DebugSwiftNetworkInjectionRuleDraft: Identifiable {
    var id: String
    var urlPattern: String
    var responseBody: String
    var responseStatusCode = ""
    var httpMethod = ""
    var isEnabled = true
    var matchType = "exact"

    init(rule: DebugSwiftNetworkInjectionSettings.Rule? = nil) {
        id = rule?.id ?? UUID().uuidString
        urlPattern = rule?.urlPattern ?? ""
        responseBody = rule?.responseBody ?? "{}"
        responseStatusCode = rule?.responseStatusCode.map { String($0) } ?? ""
        httpMethod = rule?.httpMethod ?? ""
        isEnabled = rule?.isEnabled ?? true
        matchType = rule?.matchType ?? "exact"
    }

    var rule: DebugSwiftNetworkInjectionSettings.Rule {
        .init(
            id: id,
            urlPattern: urlPattern.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            responseBody: responseBody,
            responseStatusCode: parsedStatusCode(responseStatusCode),
            httpMethod: httpMethod.isEmpty ? nil : httpMethod,
            isEnabled: isEnabled,
            matchType: urlPattern.contains("*") || urlPattern.contains("?") ? "wildcard" : "exact"
        )
    }

    var isValid: Bool {
        if urlPattern.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty { return false }
        if responseStatusCode.isEmpty { return true }
        if let _ = parsedStatusCode(responseStatusCode) { return true }
        return false
    }

    private func parsedStatusCode(_ text: String) -> Int? {
        guard let value = Int(text), (100...599).contains(value) else { return nil }
        return value
    }
}

struct DebugSwiftNetworkInjectionView: View {
    @State private var settings = DebugSwiftNetworkInjectionSettings()
    @State private var ruleDraft: DebugSwiftNetworkInjectionRuleDraft?
    @State private var editingRuleID: String?
    @State private var statusMessage = ""
    @State private var showingResetConfirmation = false
    @State private var showingCSVImporter = false
    @State private var ruleSearchText = ""

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    private let failureTypes: [(String, String)] = [
        ("timeout", "Timeout"),
        ("connectionLost", "Connection Lost"),
        ("notConnectedToInternet", "No Internet"),
        ("cannotFindHost", "Cannot Find Host"),
        ("dnsLookupFailed", "DNS Lookup Failed"),
        ("httpError", "HTTP Error"),
        ("sslError", "SSL Error"),
        ("cancelled", "Cancelled"),
        ("custom", "Custom Error")
    ]

    var body: some View {
        Form {
            delaySection
            failureSection
            rewriteSection

            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Network Injection")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") { applySettings() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Reset") { showingResetConfirmation = true }
            }
        }
        .onAppear(perform: loadSettings)
        .sheet(item: $ruleDraft) { draft in
            DebugSwiftNetworkInjectionRuleEditor(draft: draft) { updated in
                if let index = settings.rewrite.rules.firstIndex(where: { $0.id == editingRuleID }) {
                    settings.rewrite.rules[index] = updated.rule
                } else {
                    settings.rewrite.rules.append(updated.rule)
                }
                editingRuleID = nil
            }
        }
        .confirmationDialog("Reset network injection settings?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset All Settings", role: .destructive) {
                settings = DebugSwiftNetworkInjectionSettings()
                settings.rewrite.rules = []
                applySettings()
            }
        }
    }

    private var delaySection: some View {
        Section("Request delay injection") {
            Toggle("Enable delay", isOn: $settings.delay.isEnabled)
            Picker("Delay type", selection: delayModeBinding) {
                Text("Fixed").tag("fixed")
                Text("Random range").tag("random")
            }
            if settings.delay.fixedDelay != nil {
                TextField("Delay in seconds", text: fixedDelayBinding)
            } else {
                TextField("Minimum seconds", text: minDelayBinding)
                TextField("Maximum seconds", text: maxDelayBinding)
            }
            TextField("URL patterns, comma separated", text: patternsBinding($settings.delay.urlPatterns))
            methodToggles(title: "HTTP methods", selected: $settings.delay.httpMethods)
        }
    }

    private var failureSection: some View {
        Section("Network failure injection") {
            Toggle("Enable failure", isOn: $settings.failure.isEnabled)
            Picker("Failure type", selection: $settings.failure.failureType) {
                ForEach(failureTypes, id: \.0) { value, label in
                    Text(label).tag(value)
                }
            }
            VStack(alignment: .leading) {
                Text("Failure rate: \(Int((settings.failure.failureRate * 100).rounded()))%")
                Slider(value: $settings.failure.failureRate, in: 0...1, step: 0.05)
            }
            if settings.failure.failureType == "httpError" {
                TextField("HTTP status codes, comma separated", text: statusCodesBinding)
            }
            TextField("URL patterns, comma separated", text: patternsBinding($settings.failure.urlPatterns))
            methodToggles(title: "HTTP methods", selected: $settings.failure.httpMethods)
            if settings.failure.failureType == "custom" {
                TextField("Error domain", text: $settings.failure.customDomain)
                TextField("Error code", text: customCodeBinding)
                TextField("Error description", text: $settings.failure.customDescription)
            }
        }
    }

    private var rewriteSection: some View {
        Section {
            Toggle("Enable response modifier", isOn: $settings.rewrite.isEnabled)
            Toggle("Enable all rules", isOn: allRulesBinding)
                .disabled(settings.rewrite.rules.isEmpty)
            Toggle("Auto-enable on app start", isOn: $settings.rewrite.autoEnableOnRun)
            Toggle("Return mocked response without network", isOn: $settings.rewrite.shortCircuitEnabled)
            Toggle("Choose when multiple rules match", isOn: $settings.rewrite.multipleMatchEnabled)

            if settings.rewrite.rules.isEmpty {
                Text("No response rules. Add a URL pattern and replacement body to mock or rewrite matching responses.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            ForEach(settings.rewrite.rules) { rule in
                if ruleSearchText.isEmpty ||
                    rule.urlPattern.lowercased().contains(ruleSearchText.lowercased()) ||
                    (rule.httpMethod ?? "").lowercased().contains(ruleSearchText.lowercased()) {
                    if let index = settings.rewrite.rules.firstIndex(where: { $0.id == rule.id }) {
                        rewriteRuleRow(at: index)
                    }
                }
            }
            Button {
                editingRuleID = nil
                ruleDraft = DebugSwiftNetworkInjectionRuleDraft()
            } label: {
                Label("Add response rule", systemImage: "plus")
            }
            TextField("Search API rules", text: $ruleSearchText)
            HStack {
                Button("Import CSV") { showingCSVImporter = true }
                    .sheet(isPresented: $showingCSVImporter) {
                        DebugSwiftNetworkInjectionCSVImporter { csv in
                            statusMessage = DebugSwiftAndroidRuntime.importNetworkInjectionRulesCSV(csv)
                            loadSettings()
                        }
                    }
                Spacer()
                Button("Export CSV") {
                    statusMessage = DebugSwiftAndroidRuntime.exportNetworkInjectionRulesCSV()
                }
            }
            if settings.rewrite.rules.contains(where: { $0.urlPattern == "*" }) {
                Text("A rule matching * can replace every response. Keep broad patterns near the end.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Response modifier")
        } footer: {
            Text("Rules are checked in order. The first matching rule is used unless multiple-match selection is enabled.")
        }
    }

    private func rewriteRuleRow(at index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                editRule(at: index)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(settings.rewrite.rules[index].urlPattern)
                        .lineLimit(2)
                    Text("\(settings.rewrite.rules[index].httpMethod ?? "All methods") · \(settings.rewrite.rules[index].responseStatusCode.map { String($0) } ?? "200")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)
            Button("↑") { moveRule(at: index, offset: -1) }
                .disabled(index == 0)
                .accessibilityLabel("Move rule up")
            Button("↓") { moveRule(at: index, offset: 1) }
                .disabled(index == settings.rewrite.rules.count - 1)
                .accessibilityLabel("Move rule down")
            Toggle("Enabled", isOn: ruleEnabledBinding(at: index))
                .labelsHidden()
            Button(role: .destructive) {
                settings.rewrite.rules.remove(at: index)
            } label: {
                Image(systemName: "trash")
            }
            .accessibilityLabel("Delete rule")
        }
        .padding(.vertical, 2)
    }

    private func methodToggles(title: String, selected: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline)
            ForEach(methods, id: \.self) { method in
                Toggle(method, isOn: methodBinding(method, selected: selected))
            }
            Text("Leave every method off to match all methods.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var delayModeBinding: Binding<String> {
        Binding(
            get: { settings.delay.fixedDelay == nil ? "random" : "fixed" },
            set: { settings.delay.fixedDelay = $0 == "fixed" ? max(settings.delay.minDelay, 0.1) : nil }
        )
    }

    private var fixedDelayBinding: Binding<String> {
        Binding(
            get: { "\(settings.delay.fixedDelay ?? 1.0)" },
            set: { if let value = Double($0) { settings.delay.fixedDelay = value } }
        )
    }

    private var minDelayBinding: Binding<String> {
        Binding(
            get: { "\(settings.delay.minDelay)" },
            set: { if let value = Double($0) { settings.delay.minDelay = value } }
        )
    }

    private var maxDelayBinding: Binding<String> {
        Binding(
            get: { "\(settings.delay.maxDelay)" },
            set: { if let value = Double($0) { settings.delay.maxDelay = value } }
        )
    }

    private var customCodeBinding: Binding<String> {
        Binding(
            get: { "\(settings.failure.customCode)" },
            set: { if let value = Int($0) { settings.failure.customCode = value } }
        )
    }

    private var allRulesBinding: Binding<Bool> {
        Binding(
            get: { !settings.rewrite.rules.isEmpty && settings.rewrite.rules.allSatisfy(\.isEnabled) },
            set: { enabled in
                for index in settings.rewrite.rules.indices {
                    settings.rewrite.rules[index].isEnabled = enabled
                }
            }
        )
    }

    private var statusCodesBinding: Binding<String> {
        Binding(
            get: { settings.failure.customStatusCodes.map { String($0) }.joined(separator: ", ") },
            set: { settings.failure.customStatusCodes = $0.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: CharacterSet.whitespaces)) } }
        )
    }

    private func patternsBinding(_ selected: Binding<[String]>) -> Binding<String> {
        Binding(
            get: { selected.wrappedValue.joined(separator: ", ") },
            set: { value in
                selected.wrappedValue = value.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
        )
    }

    private func methodBinding(_ method: String, selected: Binding<[String]>) -> Binding<Bool> {
        Binding(
            get: { selected.wrappedValue.contains(method) },
            set: { enabled in
                if enabled, !selected.wrappedValue.contains(method) {
                    selected.wrappedValue.append(method)
                } else if !enabled {
                    selected.wrappedValue.removeAll { $0 == method }
                }
            }
        )
    }

    private func ruleEnabledBinding(at index: Int) -> Binding<Bool> {
        Binding(
            get: { settings.rewrite.rules.indices.contains(index) && settings.rewrite.rules[index].isEnabled },
            set: { enabled in
                guard settings.rewrite.rules.indices.contains(index) else { return }
                settings.rewrite.rules[index].isEnabled = enabled
            }
        )
    }

    private func editRule(at index: Int) {
        guard settings.rewrite.rules.indices.contains(index) else { return }
        let rule = settings.rewrite.rules[index]
        editingRuleID = rule.id
        ruleDraft = DebugSwiftNetworkInjectionRuleDraft(rule: rule)
    }

    private func moveRule(at index: Int, offset: Int) {
        let destination = index + offset
        guard settings.rewrite.rules.indices.contains(index), settings.rewrite.rules.indices.contains(destination) else { return }
        let rule = settings.rewrite.rules.remove(at: index)
        settings.rewrite.rules.insert(rule, at: destination)
    }

    private func loadSettings() {
        let json = DebugSwiftAndroidRuntime.networkInjectionSettingsJSON()
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(DebugSwiftNetworkInjectionSettings.self, from: data) else {
            statusMessage = "Could not load network injection settings."
            return
        }
        settings = decoded
    }

    private func applySettings() {
        guard let data = try? JSONEncoder().encode(settings),
              let json = String(data: data, encoding: .utf8) else {
            statusMessage = "Could not encode settings."
            return
        }
        statusMessage = DebugSwiftAndroidRuntime.applyNetworkInjectionSettingsJSON(json)
        loadSettings()
    }
}

private struct DebugSwiftNetworkInjectionRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: DebugSwiftNetworkInjectionRuleDraft
    let onSave: (DebugSwiftNetworkInjectionRuleDraft) -> Void

    private let methods = ["", "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Match") {
                    TextField("URL pattern", text: $draft.urlPattern)
                    Picker("HTTP method", selection: $draft.httpMethod) {
                        ForEach(methods, id: \.self) { method in
                            Text(method.isEmpty ? "All methods" : method).tag(method)
                        }
                    }
                    Toggle("Rule enabled", isOn: $draft.isEnabled)
                }
                Section("Mock response") {
                    TextField("Status code (optional)", text: $draft.responseStatusCode)
                    TextEditor(text: $draft.responseBody)
                        .frame(minHeight: 180)
                    Text("If status is empty, the mock response uses HTTP 200. The body is returned as UTF-8 JSON.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(draft.urlPattern.isEmpty ? "New rule" : "Response rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
    }
}

private struct DebugSwiftNetworkInjectionCSVImporter: View {
    @Environment(\.dismiss) private var dismiss
    @State private var csvText = ""
    @State private var showingFileImporter = false
    @State private var importError = ""
    let onImport: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Response modifier CSV") {
#if os(iOS)
                    Button("Choose CSV file") { showingFileImporter = true }
                        .fileImporter(
                            isPresented: $showingFileImporter,
                            allowedContentTypes: [.commaSeparatedText, .plainText]
                        ) { result in
                            switch result {
                            case .success(let url):
                                let hasAccess = url.startAccessingSecurityScopedResource()
                                defer {
                                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                                }
                                if let content = try? String(contentsOf: url, encoding: .utf8) {
                                    csvText = content
                                    importError = ""
                                } else {
                                    importError = "Could not read the selected file as UTF-8 CSV."
                                }
                            case .failure(let error):
                                importError = error.localizedDescription
                            }
                        }
#else
                    Text("Paste the CSV file contents below to import response rules.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
#endif
                    Text("Paste a CSV file with the columns url_pattern,response_status_code,response_body,http_method.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    if !importError.isEmpty {
                        Text(importError).foregroundColor(.red)
                    }
                    TextEditor(text: $csvText)
                        .frame(minHeight: 260)
                }
            }
            .navigationTitle("Import rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(csvText)
                        dismiss()
                    }
                    .disabled(csvText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
