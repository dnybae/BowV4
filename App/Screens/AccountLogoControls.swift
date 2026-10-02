import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct AccountLogoControls: View {
  @Binding var settings: AccountLogoSettings
  @Binding var isImporting: Bool
  var accountName: String
  var institutionName: String?
  var institutionDomain: String?
  @State private var showingFinder = false
  @State private var showingFiles = false
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var errorMessage: String?

  private var lookupName: String {
    if !settings.lookupName.isEmpty { return settings.lookupName }
    return institutionName ?? accountName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    Section {
      Button { showingFinder = true } label: {
        Label("Find logo", systemImage: "globe").labelStyle(.bowTile)
      }
      PhotosPicker(selection: $selectedPhoto, matching: .images) {
        Label("Choose photo", systemImage: "photo").labelStyle(.bowTile)
      }
      Button { showingFiles = true } label: {
        Label("Choose file", systemImage: "doc").labelStyle(.bowTile)
      }
      if isImporting { BowLoadingLabel("Loading image…") }
      if settings.source != .system {
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
    .sheet(isPresented: $showingFinder) {
      PayeeLogoFinderSheet(payeeName: lookupName,
                          domain: settings.source == .logoDev ? settings.domain : institutionDomain,
                          isBank: true) { domain in
        settings.lookupName = lookupName
        settings.domain = domain ?? ""
        settings.source = .logoDev
      }
    }
    .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.image]) { result in
      do {
        let url = try result.get()
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 50_000_000
        else { throw PayeeLogoImage.ImportError.tooLarge }
        settings.imageData = try PayeeLogoImage.preparedData(from: Data(contentsOf: url))
        settings.source = .custom
      } catch { errorMessage = error.localizedDescription }
    }
    .onChange(of: selectedPhoto) { _, photo in
      guard let photo else { return }
      isImporting = true
      Task {
        defer { isImporting = false; selectedPhoto = nil }
        do {
          guard let data = try await photo.loadTransferable(type: Data.self)
          else { throw PayeeLogoImage.ImportError.invalidImage }
          settings.imageData = try PayeeLogoImage.preparedData(from: data)
          settings.source = .custom
        } catch { errorMessage = error.localizedDescription }
      }
    }
    .bowErrorAlert("Couldn’t load image", message: $errorMessage)
  }
}
