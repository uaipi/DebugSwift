import SwiftUI

/// StrictMode on the app: work the main thread should not do, such as disk access, and leaks of closeable objects.
struct DebugThreadCheckerView: View {
    @State var detail: DebugThreadDetail? = nil
    @State var failure = ""
    @State var status = ""

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            Section {
                Toggle("Detect violations", isOn: Binding(
                    get: { detail?.enabled ?? false },
                    set: { enabled in toggle(enabled) },
                ))
                Button("Trigger a test violation") {
                    status = DebugPerformanceDetail.act("app.perf.violation")
                    load()
                }
                Button("Clear", role: .destructive) {
                    _ = DebugSwiftAndroidRuntime.perform(featureID: "thread_checker", actionID: "clear")
                    load()
                }
                if !status.isEmpty {
                    Text(verbatim: status).font(.caption)
                }
            }
            if let detail {
                Section("Violations, newest first") {
                    if detail.violations.isEmpty {
                        Text(verbatim: "No StrictMode violations recorded.")
                            .foregroundColor(Color.secondary)
                    }
                    ForEach(0..<detail.violations.count, id: \.self) { index in
                        NavigationLink {
                            DebugTextDetailView(
                                title: "Violation",
                                text: detail.violations[index].title + "\n\n" + detail.violations[index].stack,
                            )
                        } label: {
                            Text(verbatim: detail.violations[index].title)
                                .font(.system(.footnote, design: .monospaced))
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Thread Checker")
        .task {
            // StrictMode reports on the main thread a moment after the work ran, so keep reading.
            while !Task.isCancelled {
                load()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func toggle(_ enabled: Bool) {
        guard enabled != (detail?.enabled ?? false) else { return }
        status = DebugSwiftAndroidRuntime.perform(featureID: "thread_checker", actionID: "toggle")
        load()
    }

    func load() {
        switch DebugPerformanceDetail.fetch("threads", as: DebugThreadDetail.self) {
        case let .success(value):
            detail = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}
