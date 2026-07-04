import SwiftUI
import SwiftData

struct RevisionQueueView: View {
    @Environment(\.modelContext) private var context
    @Query private var allProgress: [MemorizationProgress]
    @Query private var settingsList: [AppSettings]

    private var settings: AppSettings { settingsList.first ?? AppSettings.current(in: context) }

    private var dueItems: [MemorizationProgress] {
        RevisionScheduler.dueItems(allProgress, mode: settings.revisionMode, granularity: settings.granularity)
    }

    var body: some View {
        NavigationStack {
            Group {
                if dueItems.isEmpty {
                    ContentUnavailableView {
                        Label("All caught up", systemImage: "checkmark.seal.fill")
                    } description: {
                        Text(emptyMessage)
                    }
                } else {
                    List {
                        Section {
                            NavigationLink {
                                RevisionSessionView(mode: settings.revisionMode, granularity: settings.granularity)
                            } label: {
                                Label("Start revision session", systemImage: "play.fill")
                                    .font(.headline)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        Section("\(dueItems.count) due · \(settings.revisionMode.label)") {
                            ForEach(dueItems) { p in
                                let unit = QuranData.unit(for: p)
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(unit.title).font(.body.weight(.medium))
                                        Text(dueSubtitle(p)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let arabic = unit.arabic {
                                        Text(arabic).font(.title3.weight(.semibold))
                                            .environment(\.layoutDirection, .rightToLeft)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Revise")
        }
    }

    private var emptyMessage: String {
        switch settings.revisionMode {
        case .spacedRepetition: return "No surahs are due for review right now. Come back later!"
        case .lastReviewed, .selfRated: return "Mark some surahs as memorized to build your revision list."
        }
    }

    private func dueSubtitle(_ p: MemorizationProgress) -> String {
        switch settings.revisionMode {
        case .spacedRepetition:
            if let due = p.dueDate, due > Calendar.current.startOfDay(for: .now) {
                return "Due \(due.formatted(.relative(presentation: .named)))"
            }
            return "Due now · \(p.repetitions) reviews"
        case .lastReviewed:
            if let last = p.lastReviewedAt {
                return "Last reviewed \(last.formatted(.relative(presentation: .named)))"
            }
            return "Never reviewed"
        case .selfRated:
            return "Strength \(Int(p.strength * 100))%"
        }
    }
}
