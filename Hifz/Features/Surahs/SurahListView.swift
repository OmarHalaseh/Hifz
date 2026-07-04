import SwiftUI
import SwiftData

struct SurahListView: View {
    @Environment(\.modelContext) private var context
    @Query private var allProgress: [MemorizationProgress]
    @Query private var settingsList: [AppSettings]

    @State private var search = ""
    @State private var statusFilter: MemorizationStatus? = nil
    @State private var showAddAyahRange = false

    private var settings: AppSettings { settingsList.first ?? AppSettings.current(in: context) }
    private var granularity: Granularity { settings.granularity }

    private var progressByKey: [String: MemorizationProgress] {
        Dictionary(allProgress.map { ($0.unitKey, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var units: [TrackUnit] {
        switch granularity {
        case .ayahRange:
            return allProgress
                .filter { $0.granularity == .ayahRange }
                .sorted { ($0.surahNumber, $0.ayahFrom) < ($1.surahNumber, $1.ayahFrom) }
                .map { QuranData.ayahUnit(surah: $0.surahNumber, from: $0.ayahFrom, to: $0.ayahTo) }
        default:
            return QuranData.units(for: granularity)
        }
    }

    private var filteredUnits: [TrackUnit] {
        units.filter { unit in
            let status = progressByKey[unit.key]?.status ?? .notStarted
            let matchesStatus = statusFilter == nil || status == statusFilter
            let matchesSearch = search.isEmpty
                || unit.title.localizedCaseInsensitiveContains(search)
                || unit.subtitle.localizedCaseInsensitiveContains(search)
                || (unit.arabic?.contains(search) ?? false)
            return matchesStatus && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if granularity == .ayahRange && units.isEmpty {
                    emptyAyahState
                } else {
                    list
                }
            }
            .navigationTitle(navTitle)
            .searchable(text: $search, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                if granularity == .ayahRange {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAddAyahRange = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .sheet(isPresented: $showAddAyahRange) {
                AddAyahRangeView()
            }
        }
    }

    private var navTitle: String {
        switch granularity {
        case .surah: return "Surahs"
        case .page: return "Pages"
        case .juz: return "Ajza"
        case .ayahRange: return "Ayah Ranges"
        }
    }

    private var list: some View {
        List(filteredUnits) { unit in
            NavigationLink {
                SurahDetailView(unit: unit)
            } label: {
                UnitRow(unit: unit, status: progressByKey[unit.key]?.status ?? .notStarted)
            }
        }
        .listStyle(.plain)
    }

    private var filterMenu: some View {
        Menu {
            Button { statusFilter = nil } label: { Label("All", systemImage: statusFilter == nil ? "checkmark" : "") }
            ForEach(MemorizationStatus.allCases) { status in
                Button { statusFilter = status } label: {
                    Label(status.label, systemImage: statusFilter == status ? "checkmark" : status.systemImage)
                }
            }
        } label: {
            Image(systemName: statusFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private var emptyAyahState: some View {
        ContentUnavailableView {
            Label("No ayah ranges yet", systemImage: "text.line.first.and.arrowtriangle.forward")
        } description: {
            Text("Add a range of ayahs within a surah to start tracking it.")
        } actions: {
            Button("Add ayah range") { showAddAyahRange = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// One row in the units list.
struct UnitRow: View {
    let unit: TrackUnit
    let status: MemorizationStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.color)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.title).font(.body.weight(.medium))
                Text(unit.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let arabic = unit.arabic {
                Text(arabic)
                    .font(.system(size: 20, weight: .semibold))
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .padding(.vertical, 4)
    }
}
