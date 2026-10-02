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
        Section(section.title) {
          Text(section.body)
            .font(.bowBody)
            .foregroundStyle(Bow.ink)
            .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Bow.card)
      }
      Section {
        Link(destination: SupportLink.email(subject: "Question about Bow’s \(document.title.lowercased())")) {
          Label("Questions? \(SupportLink.address)", systemImage: "envelope")
        }
      }
      .listRowBackground(Bow.card)
    }
    .bowListBackground()
    .navigationTitle(document.title)
    .navigationBarTitleDisplayMode(.inline)
  }
}

enum LegalDocument: String, Identifiable {
  case privacy
  case terms

  static let effectiveDate = "October 2026"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .privacy: "Privacy Policy"
    case .terms: "Terms of Use"
    }
  }

  struct Section: Identifiable {
    var title: String
    var body: String
    var id: String { title }
  }

  var sections: [Section] {
    switch self {
    case .privacy: Self.privacySections
    case .terms: Self.termsSections
    }
  }

  private static let privacySections: [Section] = [
    Section(title: "The short version", body: """
      Your budget lives on your iPhone. Bow has no accounts to sign up for, no analytics, \
      no advertising and no tracking. We don’t collect, sell or see your financial data.
      """),
    Section(title: "What stays on your iPhone", body: """
      Your accounts, balances, envelopes, transactions, payees, schedules, notes and settings \
      are stored only on this device. Files you import (bank CSV, OFX and QIF files, and YNAB \
      exports) are read on your iPhone and never uploaded. If you turn on iCloud Backup or \
      Finder backups, Apple includes Bow’s data in those backups under Apple’s terms.
      """),
    Section(title: "Bank sync with SimpleFIN (optional)", body: """
      If you connect a bank, Bow talks directly to SimpleFIN Bridge, a separate service you sign \
      up for and pay for yourself. The access link SimpleFIN gives Bow is kept in your iPhone’s \
      Keychain. Bow downloads your account names, balances and transactions from SimpleFIN onto \
      your iPhone; nothing passes through Bow’s servers, because there aren’t any. SimpleFIN’s \
      own privacy policy covers what SimpleFIN and your bank do with your data.
      """),
    Section(title: "Merchant logos (optional)", body: """
      To show store and bank logos, Bow asks logo.dev for an image using a business’s website \
      domain, such as starbucks.com. When you search for a logo yourself, the name you type is \
      sent instead. These requests never include amounts, balances, account details or notes, \
      but like any web request they reveal your device’s IP address to logo.dev. Turn off \
      Settings › Merchant logos to stop them.
      """),
    Section(title: "Siri and Shortcuts", body: """
      When you use Bow’s shortcuts, Apple handles your voice request under its own privacy \
      policy; Bow records the transaction on your iPhone.
      """),
    Section(title: "Exports and deleting your data", body: """
      Settings › Export data creates files on your iPhone that you choose where to send. \
      Deleting Bow removes all of its data from this iPhone.
      """),
    Section(title: "Children", body: """
      Bow isn’t directed to children under 13, and we don’t knowingly collect anyone’s personal \
      information.
      """),
    Section(title: "Changes", body: """
      If this policy changes, the new version will appear here with a new effective date.
      """)
  ]

  private static let termsSections: [Section] = [
    Section(title: "Using Bow", body: """
      Bow is a personal budgeting tool. You may use it for your own personal, non-commercial \
      budgeting under these terms and Apple’s Licensed Application End User License Agreement.
      """),
    Section(title: "Not financial advice", body: """
      Bow helps you plan with the money you have. It isn’t a bank, doesn’t move money and \
      doesn’t give financial, tax, legal or investment advice. Decisions about your money are yours.
      """),
    Section(title: "Your data and its accuracy", body: """
      Your budget is stored on your device, and you’re responsible for keeping backups, for \
      example with Settings › Export data. Balances and budgets are only as accurate as the \
      transactions entered or imported. Always check important figures against your bank.
      """),
    Section(title: "Third-party services", body: """
      Bank sync uses SimpleFIN, and merchant logos use logo.dev. Those services have their own \
      terms, and Bow isn’t responsible for their availability or for the data your bank provides.
      """),
    Section(title: "No warranty", body: """
      Bow is provided “as is” without warranties of any kind, to the extent the law allows.
      """),
    Section(title: "Limitation of liability", body: """
      To the extent the law allows, Bow’s developer isn’t liable for indirect or consequential \
      losses, or for losses from decisions made using the app.
      """),
    Section(title: "Changes", body: """
      These terms may be updated with new versions of Bow. The current version is always here.
      """)
  ]
}
