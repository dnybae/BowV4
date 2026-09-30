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
        Section("Payee") {
          TextField("Payee name", text: $name)
            .textInputAutocapitalization(.words)
        }
        .listRowBackground(Bow.card)
        Section {
          HStack(spacing: 12) {
            MerchantLogoView(
              merchantName: trimmedName,
              appearanceOverride: PayeeLogoAppearance(
                name: trimmedName,
                source: logoSource,
                domain: merchantDomain,
                imageData: customLogoData
              ),
              size: 52
            )
            VStack(alignment: .leading, spacing: 3) {
              Text("Payee icon")
              Text(logoSource.title)
                .font(.subheadline)
                .foregroundStyle(Bow.inkSoft)
            }
          }
          .padding(.vertical, 3)

          PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Label("Choose photo", systemImage: "photo")
          }
          if isImportingLogo {
            ProgressView("Loading image…")
          }
          Button("Choose file", systemImage: "folder") { showingFiles = true }
          Button("Find logo", systemImage: "magnifyingglass") { showingFindLogo = true }
            .disabled(trimmedName.isEmpty)
          if logoSource != .system {
            Button("Use default icon", systemImage: "storefront.fill") {
              logoSource = .system
            }
          }
        } header: {
          Text("Icon")
        } footer: {
          Text("Every payee starts with a native icon. You can use your own image or choose a Logo.dev logo instead.")
        }
        .listRowBackground(Bow.card)
        Section {
          CategorySelectionField(
            title: "Default envelope", selection: $defaultEnvelopeID,
            envelopes: envelopes, noneTitle: "None"
          )
        } footer: {
          Text("Bow suggests this envelope when you enter this payee on an expense. You can always choose a different one.")
        }
        .listRowBackground(Bow.card)
        Section {
          ForEach(bankNames, id: \.self) { bankName in
            Text(bankName)
          }
          .onDelete { bankNames.remove(atOffsets: $0) }
          HStack {
            TextField("Add bank name", text: $newBankName)
              .textInputAutocapitalization(.characters)
              .autocorrectionDisabled()
              .onSubmit(addBankName)
            Button("Add bank name", systemImage: "plus.circle.fill", action: addBankName)
              .labelStyle(.iconOnly)
              .disabled(trimmedNewBankName.isEmpty)
          }
        } header: {
          Text("Bank names")
        } footer: {
          Text("Imported transactions with one of these descriptions are filed under this payee and use its default envelope. Swipe to remove one.")
        }
        .listRowBackground(Bow.card)
        Section {
          TextField("Add a note", text: $notes, axis: .vertical)
            .lineLimit(2...6)
        } header: {
          Text("Notes")
        } footer: {
          Text("Keep details like a loyalty number or renewal month.")
        }
        .listRowBackground(Bow.card)
        if let entry, entry.transactionCount == 0 && entry.scheduleCount == 0,
           entry.ruleID != nil {
          Section {
            Button("Delete payee", role: .destructive) { showingDelete = true }
          }
          .listRowBackground(Bow.card)
        }
      }
      .bowListBackground()
      .navigationTitle(entry == nil ? "New payee" : "Edit payee")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
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
      .alert(errorTitle, isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
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
