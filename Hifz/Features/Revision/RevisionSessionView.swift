import SwiftUI
import SwiftData

/// Steps the user through the due queue one unit at a time.
struct RevisionSessionView: View {
    let mode: RevisionMode
    let granularity: Granularity

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allProgress: [MemorizationProgress]

    @State private var queue: [MemorizationProgress] = []
    @State private var index = 0
    @State private var revealed = false
    @State private var reviewedCount = 0

    var body: some View {
        VStack(spacing: 20) {
            if queue.isEmpty {
                completion
            } else if index < queue.count {
                let progress = queue[index]
                let unit = QuranData.unit(for: progress)

                ProgressView(value: Double(index), total: Double(queue.count))
                    .padding(.horizontal)
                Text("\(index + 1) of \(queue.count)")
                    .font(.caption).foregroundStyle(.secondary)

                Spacer()
                ReviewCardView(unit: unit, progress: progress, revealed: $revealed)
                    .padding(.horizontal)
                Spacer()

                if revealed {
                    RatingButtons { rating in rate(progress, rating) }
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else {
                completion
            }
        }
        .padding(.vertical)
        .navigationTitle("Revision")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: buildQueue)
    }

    private var completion: some View {
        ContentUnavailableView {
            Label(reviewedCount > 0 ? "Session complete" : "Nothing to revise", systemImage: "checkmark.seal.fill")
        } description: {
            Text(reviewedCount > 0
                 ? "You reviewed \(reviewedCount) \(granularity.shortLabel.lowercased())\(reviewedCount == 1 ? "" : "s"). Great work!"
                 : "You're all caught up for now.")
        } actions: {
            Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
        }
    }

    private func buildQueue() {
        guard queue.isEmpty, index == 0 else { return }
        queue = RevisionScheduler.dueItems(allProgress, mode: mode, granularity: granularity)
    }

    private func rate(_ progress: MemorizationProgress, _ rating: ReviewRating) {
        ProgressManager.review(progress, rating: rating, in: context)
        try? context.save()
        reviewedCount += 1
        withAnimation {
            revealed = false
            index += 1
        }
    }
}
