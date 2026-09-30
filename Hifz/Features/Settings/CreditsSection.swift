import SwiftUI

/// Settings section naming the running build and crediting the Quran data the
/// app is built on.
///
/// The Arabic text, the tajweed colouring and the mushaf line layout are not
/// ours: they stay under their own sources' terms (see README.md), so each row
/// says what the app uses and links out to where it came from.
struct CreditsSection: View {

    var body: some View {
        Section {
            LabeledContent("Version", value: appVersion)

            ForEach(Self.credits) { credit in
                VStack(alignment: .leading, spacing: 3) {
                    Text(credit.what)
                        .font(.subheadline.weight(.semibold))
                    Text(credit.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = credit.url {
                        Link(credit.linkLabel, destination: url)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("About & Credits")
        } footer: {
            Text("The Quran data bundled with Hifz comes from the sources above and remains under their own terms — it isn't covered by the app's licence. The Tanzil text is used unmodified.")
        }
    }

    // MARK: - Credits

    /// One line of attribution: what the app uses, whose it is, where to find it.
    private struct Credit: Identifiable {
        let what: String
        let source: String
        let linkLabel: String
        let link: String

        var id: String { what }
        var url: URL? { URL(string: link) }
    }

    private static let credits: [Credit] = [
        Credit(
            what: "Arabic text",
            source: "Tanzil Uthmani (Ḥafṣ), used unmodified — and Tanzil's page, juz and sajda numbering for the 604-page Madani mushaf.",
            linkLabel: "tanzil.net",
            link: "https://tanzil.net"
        ),
        Credit(
            what: "Translation & transliteration",
            source: "Saheeh International, and the English transliteration, via alquran.cloud.",
            linkLabel: "alquran.cloud",
            link: "https://alquran.cloud"
        ),
        Credit(
            what: "Tajweed colouring",
            source: "The quran-tajweed edition via alquran.cloud, kept as a companion to the verified Arabic text.",
            linkLabel: "alquran.cloud",
            link: "https://alquran.cloud"
        ),
        Credit(
            what: "Mushaf line layout",
            source: "The King Fahd Glorious Qur'an Printing Complex (KFGQPC) 15-line Madani mushaf layout, via the QPC line data.",
            linkLabel: "github.com/zonetecde/mushaf-layout",
            link: "https://github.com/zonetecde/mushaf-layout"
        ),
        Credit(
            what: "Recitation audio",
            source: "Streamed from everyayah.com — not bundled with the app.",
            linkLabel: "everyayah.com",
            link: "https://everyayah.com"
        ),
    ]

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return short
        }
        return "\(short) (\(build))"
    }
}
