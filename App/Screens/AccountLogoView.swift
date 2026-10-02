import SwiftUI

struct AccountLogoView: View {
  var appearance: PayeeLogoAppearance
  var systemImage: String = BudgetAccountKind.cash.systemImage
  var size: CGFloat = 38
  var style: MerchantLogoView.Style = .plain

  var body: some View {
    MerchantLogoView(merchantName: appearance.name, appearanceOverride: appearance,
                     fallbackSymbol: systemImage, size: size, style: style)
  }
}
