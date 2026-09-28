import SwiftUI

struct HomeTabBar: View {
  @Binding var selection: HomeTab
  var onAddTransaction: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      HStack(spacing: 0) {
        ForEach(HomeTab.allCases) { tab in
          Button {
            selection = tab
          } label: {
            VStack(spacing: 3) {
              Image(systemName: tab.systemImage)
                .font(.system(size: 18, weight: .semibold))
              Text(tab.title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selection == tab ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
              if selection == tab {
                Capsule().fill(Color.accentColor.opacity(0.15))
              }
            }
            .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(tab.title)
          .accessibilityAddTraits(selection == tab ? .isSelected : [])
        }
      }
      .padding(4)
      .background(.regularMaterial, in: Capsule())

      Button("Add Transaction", systemImage: "plus", action: onAddTransaction)
        .labelStyle(.iconOnly)
        .font(.title2.weight(.semibold))
        .foregroundStyle(.white)
        .frame(width: 60, height: 60)
        .background(.tint, in: Circle())
        .buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.top, 8)
    .padding(.bottom, 4)
  }
}

enum HomeTab: String, CaseIterable, Identifiable {
  case budget
  case transactions
  case calendar
  case accounts

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .budget: "Budget"
    case .transactions: "Transactions"
    case .calendar: "Calendar"
    case .accounts: "Accounts"
    }
  }

  var systemImage: String {
    switch self {
    case .budget: "square.grid.2x2.fill"
    case .transactions: "list.bullet.rectangle"
    case .calendar: "calendar"
    case .accounts: "banknote.fill"
    }
  }
}
