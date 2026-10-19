import SwiftUI

/// Renders the text snapshot a Kotlin tool returns for one feature.
struct AndroidToolSnapshotView: View {
    let featureID: String
    let title: String
    @State var text = ""

    var body: some View {
        ScrollView {
            Text(verbatim: text)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .navigationTitle(title)
        .task { text = DebugAndroidTools.snapshot(featureID) }
    }
}

#if !os(Android)
#Preview("Android tool snapshot") {
    NavigationStack {
        AndroidToolSnapshotView(featureID: "device_info", title: "Device info", text: "App 1.0\nAndroid 15")
    }
}
#endif
