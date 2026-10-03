import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct YNABImportScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @AppStorage("bow.demoMode") private var isDemoMode = false
  var groups: [BudgetGroup]
  var envelopes: [BudgetEnvelope]
  @State private var showingFilePicker = false
  @State private var preview: YNABCategoryPreview?
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Button("Choose YNAB plan export", systemImage: "text.document") {
            showingFilePicker = true
          }
          if isDemoMode {
            Button("Use sample export", systemImage: "doc.text") {
              do {
                preview = try YNABCategoryParser().parse(DemoData.sampleYNABExport)
              } catch {
                errorMessage = error.localizedDescription
              }
            }
          }
        } header: {
          Text("File")
        } footer: {
          Text("Choose the zip from YNAB’s Export Plan, or the Plan file inside it. Bow imports your category groups and categories as groups and envelopes. Transactions, past assignments, balances, and targets are left behind.")
            .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)

        if let preview {
          Section {
            Text("\(preview.groups.count) groups · \(preview.envelopeCount) envelopes")
              .font(.bowHeadline)
          }
          .listRowBackground(Bow.card)
          ForEach(preview.groups) { group in
            Section(group.name) {
              ForEach(group.envelopes, id: \.self) { name in
                Label(name, systemImage: "square.grid.2x2.fill")
              }
            }
            .listRowBackground(Bow.card)
          }
        }
      }
      .bowListBackground()
      .navigationTitle("Import from YNAB")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { BowToolbarLabel("Cancel") }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button { save() } label: { BowToolbarLabel("Import") }
            .disabled(preview == nil)
        }
      }
      .fileImporter(
        isPresented: $showingFilePicker,
        allowedContentTypes: [
          .zip,
          .commaSeparatedText,
          UTType(filenameExtension: "tsv") ?? .plainText,
          .plainText
        ]
      ) { result in
        do {
          let url = try result.get()
          let accessed = url.startAccessingSecurityScopedResource()
          defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
          }
          preview = try YNABCategoryParser().parse(data: Data(contentsOf: url))
        } catch {
          errorMessage = error.localizedDescription
        }
      }
      .bowErrorAlert("Couldn’t import YNAB categories", message: $errorMessage)
    }
  }

  private func save() {
    guard let preview else { return }
    do {
      _ = try YNABCategoryImporter().save(
        preview,
        existingGroups: groups,
        existingEnvelopes: envelopes,
        in: modelContext
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
