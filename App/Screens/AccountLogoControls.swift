import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// The Icon section of the account editor. Its sheet, file importer and alert live on the form
/// (`accountLogoPresentations`), not on this section: a modifier on a `Section` is copied onto
/// every row, and several rows presenting the same sheet dismissed the whole editor.
struct AccountLogoControls: View {
  @Binding var settings: AccountLogoSettings
  @Binding var presentation: AccountLogoPresentation
  var institutionName: String?
  var institutionDomain: String?

  var body: some View {
    Section {
      Button { presentation.showingFinder = true } label: {
        Label("Find logo", systemImage: "globe").labelStyle(.bowTile)
      }
      PhotosPicker(selection: $presentation.selectedPhoto, matching: .images) {
        Label("Choose photo", systemImage: "photo").labelStyle(.bowTile)
      }
      Button { presentation.showingFiles = true } label: {
        Label("Choose file", systemImage: "doc").labelStyle(.bowTile)
      }
      if presentation.isImporting { BowLoadingLabel("Loading image…") }
      // A new account has no icon choice yet; that already is the default icon.
      if settings.source != nil && settings.source != .system {
        Button {
          settings.source = .system
        } label: {
          Label("Use default icon", systemImage: "building.columns").labelStyle(.bowTile)
        }
      }
      if settings.source != nil, institutionName != nil || institutionDomain != nil {
        Button("Use automatic bank logo", systemImage: "arrow.clockwise") {
          settings = AccountLogoSettings()
        }
      }
    } header: {
      Text("Icon")
    } footer: {
      Text("Find your bank’s logo by name or website, or choose your own image. Linked accounts use the bank logo automatically unless you choose another icon.")
        .font(.bowFootnote)
    }
    .listRowBackground(Bow.card)
  }
}

/// What the Icon section is presenting.
struct AccountLogoPresentation {
  var showingFinder = false
  var showingFiles = false
  var selectedPhoto: PhotosPickerItem?
  var isImporting = false
  var errorMessage: String?
}

extension View {
  /// The Icon section's logo finder, file importer and photo loading. Apply once, to the form.
  func accountLogoPresentations(
    settings: Binding<AccountLogoSettings>,
    presentation: Binding<AccountLogoPresentation>,
    lookupName: String,
    institutionDomain: String?
  ) -> some View {
    modifier(AccountLogoPresentations(
      settings: settings, presentation: presentation,
      lookupName: lookupName, institutionDomain: institutionDomain
    ))
  }
}

private struct AccountLogoPresentations: ViewModifier {
  @Binding var settings: AccountLogoSettings
  @Binding var presentation: AccountLogoPresentation
  var lookupName: String
  var institutionDomain: String?

  private var name: String {
    settings.lookupName.isEmpty ? lookupName : settings.lookupName
  }

  func body(content: Content) -> some View {
    content
      .sheet(isPresented: $presentation.showingFinder) {
        PayeeLogoFinderSheet(payeeName: name,
                            domain: settings.source == .logoDev ? settings.domain : institutionDomain,
                            isBank: true) { domain in
          settings.lookupName = name
          settings.domain = domain ?? ""
          settings.source = .logoDev
        }
      }
      .fileImporter(isPresented: $presentation.showingFiles, allowedContentTypes: [.image]) { result in
        do {
          let url = try result.get()
          let accessing = url.startAccessingSecurityScopedResource()
          defer { if accessing { url.stopAccessingSecurityScopedResource() } }
          guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 50_000_000
          else { throw PayeeLogoImage.ImportError.tooLarge }
          settings.imageData = try PayeeLogoImage.preparedData(from: Data(contentsOf: url))
          settings.source = .custom
        } catch { presentation.errorMessage = error.localizedDescription }
      }
      .onChange(of: presentation.selectedPhoto) { _, photo in
        guard let photo else { return }
        presentation.isImporting = true
        Task {
          defer { presentation.isImporting = false; presentation.selectedPhoto = nil }
          do {
            guard let data = try await photo.loadTransferable(type: Data.self)
            else { throw PayeeLogoImage.ImportError.invalidImage }
            settings.imageData = try PayeeLogoImage.preparedData(from: data)
            settings.source = .custom
          } catch { presentation.errorMessage = error.localizedDescription }
        }
      }
      .bowErrorAlert("Couldn’t load image", message: $presentation.errorMessage)
  }
}
