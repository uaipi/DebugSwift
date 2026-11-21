#if os(iOS)
@_spi(DebugSwiftUI) import DebugSwift
import SwiftUI
import UIKit

/// An empty native view inside the shared panel. Screen captures look for it to leave the panel out
/// when it is presented in the app's own window, as a `.sheet` is.
struct DebugPanelMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        SharedPanelData.makePanelMarker()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
