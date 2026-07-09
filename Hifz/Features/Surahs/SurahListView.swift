import SwiftUI
import SwiftData

struct SurahListView: View {
    @Environment(\.modelContext) private var context
    @Query private var allProgress: [MemorizationProgress]
    @Query private var settingsList: [AppSettings]
    @Query private var hifzAyahs: [HifzAyah]

    @State private var search = ""
    @State private var statusFilter: MemorizationStatus? = nil
    @State private var showAddAyahRange = false

    /// Order units from the end of the mushaf (An-Nās → Al-Fātiḥa), matching how
    /// most people memorize — starting with the short final surahs. On by default.
    @AppStorage("surahListReversed") private var reversed = true

    /// Multi-select: when active, rows toggle selection instead of navigating,
    /// so several units can be marked memorized in one go.
    @State private var selecting = false
    @State private var selectedKeys: Set<String> = []

    private var settings: AppSettings { settingsList.first ?? AppSettings.current(in: context) }
    private var granularity: Granularity { settings.granularity }

    /// Effective status per unit, unioning the ḥifẓ program's ayah coverage with
    /// any manual mark (see `MemorizationCoverage`).
    private var statusByKey: [String: MemorizationStatus] {
        MemorizationCoverage.statusByUnitKey(
            units: units,
            memorizedKeys: MemorizationCoverage.memorizedKeys(from: hifzAyahs),
            stored: MemorizationCoverage.storedStatus(from: allProgress, granularity: granularity)
        )
    }
    private func status(for unit: TrackUnit) -> MemorizationStatus {
        statusByKey[unit.key] ?? .notStarted
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
        let matched = units.filter { unit in
            let matchesStatus = statusFilter == nil || status(for: unit) == statusFilter
            let matchesSearch = search.isEmpty
                || unit.title.localizedCaseInsensitiveContains(search)
                || unit.subtitle.localizedCaseInsensitiveContains(search)
                || (unit.arabic?.contains(search) ?? false)
            return matchesStatus && matchesSearch
        }
        return reversed ? matched.reversed() : matched
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
                if selecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { exitSelection() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(allFilteredSelected ? "Deselect All" : "Select All") { toggleSelectAll() }
                    }
                    ToolbarItem(placement: .bottomBar) { selectionActionBar }
                } else {
                    ToolbarItem(placement: .topBarLeading) { filterMenu }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select") { selecting = true }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { MushafPageView() } label: { Image(systemName: "book.pages") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { ReaderIndexView() } label: { Image(systemName: "book") }
                    }
                    if granularity == .ayahRange {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { showAddAyahRange = true } label: { Image(systemName: "plus") }
                        }
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
        case .halfPage: return "Half Pages"
        case .quarterPage: return "Quarter Pages"
        case .line: return "Rows"
        case .juz: return "Ajza"
        case .ayahRange: return "Ayah Ranges"
        }
    }

    private var list: some View {
        List(filteredUnits) { unit in
            if selecting {
                Button {
                    toggleSelection(unit)
                } label: {
                    UnitRow(
                        unit: unit,
                        status: status(for: unit),
                        selected: selectedKeys.contains(unit.key)
                    )
                }
                .tint(.primary)
            } else {
                NavigationLink {
                    SurahDetailView(unit: unit)
                } label: {
                    UnitRow(unit: unit, status: status(for: unit))
                }
            }
        }
        .listStyle(.plain)
    }

    private func toggleSelection(_ unit: TrackUnit) {
        if selectedKeys.contains(unit.key) {
            selectedKeys.remove(unit.key)
        } else {
            selectedKeys.insert(unit.key)
        }
    }

    /// Marks every selected unit as memorized in one save, then exits select mode.
    private func markSelectedMemorized() {
        for unit in units where selectedKeys.contains(unit.key) {
            let progress = ProgressManager.progress(for: unit, existing: allProgress, in: context)
            ProgressManager.setStatus(.memorized, for: progress)
        }
        try? context.save()
        exitSelection()
    }

    private func exitSelection() {
        selecting = false
        selectedKeys = []
    }

    private var allFilteredSelected: Bool {
        !filteredUnits.isEmpty && filteredUnits.allSatisfy { selectedKeys.contains($0.key) }
    }

    private func toggleSelectAll() {
        if allFilteredSelected {
            filteredUnits.forEach { selectedKeys.remove($0.key) }
        } else {
            filteredUnits.forEach { selectedKeys.insert($0.key) }
        }
    }

    private var selectionActionBar: some View {
        HStack {
            Text(selectedKeys.isEmpty ? "Select items" : "\(selectedKeys.count) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                markSelectedMemorized()
            } label: {
                Label("Mark memorized", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedKeys.isEmpty)
        }
    }

    private var filterMenu: some View {
        Menu {
            Button { statusFilter = nil } label: { Label("All", systemImage: statusFilter == nil ? "checkmark" : "") }
            ForEach(MemorizationStatus.allCases) { status in
                Button { statusFilter = status } label: {
                    Label(status.label, systemImage: statusFilter == status ? "checkmark" : status.systemImage)
                }
            }
            Divider()
            Toggle(isOn: $reversed) {
                Label("From the end (An-Nās first)", systemImage: "arrow.up.and.down.text.horizontal")
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
    /// nil = normal row; non-nil = multi-select mode showing a checkbox.
    var selected: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let selected {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .frame(width: 28)
            }
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
