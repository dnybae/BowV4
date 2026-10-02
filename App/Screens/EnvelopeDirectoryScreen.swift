import SwiftUI
import SwiftData

struct EnvelopeDirectoryScreen: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @State private var selected: EnvelopeSuggestion?
  @State private var groupID: UUID?
  @State private var message: String?

  private let suggestions: [EnvelopeSuggestion] = [
    .init(name: "Groceries", groupName: "Food & Home"),
    .init(name: "Housing", groupName: "Food & Home"),
    .init(name: "Rent", groupName: "Food & Home"),
    .init(name: "Mortgage", groupName: "Food & Home"),
    .init(name: "Renter’s / Homeowner’s Insurance", groupName: "Food & Home"),
    .init(name: "Utilities", groupName: "Food & Home"),
    .init(name: "Electricity", groupName: "Food & Home"),
    .init(name: "Gas / Heating", groupName: "Food & Home"),
    .init(name: "Water & Trash", groupName: "Food & Home"),
    .init(name: "Internet", groupName: "Food & Home"),
    .init(name: "Cell Phone Plan", groupName: "Food & Home"),
    .init(name: "Dining Out", groupName: "Food & Home"),
    .init(name: "Coffee Shops", groupName: "Food & Home"),
    .init(name: "Alcohol & Bars", groupName: "Food & Home"),
    .init(name: "Household Supplies", groupName: "Food & Home"),
    .init(name: "Laundry & Dry Cleaning", groupName: "Food & Home"),
    .init(name: "Furniture & Home Decor", groupName: "Food & Home"),
    .init(name: "Transportation", groupName: "Getting Around"),
    .init(name: "Auto Care", groupName: "Getting Around"),
    .init(name: "Auto Insurance", groupName: "Getting Around"),
    .init(name: "Public Transit", groupName: "Getting Around"),
    .init(name: "Rideshares & Taxis", groupName: "Getting Around"),
    .init(name: "Gas & Fuel", groupName: "Getting Around"),
    .init(name: "Health", groupName: "Lifestyle"),
    .init(name: "Health Insurance", groupName: "Lifestyle"),
    .init(name: "Medical Out-of-Pocket / Co-pays", groupName: "Lifestyle"),
    .init(name: "Pharmacy & Prescriptions", groupName: "Lifestyle"),
    .init(name: "Therapy & Mental Health", groupName: "Lifestyle"),
    .init(name: "Gym & Fitness Memberships", groupName: "Lifestyle"),
    .init(name: "Haircuts & Salon", groupName: "Lifestyle"),
    .init(name: "Skincare & Cosmetics", groupName: "Lifestyle"),
    .init(name: "Shopping", groupName: "Lifestyle"),
    .init(name: "Clothing & Shoes", groupName: "Lifestyle"),
    .init(name: "Pet Food & Supplies", groupName: "Lifestyle"),
    .init(name: "Vet Visits & Medications", groupName: "Lifestyle"),
    .init(name: "Pet Grooming & Boarding", groupName: "Lifestyle"),
    .init(name: "Streaming & Media Subscriptions", groupName: "Lifestyle"),
    .init(name: "Software & Digital Tools", groupName: "Lifestyle"),
    .init(name: "Hobbies & Crafts", groupName: "Lifestyle"),
    .init(name: "Movies, Events & Concerts", groupName: "Lifestyle"),
    .init(name: "Books & Education", groupName: "Lifestyle"),
    .init(name: "Bank & Transaction Fees", groupName: "Lifestyle"),
    .init(name: "Postal & Shipping", groupName: "Lifestyle"),
    .init(name: "Legal & Admin Fees", groupName: "Lifestyle"),
    .init(name: "Gifts", groupName: "Lifestyle"),
    .init(name: "Charitable Giving", groupName: "Lifestyle"),
    .init(name: "Emergency Fund", groupName: "Future"),
    .init(name: "Home Repairs", groupName: "Future"),
    .init(name: "Travel", groupName: "Future"),
    .init(name: "Student Loans", groupName: "Future"),
    .init(name: "Personal Loans", groupName: "Future"),
    .init(name: "Device & Tech Replacement", groupName: "Future"),
    .init(name: "Retirement Contributions / Investments", groupName: "Future"),
    .init(name: "Buffer / “Things I Forgot to Budget For”", groupName: "Future")
  ]

  var body: some View {
    List {
      ForEach(["Food & Home", "Getting Around", "Lifestyle", "Future"], id: \.self) { groupName in
        Section(groupName) {
          ForEach(suggestions.filter { $0.groupName == groupName }) { suggestion in
            Button(suggestion.name) {
              selected = suggestion
              groupID = groups.first {
                $0.name.localizedCaseInsensitiveCompare(groupName) == .orderedSame
              }?.id
            }
            .disabled(envelopes.contains {
              $0.name.localizedCaseInsensitiveCompare(suggestion.name) == .orderedSame
                && !$0.isHidden
            })
          }
        }
        .listRowBackground(Bow.card)
      }
    }
    .bowListBackground()
    .navigationTitle("Envelope ideas")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $selected) { suggestion in
      NavigationStack {
        Form {
          Section("Envelope") {
            LabeledContent("Name", value: suggestion.name)
            Picker("Group", selection: $groupID) {
              Text("New: \(suggestion.groupName)").tag(Optional<UUID>.none)
              ForEach(groups.filter { !$0.isSystem }.sorted { $0.sortOrder < $1.sortOrder }) { group in
                Text(group.name).tag(Optional(group.id))
              }
            }
          }
          .listRowBackground(Bow.card)
          Section {
            Text("A directory envelope starts with no money assigned. You can edit its target later.")
              .font(.bowBody)
              .foregroundStyle(Bow.inkSoft)
          }
          .listRowBackground(Bow.card)
        }
        .bowListBackground()
        .navigationTitle("Add envelope")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button { selected = nil } label: { BowToolbarLabel("Cancel") }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button { add(suggestion) } label: { BowToolbarLabel("Add") }
          }
        }
      }
    }
    .bowErrorAlert("Couldn’t add envelope", message: $message)
  }

  private func add(_ suggestion: EnvelopeSuggestion) {
    do {
      let destinationID: UUID
      if let groupID {
        destinationID = groupID
      } else if let existing = groups.first(where: {
        $0.name.localizedCaseInsensitiveCompare(suggestion.groupName) == .orderedSame
      }) {
        destinationID = existing.id
      } else {
        let group = BudgetGroup(name: suggestion.groupName, sortOrder: groups.count)
        modelContext.insert(group)
        destinationID = group.id
      }
      if let hidden = envelopes.first(where: {
        $0.groupID == destinationID
          && $0.name.localizedCaseInsensitiveCompare(suggestion.name) == .orderedSame
          && $0.isHidden
      }) {
        hidden.isHidden = false
        try modelContext.save()
      } else {
        try BudgetCommands.addEnvelope(
          name: suggestion.name, symbol: "", groupID: destinationID,
          order: envelopes.filter { $0.groupID == destinationID }.count,
          in: modelContext
        )
      }
      selected = nil
      dismiss()
    } catch {
      message = error.localizedDescription
    }
  }
}

private struct EnvelopeSuggestion: Identifiable {
  var name: String
  var groupName: String
  var id: String { groupName + "/" + name }
}
