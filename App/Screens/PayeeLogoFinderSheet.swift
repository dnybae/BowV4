import SwiftUI

struct PayeeLogoFinderSheet: View {
  @Environment(\.dismiss) private var dismiss
  var payeeName: String
  var onSelect: (String?) -> Void
  @State private var domain: String
  @State private var previewImage: BrandLogo?
  @State private var isLoading = false

  init(payeeName: String, domain: String?, onSelect: @escaping (String?) -> Void) {
    self.payeeName = payeeName
    self.onSelect = onSelect
    _domain = State(initialValue: domain ?? "")
  }

  private var trimmedDomain: String {
    domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private var validDomain: Bool {
    trimmedDomain.isEmpty || trimmedDomain.range(
      of: "^(?:[A-Za-z0-9-]+\\.)+[A-Za-z]{2,}$", options: .regularExpression
    ) != nil
  }

  private var previewURL: URL? {
    guard validDomain else { return nil }
    return LogoDev.logoURL(
      domain: trimmedDomain.isEmpty ? nil : trimmedDomain,
      merchantName: payeeName
    )
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack(spacing: 16) {
            Group {
              if let previewImage {
                BrandLogoImage(logo: previewImage, side: 64)
              } else if isLoading {
                RoundedRectangle(cornerRadius: Bow.Radius.sm)
                  .fill(Bow.well)
                  .frame(width: 54, height: 54)
                  .bowShimmer()
              } else {
                Image(systemName: "storefront.fill")
                  .bowScaledIcon(frame: 54, glyph: 25, weight: .regular)
                  .foregroundStyle(Bow.inkSoft)
              }
            }
            .frame(width: 64, height: 64)
            .background(Bow.well,
                        in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
              Text(payeeName).font(.bowHeadline)
              Text(isLoading ? "Looking for a logo…" : previewImage == nil
                   ? "No logo found" : "Logo found")
                .font(.bowSubhead)
                .foregroundStyle(Bow.inkSoft)
            }
          }
          .padding(.vertical, 4)
        } footer: {
          Text("A logo is used only after you choose Use Logo. If this isn't the right company, enter its website domain.")
            .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)

        Section {
          TextField("Website domain", text: $domain)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
          if !validDomain {
            Text("Enter a domain like starbucks.com.")
              .font(.bowFootnote)
              .foregroundStyle(Bow.needsInk)
          }
        } footer: {
          Text("Optional. A website domain gives a more precise result than the payee name.")
            .font(.bowFootnote)
        }
        .listRowBackground(Bow.card)
      }
      .bowListBackground()
      .scrollDismissesKeyboard(.interactively)
      .bowAnimation(value: isLoading)
      .navigationTitle("Find logo")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button { dismiss() } label: { BowToolbarLabel("Cancel") }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            onSelect(trimmedDomain.isEmpty ? nil : trimmedDomain)
            dismiss()
          } label: { BowToolbarLabel("Use logo") }
          .disabled(previewImage == nil || !validDomain)
        }
      }
      .task(id: previewURL) {
        previewImage = nil
        guard let previewURL else {
          isLoading = false
          return
        }
        isLoading = true
        do {
          try await Task.sleep(for: .milliseconds(300))
          let logo = await BrandLogoStore.logo(for: previewURL)
          guard !Task.isCancelled, let logo else {
            isLoading = false
            return
          }
          previewImage = logo
          isLoading = false
        } catch {
          if !Task.isCancelled { isLoading = false }
        }
      }
    }
  }
}
