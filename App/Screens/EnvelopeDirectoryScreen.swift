import SwiftUI
import SwiftData

struct EnvelopeDirectoryScreen: View {
  @Query private var groups: [BudgetGroup]
  @Query private var envelopes: [BudgetEnvelope]
  @State private var selected: EnvelopeIdea?

  private let suggestions: [EnvelopeIdea] = [
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

  private func isAdded(_ idea: EnvelopeIdea) -> Bool {
    envelopes.contains {
      $0.name.localizedCaseInsensitiveCompare(idea.name) == .orderedSame && !$0.isHidden
    }
  }

  var body: some View {
    List {
      Section {
        Text("Tap an idea to add it. Ideas you already have are checked.")
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
          .listRowBackground(Color.clear)
      }
      ForEach(["Food & Home", "Getting Around", "Lifestyle", "Future"], id: \.self) { groupName in
        Section(groupName) {
          ForEach(suggestions.filter { $0.groupName == groupName }) { idea in
            let added = isAdded(idea)
            Button {
              selected = idea
            } label: {
              HStack {
                Text(idea.name)
                  .foregroundStyle(added ? Bow.inkSoft : Bow.ink)
                Spacer(minLength: Bow.Space.s2)
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                  .foregroundStyle(added ? AnyShapeStyle(Bow.funded) : AnyShapeStyle(.tint))
                  .accessibilityHidden(true)
              }
              .contentShape(Rectangle())
            }
            .disabled(added)
            .accessibilityValue(added ? "Added" : "")
          }
        }
        .listRowBackground(Bow.card)
      }
    }
    .bowListBackground()
    .navigationTitle("Envelope ideas")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $selected) { idea in
      // The same editor as New Envelope, filled in from the idea; this list stays open after.
      EnvelopeEditorScreen(groups: groups, idea: idea)
    }
  }
}
