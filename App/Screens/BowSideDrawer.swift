import SwiftUI

enum BowDrawerPage: String, Identifiable {
  case insights
  case inventory
  case settings

  var id: String { rawValue }
}

struct BowSideDrawer: View {
  var budgetName: String
  var onClose: () -> Void
  var onRename: () -> Void
  var onOpen: (BowDrawerPage) -> Void

  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 0) {
        VStack(spacing: 0) {
          Image("BrandIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .padding(.top, 28)
            .accessibilityLabel("Bow app icon")

          Button(action: onRename) {
            HStack(spacing: 6) {
              Text(budgetName)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
              Image(systemName: "pencil")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityHint("Rename this budget")

          Divider().padding(.bottom, 12)
          drawerButton("Insights", symbol: "chart.xyaxis.line", page: .insights)
          drawerButton("Home Inventory", symbol: "shippingbox", page: .inventory)
          drawerButton("Settings", symbol: "gearshape", page: .settings)
          HStack(spacing: 14) {
            Image(systemName: "plus")
              .frame(width: 22)
            Text("New Budget")
            Spacer()
            Text("Coming soon")
              .font(.caption)
          }
          .foregroundStyle(.tertiary)
          .frame(minHeight: 50)
          .padding(.horizontal, 20)
          .accessibilityLabel("New Budget, coming soon")
          Spacer()
        }
        .frame(width: min(geometry.size.width * 0.84, 340))
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .transition(.move(edge: .leading))

        Button(action: onClose) {
          Color.clear.contentShape(Rectangle())
        }
          .accessibilityLabel("Close Menu")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .contentShape(Rectangle())
          .buttonStyle(.plain)
      }
      .background(Color.black.opacity(0.28).ignoresSafeArea())
    }
    .ignoresSafeArea(edges: .bottom)
  }

  private func drawerButton(_ title: String, symbol: String, page: BowDrawerPage) -> some View {
    Button { onOpen(page) } label: {
      Label(title, systemImage: symbol)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 20)
    }
    .buttonStyle(.plain)
  }
}
