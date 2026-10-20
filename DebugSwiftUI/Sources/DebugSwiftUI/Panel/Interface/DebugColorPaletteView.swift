import SwiftUI

struct DebugPaletteColor: Decodable, Identifiable {
    let hex: String
    let red: Int
    let green: Int
    let blue: Int
    let percent: Double
    var id: String { hex }

    var color: Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

struct DebugPaletteResult: Decodable {
    let colors: [DebugPaletteColor]
    let source: String
}

/// The dominant colors of the app's window. Tap a color to copy its hex value.
struct DebugColorPaletteView: View {
    @State var result: DebugPaletteResult? = nil
    @State var failure = ""
    @State var status = ""

    var body: some View {
        List {
            Section {
                Button("Capture the screen") { capture() }
                if !status.isEmpty {
                    Text(verbatim: status).font(.caption)
                }
            }
            if !failure.isEmpty {
                Text(verbatim: failure).foregroundColor(Color.red)
            }
            if let result {
                Section("Colors by share of the screen (\(result.source))") {
                    ForEach(result.colors) { color in
                        Button {
                            DebugClipboard.copy(color.hex)
                            status = "Copied \(color.hex)."
                        } label: {
                            DebugPaletteRow(color: color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Color Palette")
        .onAppear { capture() }
    }

    func capture() {
        switch DebugResourceClient.fetch("app.ui.palette", as: DebugPaletteResult.self) {
        case let .success(value):
            result = value
            failure = ""
        case let .failure(error):
            failure = error.message
        }
    }
}

struct DebugPaletteRow: View {
    let color: DebugPaletteColor

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.color)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: color.hex)
                    .font(.system(.body, design: .monospaced))
                Text(verbatim: "rgb(\(color.red), \(color.green), \(color.blue))")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
            Spacer()
            Text(verbatim: String(format: "%.1f%%", color.percent))
                .foregroundColor(Color.secondary)
        }
    }
}
