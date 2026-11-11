import SwiftUI

/// The dashboard's headline progress: one ring that can count memorized
/// surahs, pages, ajzāʾ or ayahs, plus a tappable map of all 30 ajzāʾ.
///
/// Every metric is derived from the same set of memorized ayah keys (program
/// rows unioned with manual marks), so a page fully covered by a surah marked
/// in the list counts as a memorized page too.
struct ProgressOverviewCard: View {
    let memorizedKeys: Set<String>
    /// Ayahs assigned in Sabaq but not yet confirmed.
    let inProgressKeys: Set<String>

    enum Metric: String, CaseIterable, Identifiable {
        case surah, page, juz, ayah
        var id: String { rawValue }
        var label: String {
            switch self {
            case .surah: return "Surahs"
            case .page: return "Pages"
            case .juz: return "Juz"
            case .ayah: return "Ayahs"
            }
        }
        var noun: String {
            switch self {
            case .surah: return "surahs"
            case .page: return "pages"
            case .juz: return "ajzāʾ"
            case .ayah: return "ayahs"
            }
        }
        var tint: Color {
            switch self {
            case .surah: return .accentColor
            case .page: return .teal
            case .juz: return .indigo
            case .ayah: return .green
            }
        }
        var granularity: Granularity? {
            switch self {
            case .surah: return .surah
            case .page: return .page
            case .juz: return .juz
            case .ayah: return nil
            }
        }
    }

    @AppStorage("dashboardMetric") private var metricRaw = Metric.page.rawValue
    @State private var selectedJuz: Int?
    @State private var appeared = false

    private var metric: Metric { Metric(rawValue: metricRaw) ?? .page }

    struct Tally { var memorized = 0, learning = 0, total = 0 }

    private func tally(_ m: Metric) -> Tally {
        guard let g = m.granularity else {
            let learning = inProgressKeys.subtracting(memorizedKeys).count
            return Tally(memorized: memorizedKeys.count, learning: learning, total: QuranData.totalAyahs)
        }
        let started = memorizedKeys.union(inProgressKeys)
        var t = Tally()
        for unit in QuranData.units(for: g) {
            let keys = MemorizationCoverage.ayahKeys(in: unit)
            guard !keys.isEmpty else { continue }
            t.total += 1
            let done = keys.reduce(0) { $0 + (memorizedKeys.contains($1) ? 1 : 0) }
            if done == keys.count { t.memorized += 1 }
            else if done > 0 || keys.contains(where: started.contains) { t.learning += 1 }
        }
        return t
    }

    var body: some View {
        let t = tally(metric)
        let fraction = t.total == 0 ? 0 : Double(t.memorized) / Double(t.total)

        VStack(spacing: 16) {
            Picker("Count", selection: $metricRaw.animation(.snappy)) {
                ForEach(Metric.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)

            ring(fraction: appeared ? fraction : 0, tally: t)
                .frame(width: 190, height: 190)
                .contentShape(Circle())
                .onTapGesture { cycle(by: 1) }
                .gesture(DragGesture(minimumDistance: 30).onEnded { v in
                    cycle(by: v.translation.width < 0 ? 1 : -1)
                })
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Switches between surahs, pages, juz and ayahs")

            HStack(spacing: 0) {
                pill("\(t.memorized)", "memorized", .green)
                Divider().frame(height: 28)
                pill("\(t.learning)", "in progress", .orange)
                Divider().frame(height: 28)
                pill("\(max(0, t.total - t.memorized - t.learning))", "to go", .secondary)
            }

            juzMap
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
        .sensoryFeedback(.selection, trigger: metricRaw)
        .sensoryFeedback(.selection, trigger: selectedJuz)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.1)) { appeared = true }
        }
    }

    private func ring(fraction: Double, tally t: Tally) -> some View {
        ZStack {
            Circle().stroke(metric.tint.opacity(0.15), lineWidth: 16)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, fraction)))
                .stroke(metric.tint, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: fraction)
            VStack(spacing: 2) {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: fraction))
                Text("\(t.memorized) / \(t.total) \(metric.noun)")
                    .font(.subheadline.weight(.medium))
                    .contentTransition(.numericText())
                Text("tap to switch")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func pill(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func cycle(by step: Int) {
        let all = Metric.allCases
        let i = all.firstIndex(of: metric) ?? 0
        withAnimation(.snappy) {
            metricRaw = all[(i + step + all.count) % all.count].rawValue
        }
    }

    // MARK: - Juz map

    private var juzFractions: [Int: (done: Int, total: Int)] {
        var out: [Int: (Int, Int)] = [:]
        for unit in QuranData.units(for: .juz) {
            let c = MemorizationCoverage.counts(for: unit, memorizedKeys: memorizedKeys)
            out[unit.juzNumber] = (c.memorized, c.total)
        }
        return out
    }

    private var juzMap: some View {
        let fractions = juzFractions
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Juz map").font(.subheadline.weight(.semibold))
                Spacer()
                if let j = selectedJuz, let f = fractions[j] {
                    Text("Juz \(j) · \(f.total == 0 ? 0 : f.done * 100 / f.total)% · \(f.done)/\(f.total) ayahs")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    Text("Tap a juz").font(.caption).foregroundStyle(.tertiary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                ForEach(1...30, id: \.self) { j in
                    let f = fractions[j] ?? (0, 1)
                    juzCell(j, fraction: f.total == 0 ? 0 : Double(f.done) / Double(f.total))
                }
            }
        }
    }

    private func juzCell(_ juz: Int, fraction: Double) -> some View {
        let selected = selectedJuz == juz
        return ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.indigo.opacity(0.12))
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 6)
                    .fill(fraction >= 1 ? Color.green : Color.indigo.opacity(0.35 + 0.5 * fraction))
                    .frame(height: geo.size.height * (appeared ? fraction : 0))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            Text("\(juz)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(fraction >= 0.6 ? .white : .primary)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.primary : .clear, lineWidth: 2))
        .scaleEffect(selected ? 1.12 : 1)
        .onTapGesture {
            withAnimation(.snappy) { selectedJuz = selected ? nil : juz }
        }
        .accessibilityLabel("Juz \(juz), \(Int(fraction * 100)) percent memorized")
        .accessibilityAddTraits(.isButton)
    }
}
