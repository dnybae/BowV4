import SwiftUI

/// Bow's privacy policy and terms of use, readable without a connection.
struct LegalDocumentScreen: View {
  var document: LegalDocument

  var body: some View {
    List {
      Section {
        Text("Effective \(LegalDocument.effectiveDate)")
          .font(.bowSubhead)
          .foregroundStyle(Bow.inkSoft)
          .listRowBackground(Color.clear)
      }
      ForEach(document.sections) { section in
        Section {
          Text(section.body)
            .font(.bowBody)
            .foregroundStyle(Bow.ink)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
          ForEach(section.links) { reference in
            Link(reference.title, destination: reference.url)
              .font(.bowBody)
              .fixedSize(horizontal: false, vertical: true)
          }
        } header: {
          Text(section.title)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
        }
        .listRowBackground(Bow.card)
      }
      Section("Contact") {
        Link(destination: SupportLink.email(subject: "Question about Bow’s \(document.title.lowercased())")) {
          Label(SupportLink.address, systemImage: "envelope")
        }
      }
      .listRowBackground(Bow.card)
      Section {
        NavigationLink(document.relatedDocument.title) {
          LegalDocumentScreen(document: document.relatedDocument)
        }
      }
      .listRowBackground(Bow.card)
    }
    .bowListBackground()
    .navigationTitle(document.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}
