import SwiftUI

/// The four SM-2 rating buttons.
struct RatingButtons: View {
    var onRate: (ReviewRating) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ReviewRating.allCases) { rating in
                Button {
                    onRate(rating)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: rating.systemImage).font(.title3)
                        Text(rating.label).font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(rating.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(rating.color)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A flip card showing a unit's name and revealing recall details.
struct ReviewCardView: View {
    let unit: TrackUnit
    let progress: MemorizationProgress
    @Binding var revealed: Bool

    var body: some View {
        VStack(spacing: 16) {
            if let arabic = unit.arabic {
                Text(arabic)
                    .font(.system(size: 52, weight: .bold))
                    .environment(\.layoutDirection, .rightToLeft)
            }
            Text(unit.title).font(.title2.weight(.semibold))
            Text(unit.subtitle).font(.subheadline).foregroundStyle(.secondary)

            if revealed {
                Divider().padding(.vertical, 4)
                VStack(spacing: 6) {
                    Text("Recite it from memory, then rate your recall.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Label("\(progress.repetitions) reviews", systemImage: "arrow.triangle.2.circlepath")
                        Label(progress.intervalDays == 0 ? "New" : "\(progress.intervalDays)d", systemImage: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else {
                Text("Tap to reveal")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 24))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring) { revealed = true } }
    }
}
