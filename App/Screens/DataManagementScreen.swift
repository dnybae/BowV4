import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings › Your data: export a full backup and a transactions spreadsheet, or restore a backup.
struct DataManagementScreen: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.bowToasts) private var toasts
  @AppStorage("bow.demoMode") private var isDemoMode = false
  var appVersion: String
  @State private var exports: Exports?
  @State private var isPreparing = false
  @State private var showingImporter = false
  @State private var pendingRestore: BowBackup?
  @State private var errorMessage: String?

  struct Exports {
    var backup: URL
    var spreadsheet: URL
  }

  var body: some View {
    List {
      Section {
        if let exports {
          ShareLink(item: exports.backup) {
            Label("Share backup", systemImage: "externaldrive.badge.checkmark")
          }
          ShareLink(item: exports.spreadsheet) {
            Label("Share transactions spreadsheet", systemImage: "tablecells")
          }
        } else {
          BowLoadingLabel("Preparing your files…")
        }
      } header: {
        Text("Export")
      } footer: {
        Text("The backup holds your whole budget and can be restored on any iPhone. The spreadsheet lists every transaction as CSV. Both are made on this iPhone and go only where you send them.")
          .font(.bowFootnote)
      }
      .listRowBackground(Bow.card)

      Section {
        Button("Restore from backup…", systemImage: "arrow.counterclockwise") { showingImporter = true }
          .disabled(isDemoMode)
      } header: {
        Text("Restore")
      } footer: {
        Text(isDemoMode
          ? "Turn off demo mode to restore your own budget."
          : "Restoring replaces everything in this budget with the backup. Bank sync needs to be connected again afterwards.")
          .font(.bowFootnote)
      }
      .listRowBackground(Bow.card)
    }
    .bowListBackground()
    .navigationTitle("Your data")
    .navigationBarTitleDisplayMode(.inline)
    .task { prepareExports() }
    .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
      load(result)
    }
    .bowConfirmationDialog("Replace your budget with this backup?", item: $pendingRestore) { backup in
      Button("Replace Budget", role: .destructive) { restore(backup) }
    } message: { backup in
      Text("\(backup.summary)\n\nEverything currently in Bow is replaced. Export a backup first if you might want it back.")
    }
    .bowErrorAlert("Your data", message: $errorMessage)
  }

  private func prepareExports() {
    guard exports == nil, !isPreparing else { return }
    isPreparing = true
    defer { isPreparing = false }
    do {
      let stamp = Date().formatted(.iso8601.year().month().day())
      let folder = FileManager.default.temporaryDirectory.appending(path: "BowExport", directoryHint: .isDirectory)
      try? FileManager.default.removeItem(at: folder)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let backupURL = folder.appending(path: "Bow Backup \(stamp).json")
      try BowBackup.make(from: modelContext, appVersion: appVersion).encoded().write(to: backupURL, options: .completeFileProtection)
      let csvURL = folder.appending(path: "Bow Transactions \(stamp).csv")
      try Data(TransactionCSVExporter().csv(from: modelContext).utf8).write(to: csvURL, options: .completeFileProtection)
      exports = Exports(backup: backupURL, spreadsheet: csvURL)
    } catch {
      errorMessage = "Bow couldn’t prepare your files. \(error.localizedDescription)"
    }
  }

  private func load(_ result: Result<URL, Error>) {
    do {
      let url = try result.get()
      let accessing = url.startAccessingSecurityScopedResource()
      defer { if accessing { url.stopAccessingSecurityScopedResource() } }
      pendingRestore = try BowBackup.decode(Data(contentsOf: url))
    } catch let error as BowBackup.RestoreError {
      errorMessage = error.localizedDescription
    } catch is DecodingError {
      errorMessage = "This file isn’t a Bow backup."
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func restore(_ backup: BowBackup) {
    do {
      try backup.restore(into: modelContext)
      try? SimpleFINCredentialStore().delete()
      exports = nil
      prepareExports()
      toasts?.show(.saved("Restored · \(backup.profile?.name ?? "Budget")"))
    } catch {
      modelContext.rollback()
      errorMessage = "Bow couldn’t restore this backup, so nothing was changed. \(error.localizedDescription)"
    }
  }
}

extension BowBackup: Identifiable {
  var id: Date { exportedAt }
}
