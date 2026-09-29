import SwiftUI
import SwiftData

struct PayeeEditorScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var payees: [BudgetPayee]
  @Query private var envelopes: [BudgetEnvelope]
  var entry: PayeeDirectory.Entry?
  var onSaved: () -> Void
  @State private var name: String
  @State private var exactMatchText: String
  @State private var merchantDomain: String
  @State private var brandResults: [BrandSearchResult] = []
  @State private var defaultEnvelopeID: UUID?
  @State private var errorMessage: String?
  @State private var showingDelete = false
  @State private var isSaving = false

  init(entry: PayeeDirectory.Entry?, payee: BudgetPayee? = nil, onSaved: @escaping () -> Void = {}) {
    self.entry = entry
    self.onSaved = onSaved
    _name = State(initialValue: entry?.name ?? "")
    _exactMatchText = State(initialValue: payee?.exactMatchText ?? "")
    _merchantDomain = State(initialValue: payee?.merchantDomain ?? "")
    _defaultEnvelopeID = State(initialValue: payee?.defaultEnvelopeID)
  }

  private var trimmedName: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Payee") {
          TextField("Payee Name", text: $name)
            .textInputAutocapitalization(.words)
          if merchantDomain.isEmpty && !brandResults.isEmpty {
            ForEach(brandResults) { brand in
              Button {
                name = brand.name
                merchantDomain = brand.domain
                brandResults = []
              } label: {
                HStack(spacing: 12) {
                  MerchantLogoView(
                    merchantName: brand.name, domain: brand.domain,
                    logoURL: brand.compactLogoURL
                  )
                  VStack(alignment: .leading, spacing: 2) {
                    Text(brand.name).foregroundStyle(.primary)
                    Text(brand.domain).font(.caption).foregroundStyle(.secondary)
                  }
                }
                .contentShape(Rectangle())
              }
            }
          }
        }
        Section {
          TextField("Website domain", text: $merchantDomain)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
          if !validDomain {
            Text("Enter a domain like starbucks.com.")
              .font(.footnote)
              .foregroundStyle(.orange)
          }
        } header: {
          Text("Company")
        } footer: {
          Text("Choose a company suggestion above or enter its website domain to show the correct logo. Leave blank for a personal payee.")
        }
        Section {
          CategorySelectionField(
            title: "Default Category", selection: $defaultEnvelopeID,
            envelopes: envelopes, noneTitle: "None"
          )
        } footer: {
          Text("Bow suggests this envelope when you enter this payee on an expense. You can always choose a different one.")
        }
        Section {
          TextField("Exact bank description", text: $exactMatchText)
            .textInputAutocapitalization(.characters)
        } footer: {
          Text("Optional. Match a bank’s full payee description to this payee and its default envelope when importing transactions.")
        }
        if let entry, entry.transactionCount == 0 && entry.scheduleCount == 0,
           entry.ruleID != nil {
          Section {
            Button("Delete Payee", role: .destructive) { showingDelete = true }
          }
        }
      }
      .navigationTitle(entry == nil ? "New Payee" : "Edit Payee")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { Task { await save() } }
            .disabled(trimmedName.isEmpty || !validDomain || isSaving)
        }
      }
      .confirmationDialog("Delete this payee?", isPresented: $showingDelete) {
        Button("Delete Payee", role: .destructive) { delete() }
      } message: {
        Text("This removes the saved payee and its matching settings.")
      }
      .alert("Couldn’t Save Payee", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK") { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
      .task(id: trimmedName) {
        brandResults = []
        guard merchantDomain.isEmpty, trimmedName.count >= 2,
              BrandLookupClient.isConfigured else { return }
        do {
          try await Task.sleep(for: .milliseconds(200))
          let results = try await BrandLookupClient.search(trimmedName)
          try Task.checkCancellation()
          brandResults = results
        } catch { }
      }
    }
  }

  private var validDomain: Bool {
    let value = merchantDomain.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty || value.range(of: "^(?:[A-Za-z0-9-]+\\.)+[A-Za-z]{2,}$", options: .regularExpression) != nil
  }

  private func save() async {
    guard !isSaving else { return }
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
    guard !payees.contains(where: {
      $0.id != entry?.ruleID && PayeeDirectory.key($0.exactMatchText) == newKey
    }) else {
      errorMessage = "This name is already used as another payee’s bank description."
      return
    }
    let exact = exactMatchText.trimmingCharacters(in: .whitespacesAndNewlines)
    let exactKey = PayeeDirectory.key(exact)
    guard exact.isEmpty || !payees.contains(where: {
      $0.id != entry?.ruleID
        && (PayeeDirectory.key($0.exactMatchText) == exactKey
          || PayeeDirectory.key($0.name) == exactKey)
    }) else {
      errorMessage = "Another payee already matches this bank description."
      return
    }
    do {
      if let entry {
        let previousExact = payees.first { $0.id == entry.ruleID }?.exactMatchText ?? ""
        if newKey != entry.key || trimmedName != entry.name
            || PayeeDirectory.key(previousExact) != exactKey {
          try await repository.renameHistory(
            from: Set([entry.key, PayeeDirectory.key(previousExact)]).subtracting([""]),
            to: trimmedName
          )
        }
        if let payee = payees.first(where: { $0.id == entry.ruleID }) {
          payee.name = trimmedName
          payee.exactMatchText = exact
          payee.defaultEnvelopeID = defaultEnvelopeID
          payee.merchantDomain = merchantDomain.isEmpty ? nil : merchantDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        } else {
          modelContext.insert(BudgetPayee(
            name: trimmedName,
            defaultEnvelopeID: defaultEnvelopeID,
            exactMatchText: exact,
            merchantDomain: merchantDomain.isEmpty ? nil : merchantDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
          ))
        }
      } else {
        modelContext.insert(BudgetPayee(
          name: trimmedName,
          defaultEnvelopeID: defaultEnvelopeID,
          exactMatchText: exact,
          merchantDomain: merchantDomain.isEmpty ? nil : merchantDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        ))
      }
      try modelContext.save()
      dismiss()
      onSaved()
    } catch {
      errorMessage = error.localizedDescription
    }
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
      errorMessage = error.localizedDescription
    }
  }
}
