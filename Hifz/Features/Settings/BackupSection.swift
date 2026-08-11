import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The JSON blob handed to the system's save/share sheet.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw BackupError.unreadable
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Settings section for exporting the store to a JSON file and restoring it back.
///
/// This is the app's backup: everything is on-device only, so the user needs a
/// file they can park in Files, Drive or Dropbox and pull back after a reinstall
/// or a new phone.
struct BackupSection: View {
    @Environment(\.modelContext) private var context

    @State private var document: BackupDocument?
    @State private var exportName = "Hifz-Backup"
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingRestore: BackupArchive?
    @State private var alert: BackupAlert?

    var body: some View {
        Section {
            Button {
                exportBackup()
            } label: {
                Label("Export backup…", systemImage: "square.and.arrow.up")
            }

            Button {
                showImporter = true
            } label: {
                Label("Restore from backup…", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Your ḥifẓ is stored only on this device. Export a copy now and then and keep it somewhere safe — restoring it on a new phone brings back every ayah, schedule and review.")
        }
        .fileExporter(
            isPresented: $showExporter,
            document: document,
            contentType: .json,
            defaultFilename: exportName
        ) { result in
            if case .failure(let error) = result {
                alert = BackupAlert(title: "Export failed", message: error.localizedDescription)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json]
        ) { result in
            loadBackup(from: result)
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(get: { pendingRestore != nil },
                                 set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button("Replace everything", role: .destructive) { applyRestore() }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            if let archive = pendingRestore {
                Text("\(archive.summary), saved \(archive.exportedAt.formatted(date: .abbreviated, time: .shortened)).\n\nThis replaces all data currently on this device. It cannot be undone.")
            }
        }
        .alert(item: $alert) { a in
            Alert(title: Text(a.title), message: Text(a.message), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Actions

    private func exportBackup() {
        do {
            let archive = try BackupArchive.capture(from: context)
            document = BackupDocument(data: try archive.encoded())
            exportName = archive.suggestedFilename
            showExporter = true
        } catch {
            alert = BackupAlert(title: "Export failed", message: error.localizedDescription)
        }
    }

    private func loadBackup(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            // A file picked outside the app's container needs its security scope
            // opened before it can be read.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            pendingRestore = try BackupArchive.decoded(from: try Data(contentsOf: url))
        } catch let error as BackupError {
            alert = BackupAlert(title: "Can't read that backup", message: error.localizedDescription)
        } catch {
            alert = BackupAlert(title: "Can't read that backup",
                                message: BackupError.unreadable.localizedDescription)
        }
    }

    private func applyRestore() {
        guard let archive = pendingRestore else { return }
        pendingRestore = nil
        do {
            try archive.restore(into: context)
            alert = BackupAlert(title: "Restored", message: "\(archive.summary) are back.")
        } catch {
            alert = BackupAlert(title: "Restore failed", message: error.localizedDescription)
        }
    }
}

/// A one-off message from an export/restore attempt.
struct BackupAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
