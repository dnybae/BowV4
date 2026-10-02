import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct PayeeEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  @Query private var envelopes: [BudgetEnvelope]
  var entry: PayeeDirectory.Entry?
  var onSaved: () -> Void
  @State private var name: String
  @State private var bankNames: [String]
  @State private var newBankName = ""
  @State private var merchantDomain: String
  @State private var logoSource: PayeeLogoSource
  @State private var customLogoData: Data?
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var defaultEnvelopeID: UUID?
  @State private var notes: String
  @State private var errorMessage: String?
  @State private var errorTitle = "Couldn’t save payee"
  @State private var showingDelete = false
  @State private var isSaving = false
  @State private var isImportingLogo = false
  @State private var showingFiles = false
  @State private var showingFindLogo = false
  @State private var initialFields: PayeeFields?

  init(entry: PayeeDirectory.Entry?, payee: BudgetPayee? = nil, onSaved: @escaping () -> Void = {}) {
    self.entry = entry
    self.onSaved = onSaved
    _name = State(initialValue: entry?.name ?? "")
    _bankNames = State(initialValue: payee?.bankNames ?? [])
    _merchantDomain = State(initialValue: payee?.merchantDomain ?? "")
    _logoSource = State(initialValue: payee?.logoSource ?? .system)
    _customLogoData = State(initialValue: payee?.customLogoData)
    _defaultEnvelopeID = State(initialValue: payee?.defaultEnvelopeID)
    _notes = State(initialValue: payee?.notes ?? "")
  }

  private var fields: PayeeFields {
    PayeeFields(name: name, bankNames: bankNames, merchantDomain: merchantDomain, logoSource: logoSource,
                customLogoData: customLogoData, defaultEnvelopeID: defaultEnvelopeID, notes: notes)
  }

  private var hasChanges: Bool {
    guard let initialFields else { return false }
    return fields != initialFields || !newBankName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var trimmedNewBankName: String {
    newBankName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var trimmedNotes: String {
    notes.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          BowNameHeader(placeholder: "Payee name", name: $name) {
            MerchantLogoView(
              merchantName: trimmedName,
              appearanceOverride: PayeeLogoAppearance(
                name: trimmedName,
                source: logoSource,
                domain: merchantDomain,
                imageData: customLogoData
              ),
              size: 64, style: .glossy
            )
            .overlay(alignment: .bottomTrailing) {
              Image(systemName: "pencil")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Bow.onBow)
                .frame(width: 22, height: 22)
                .background(Bow.bowSolid, in: Circle())
                .overlay(Circle().stroke(Bow.card, lineWidth: 2))
                .offset(x: 6, y: 6)
                .accessibilityHidden(true)
            }
          }
          .textInputAutocapitalization(.words)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        Section {
          Button { showingFindLogo = true } label: {
            Label("Find logo", systemImage: "globe").labelStyle(.bowTile)
          }
          .disabled(trimmedName.isEmpty)
          PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label("Choose photo", systemImage: "photo").labelStyle(.bowTile)
          }
          if isImportingLogo {
            BowLoadingLabel("Loading image…")
          }
          Button { showingFiles = true } label: {
            Label("Choose file", systemImage: "doc").labelStyle(.bowTile)
          }
          if logoSource != .system {
            Button { logoSource = .system } label: {
              Label("Use default icon", systemImage: "storefront").labelStyle(.bowTile)
            }
          }
        } header: {
          Text("Icon")
        } footer: {
          Text("\(logoSource.title). Every payee starts with a native icon. You can use your own image or choose a Logo.dev logo instead.")
        }
        .listRowBackground(Bow.card)
        Section {
          EnvelopeSelectionField(
            title: "Default envelope", selection: $defaultEnvelopeID,
            envelopes: envelopes, noneTitle: "None", systemImage: "square.grid.2x2"
          )
        } footer: {
          Text("Bow suggests this envelope when you enter this payee on an expense. You can always choose a different one.")
        }
        .listRowBackground(Bow.card)
        Section {
          ForEach(bankNames, id: \.self) { bankName in
            HStack {
              Text(bankName)
              Spacer(minLength: Bow.Space.s2)
              Button("Remove \(bankName)", systemImage: "minus.circle.fill", role: .destructive) {
                bankNames.removeAll { $0 == bankName }
              }
              .labelStyle(.iconOnly)
              .buttonStyle(.borderless)
              .foregroundStyle(Bow.inkFaint)
            }
          }
          HStack(spacing: Bow.Space.s3) {
            BowTileIcon(systemImage: "plus")
            TextField("Add bank name", text: $newBankName)
              .textInputAutocapitalization(.characters)
              .autocorrectionDisabled()
              .onSubmit(addBankName)
            if !trimmedNewBankName.isEmpty {
              Button("Add", action: addBankName)
            }
          }
        } header: {
          Text("Bank names")
        } footer: {
          Text("Imported transactions with one of these descriptions are filed under this payee and use its default envelope.")
        }
        .listRowBackground(Bow.card)
        Section {
          BowNotesRow(notes: $notes)
        } footer: {
          Text("Keep details like a loyalty number or renewal month.")
        }
        .listRowBackground(Bow.card)
        if let entry, entry.transactionCount == 0 && entry.scheduleCount == 0,
           entry.ruleID != nil {
          BowDestructiveSection("Delete payee") { showingDelete = true }
        }
      }
      .bowSkyList(mood: .dawn, height: 420)
      .bowEditorSheet(hasChanges: hasChanges)
      .onAppear { if initialFields == nil { initialFields = fields } }
      .navigationTitle(entry == nil ? "New payee" : "Payee")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        BowCancelButton(hasChanges: hasChanges) { dismiss() }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }
            .disabled(trimmedName.isEmpty || isSaving || isImportingLogo)
        }
      }
      .confirmationDialog("Delete this payee?", isPresented: $showingDelete) {
        Button("Delete payee", role: .destructive) { delete() }
      } message: {
        Text("This removes the saved payee and its matching settings.")
      }
      .bowErrorAlert(errorTitle, message: $errorMessage)
      .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image]) { result in
        do {
          let url = try result.get()
          let hasAccess = url.startAccessingSecurityScopedResource()
          defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
          let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
          guard size <= 50_000_000 else { throw PayeeLogoImage.ImportError.tooLarge }
          customLogoData = try PayeeLogoImage.preparedData(from: Data(contentsOf: url))
          logoSource = .custom
        } catch {
          errorTitle = "Couldn’t load image"
          errorMessage = error.localizedDescription
        }
      }
      .sheet(isPresented: $showingFindLogo) {
        PayeeLogoFinderSheet(payeeName: trimmedName, domain: merchantDomain) { selectedDomain in
          merchantDomain = selectedDomain ?? ""
          logoSource = .logoDev
        }
      }
      .onChange(of: selectedPhoto) { _, photo in
        guard let photo else { return }
        isImportingLogo = true
        Task {
          defer {
            isImportingLogo = false
            selectedPhoto = nil
          }
          do {
            guard let data = try await photo.loadTransferable(type: Data.self) else {
              throw PayeeLogoImage.ImportError.invalidImage
            }
            customLogoData = try PayeeLogoImage.preparedData(from: data)
            logoSource = .custom
          } catch {
            errorTitle = "Couldn’t load image"
            errorMessage = error.localizedDescription
          }
        }
      }
    }
  }

  private func save() async {
    guard !isSaving else { return }
    errorTitle = "Couldn’t save payee"
    isSaving = true
    defer { isSaving = false }
    let newKey = PayeeDirectory.key(trimmedName)
    let repository = PayeeDirectoryRepository(modelContainer: modelContext.container)
    let allEntries: [PayeeDirectory.Entry]
    do {
      allEntries = try await repository.entries()
    } catch {
      errorMessage = error.localizedDescription
      return
    }
    guard !allEntries.contains(where: { $0.key == newKey && $0.key != entry?.key }) else {
      errorMessage = "A payee with this name already exists."
      return
    }
    let finalBankNames = BudgetPayee.cleanedBankNames(
      bankNames + [newBankName], excluding: trimmedName
    )
    let otherKeys = Set(payees.filter { $0.id != entry?.ruleID }.flatMap(PayeeDirectory.matchKeys))
    guard !otherKeys.contains(newKey) else {
      errorMessage = "This name is already used as another payee’s bank name."
      return
    }
    if let taken = finalBankNames.first(where: { otherKeys.contains(PayeeDirectory.key($0)) }) {
      errorMessage = "“\(taken)” already belongs to another payee. Merge the payees instead."
      return
    }
    let domain = merchantDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    do {
      if let entry, newKey != entry.key || trimmedName != entry.name {
        try await repository.renameHistory(from: [entry.key], to: trimmedName)
      }
      let payee: BudgetPayee
      if let existing = payees.first(where: { $0.id == entry?.ruleID }) {
        payee = existing
        payee.name = trimmedName
      } else {
        payee = BudgetPayee(name: trimmedName)
        modelContext.insert(payee)
      }
      payee.bankNames = finalBankNames
      payee.defaultEnvelopeID = defaultEnvelopeID
      payee.notes = trimmedNotes
      payee.merchantDomain = domain.isEmpty ? nil : domain
      payee.logoSource = logoSource
      payee.customLogoData = logoSource == .custom ? customLogoData : nil
      try modelContext.save()
      dismiss()
      onSaved()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func addBankName() {
    guard !trimmedNewBankName.isEmpty else { return }
    bankNames = BudgetPayee.cleanedBankNames(bankNames + [newBankName], excluding: trimmedName)
    newBankName = ""
  }

  private func delete() {
    guard let entry,
          entry.transactionCount == 0,
          entry.scheduleCount == 0,
          let payee = payees.first(where: { $0.id == entry.ruleID }) else { return }
    do {
      modelContext.delete(payee)
      try modelContext.save()
      dismiss()
      onSaved()
    } catch {
      errorTitle = "Couldn’t delete payee"
      errorMessage = error.localizedDescription
    }
  }
}

/// The editable fields, compared to what the sheet opened with.
private struct PayeeFields: Equatable {
  var name: String
  var bankNames: [String]
  var merchantDomain: String
  var logoSource: PayeeLogoSource
  var customLogoData: Data?
  var defaultEnvelopeID: UUID?
  var notes: String
}
