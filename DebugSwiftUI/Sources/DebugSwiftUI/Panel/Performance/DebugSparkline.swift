import SwiftUI

/// A small bar chart of recent readings, scaled to `ceiling` (or to the largest reading when nil).
/// Built from plain rectangles, which every platform lays out the same way.
struct DebugSparkline: View {
    let values: [Double]
    var ceiling: Double? = nil
    var color: Color = Color.accentColor
    let height = 56.0

    var scale: Double {
        max(ceiling ?? (values.max() ?? 1), 0.0001)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            ForEach(0..<values.count, id: \.self) { index in
                Rectangle()
                    .fill(color)
                    .frame(height: max(1.0, height * min(values[index] / scale, 1.0)))
            }
            Spacer(minLength: 0)
        }
        .frame(height: height, alignment: .bottom)
    }
}

/// A titled metric: its current value over its recent history.
struct DebugMetricCard: View {
    let title: String
    let value: String
    let history: DebugMetricHistory
    var ceiling: Double? = nil
    var color: Color = Color.accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: title)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                Spacer()
                Text(verbatim: value)
                    .font(.system(.body, design: .monospaced))
            }
            DebugSparkline(values: history.values, ceiling: ceiling, color: color)
        }
    }
}
