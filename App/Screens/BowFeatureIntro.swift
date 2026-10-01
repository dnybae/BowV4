import SwiftUI

/// The first time someone reaches a bigger feature (bank sync, file import, reconciling):
/// what it does and why, in three short points, then the action. Place it in a List row with
/// a clear background, or on its own.
struct BowFeatureIntro: View {
  var systemImage: String
  var title: String
  var points: [Point]
  var actionTitle: String
  var action: () -> Void

  struct Point: Identifiable {
    var systemImage: String
    var text: String
    var id: String { text }
  }

  var body: some View {
    VStack(spacing: Bow.Space.s5) {
      VStack(spacing: Bow.Space.s3) {
        BowGlossyTile(systemImage: systemImage)
        Text(title)
          .font(.bowTitle)
          .foregroundStyle(Bow.ink)
          .multilineTextAlignment(.center)
          .accessibilityAddTraits(.isHeader)
      }

      VStack(alignment: .leading, spacing: Bow.Space.s4) {
        ForEach(points) { point in
          HStack(alignment: .center, spacing: Bow.Space.s3) {
            BowTileIcon(systemImage: point.systemImage)
            Text(point.text)
              .font(.bowBody)
              .foregroundStyle(Bow.ink)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .accessibilityElement(children: .combine)
        }
      }
      .padding(Bow.Space.s4)
      .bowCard(radius: Bow.Radius.lg)

      Button(action: action) {
        Text(actionTitle)
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity)
      }
      .bowPrimaryButton()
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Bow.Space.s2)
  }
}

/// Keys for intros that show once.
enum BowIntroKey {
  static let bankSync = "bow.intro.bankSync"
  static let fileImport = "bow.intro.fileImport"
  static let reconcile = "bow.intro.reconcile"
}
