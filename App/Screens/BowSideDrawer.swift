import SwiftUI

enum BowDrawerPage: String, Identifiable {
  case insights
  case inventory
  case settings

  var id: String { rawValue }
}

struct BowSideDrawer: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var isPresented: Bool
  var allowsEdgeOpen: Bool
  var budgetName: String
  var onRename: () -> Void
  var onOpen: (BowDrawerPage) -> Void
  @State private var openingDrag: CGFloat = 0
  @State private var closingDrag: CGFloat = 0

  var body: some View {
    GeometryReader { geometry in
      let width = min(geometry.size.width * 0.84, 340)
      let progress = isPresented
        ? max(0, min(1, 1 + closingDrag / width))
        : max(0, min(1, openingDrag / width))

      ZStack(alignment: .leading) {
        if progress > 0 {
          Button(action: close) {
            Color.black.opacity(0.28 * progress)
              .ignoresSafeArea()
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Close Menu")
          .allowsHitTesting(isPresented)
          .accessibilityHidden(!isPresented)
        }

        menuContent
          .frame(width: width, height: geometry.size.height)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
          .shadow(color: .black.opacity(0.16 * progress), radius: 18)
          .offset(x: -width * (1 - progress))
          .simultaneousGesture(closeGesture(width: width))
          .allowsHitTesting(isPresented)
          .accessibilityHidden(!isPresented)

        if !isPresented && allowsEdgeOpen {
          Color.clear
            .frame(width: 24)
            .contentShape(Rectangle())
            .gesture(openGesture(width: width))
            .accessibilityHidden(true)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
    .ignoresSafeArea(edges: .bottom)
  }

  private var menuContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top) {
          Image("BrandIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .accessibilityLabel("Bow app icon")
          Spacer()
          Button("Close") { close() }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)

        Button(action: onRename) {
          HStack(spacing: 6) {
            Text(budgetName)
              .font(.title3.weight(.semibold))
              .lineLimit(2)
            Image(systemName: "pencil")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
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
      }
    }
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

  private func openGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { value in
        guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
        openingDrag = max(0, min(width, value.translation.width))
      }
      .onEnded { value in
        let shouldOpen = abs(value.translation.width) > abs(value.translation.height) * 1.2
          && value.predictedEndTranslation.width > width * 0.34
        withAnimation(reduceMotion ? nil : .snappy) {
          isPresented = shouldOpen
          openingDrag = 0
        }
      }
  }

  private func closeGesture(width: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { value in
        guard abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
        closingDrag = max(-width, min(0, value.translation.width))
      }
      .onEnded { value in
        let shouldClose = abs(value.translation.width) > abs(value.translation.height) * 1.2
          && value.predictedEndTranslation.width < -width * 0.34
        withAnimation(reduceMotion ? nil : .snappy) {
          isPresented = !shouldClose
          closingDrag = 0
        }
      }
  }

  private func close() {
    withAnimation(reduceMotion ? nil : .snappy) { isPresented = false }
  }
}
