import SwiftUI

/// A circular progress ring with a centered label.
struct ProgressRing: View {
    let fraction: Double        // 0…1
    var lineWidth: CGFloat = 14
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: fraction)
            VStack(spacing: 2) {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("memorized")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A compact stat tile for the dashboard grid.
struct StatCard: View {
    let value: String
    let label: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A colored status pill.
struct StatusBadge: View {
    let status: MemorizationStatus

    var body: some View {
        Label(status.label, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.12), in: Capsule())
    }
}
