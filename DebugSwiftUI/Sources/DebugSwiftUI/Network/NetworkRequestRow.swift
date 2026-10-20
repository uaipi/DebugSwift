import DebugSwiftCore
import SwiftUI

struct NetworkRequestRow: View {
    let request: NetworkRecordSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(verbatim: request.method).font(.caption)
                Text(verbatim: request.statusTitle)
                    .font(.headline)
                    .foregroundStyle(request.status.color)
                Spacer()
                Text(verbatim: "\(request.durationMilliseconds) ms").font(.caption)
            }
            Text(verbatim: request.host)
            Text(verbatim: request.path).font(.caption).lineLimit(1)
        }
        .accessibilityLabel(Text(verbatim: "\(request.method) \(request.statusTitle) \(request.host)\(request.path), \(request.durationMilliseconds) ms"))
    }
}

extension NetworkRecordSummary.Status {
    var color: Color {
        switch self {
        case .success: .green
        case .redirect: .orange
        case .error, .failed: .red
        }
    }
}
