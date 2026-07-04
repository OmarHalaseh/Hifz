import Foundation
import SwiftData

/// One recorded review event. Powers statistics, streaks, and the activity heatmap.
@Model
final class ReviewLog {
    var date: Date
    var unitKey: String
    var rating: ReviewRating
    var intervalAfter: Int

    init(date: Date = .now, unitKey: String, rating: ReviewRating, intervalAfter: Int) {
        self.date = date
        self.unitKey = unitKey
        self.rating = rating
        self.intervalAfter = intervalAfter
    }
}
