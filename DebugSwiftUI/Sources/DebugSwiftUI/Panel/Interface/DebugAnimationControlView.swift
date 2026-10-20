import SwiftUI

struct DebugAnimationState: Decodable {
    let window: Double
    let transition: Double
    let animator: Double
    let canWriteSystem: Bool
    let packageName: String
    let message: String?
}

/// The system animation scales, with a quick way to slow animations down to inspect them.
struct DebugAnimationControlView: View {
    @State var state: DebugAnimationState? = nil
    @State var failure = ""
    @State var status = ""

    let speeds: [Double] = [1, 2, 5, 10]

    var body: some View {
        List {
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let state {
                Section("Current scales") {
                    LabeledContent("Window") { Text(verbatim: scaleText(state.window)) }
                    LabeledContent("Transition") { Text(verbatim: scaleText(state.transition)) }
                    LabeledContent("Animator") { Text(verbatim: scaleText(state.animator)) }
                }
                Section("Slow animations to") {
                    ForEach(speeds, id: \.self) { speed in
                        Button(speed == 1 ? "Normal speed" : scaleText(speed) + " slower") { set(speed) }
                    }
                }
                if !state.canWriteSystem {
                    Section("To change the system scales") {
                        Text(verbatim: "Run: adb shell pm grant \(state.packageName) android.permission.WRITE_SECURE_SETTINGS")
                            .font(.system(.footnote, design: .monospaced))
                        Button("Open Developer options") {
                            status = DebugSwiftAndroidRuntime.perform(featureID: "animation_control", actionID: "open_animation_settings")
                        }
                    }
                }
            }
            if !status.isEmpty {
                Section("Status") {
                    Text(verbatim: status).font(.caption)
                }
            }
        }
        .navigationTitle("Animation Settings")
        .onAppear { load() }
    }

    func scaleText(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))×" : String(format: "%.1f×", value)
    }

    func load() {
        switch DebugResourceClient.fetch("app.animation.get", as: DebugAnimationState.self) {
        case let .success(value):
            state = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }

    func set(_ speed: Double) {
        switch DebugResourceClient.fetch("app.animation.set", ["scale": String(speed)], as: DebugAnimationState.self) {
        case let .success(value):
            state = value
            status = value.message ?? ""
        case let .failure(error):
            status = error.message
        }
    }
}
