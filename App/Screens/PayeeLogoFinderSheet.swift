import SwiftUI

struct PayeeLogoFinderSheet: View {
  @Environment(\.dismiss) private var dismiss
  var payeeName: String
  var onSelect: (String?) -> Void
  @State private var domain: String
  @State private var previewImage: UIImage?
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
                Image(uiImage: previewImage)
                  .resizable()
                  .scaledToFit()
                  .frame(width: 54, height: 54)
              } else if isLoading {
                ProgressView()
                  .frame(width: 54, height: 54)
              } else {
                Image(systemName: "storefront.fill")
                  .font(.system(size: 25))
                  .foregroundStyle(.secondary)
                  .frame(width: 54, height: 54)
              }
            }
            .frame(width: 64, height: 64)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
              Text(payeeName).font(.headline)
              Text(isLoading ? "Looking for a logo…" : previewImage == nil
                   ? "No logo found" : "Logo found")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 4)
        } footer: {
          Text("A logo is used only after you choose Use Logo. If this isn't the right company, enter its website domain.")
        }

        Section {
          TextField("Website domain", text: $domain)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
          if !validDomain {
            Text("Enter a domain like starbucks.com.")
              .font(.footnote)
              .foregroundStyle(.orange)
          }
        } footer: {
          Text("Optional. A website domain gives a more precise result than the payee name.")
        }
      }
      .navigationTitle("Find Logo")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Use Logo") {
            onSelect(trimmedDomain.isEmpty ? nil : trimmedDomain)
            dismiss()
          }
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
          let (data, response) = try await URLSession.shared.data(from: previewURL)
          guard !Task.isCancelled,
                (response as? HTTPURLResponse)?.statusCode == 200,
                let image = UIImage(data: data) else {
            isLoading = false
            return
          }
          previewImage = image
          isLoading = false
        } catch {
          if !Task.isCancelled { isLoading = false }
        }
      }
    }
  }
}
