import SwiftUI

/// The switch for the floating debug button, shown in the panel on Android.
struct DebugFloatingButtonToggle: View {
    @State var isOn = false

    var body: some View {
        Toggle("Floating debug button", isOn: Binding(
            get: { isOn },
            set: { enabled in
                isOn = enabled
                DebugFloatingButton.setEnabled(enabled)
            },
        ))
        .onAppear { isOn = DebugFloatingButton.isEnabled }
    }
}
