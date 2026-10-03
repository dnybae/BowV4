import Foundation

/// Bundled legal text for Bow's current features. Keep these disclosures aligned with data flows.
enum LegalDocument: String, Identifiable {
  case privacy
  case terms

  static let effectiveDate = "October 2, 2026"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .privacy: "Privacy Policy"
    case .terms: "Terms of Use"
    }
  }

  var relatedDocument: LegalDocument { self == .privacy ? .terms : .privacy }

  var sections: [Section] {
    switch self {
    case .privacy: Self.privacySections
    case .terms: Self.termsSections
    }
  }

  struct Section: Identifiable {
    var title: String
    var body: String
    var links: [Reference] = []
    var id: String { title }
  }

  struct Reference: Identifiable {
    var title: String
    var url: URL
    var id: URL { url }
  }

  private static let simpleFINPrivacy = Reference(
    title: "SimpleFIN Privacy Policy",
    url: URL(string: "https://beta-bridge.simplefin.org/info/privacy")!
  )
  private static let logoDevPrivacy = Reference(
    title: "Logo.dev Privacy Policy",
    url: URL(string: "https://www.logo.dev/legal/privacy")!
  )
  private static let applePrivacy = Reference(
    title: "Apple Privacy Policy",
    url: URL(string: "https://www.apple.com/legal/privacy/")!
  )
  private static let appleEULA = Reference(
    title: "Apple Standard License Agreement",
    url: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
  )

  private static let privacySections: [Section] = [
    Section(title: "About this policy", body: """
      This Privacy Policy describes how Bow (also called Bow Budget), a personal budgeting app \
      provided by Daniel Baeza (“we,” “us,” or “the developer”), handles information in the current \
      version of the app. Contact us at \(SupportLink.address) with privacy questions.
      """),
    Section(title: "The short version", body: """
      Bow stores and processes your budget on your iPhone. No Bow account or registration is \
      required, and your budget is not uploaded to a server operated by the developer. Bow does \
      not display ads or include analytics or tracking SDKs. We do not sell your \
      personal information.

      Some features contact other services: optional bank sync uses SimpleFIN, and online \
      merchant and bank logos use logo.dev. Device backups, Siri, links you open, files you \
      share, and messages you send to support can also involve information leaving your device, \
      as described below.
      """),
    Section(title: "Information stored on your device", body: """
      Bow uses the information you enter or import to calculate budgets, balances, spending, \
      schedules, and forecasts. This includes your budget name, accounts, balances, groups, \
      envelopes, allocations, transactions, payees, notes, schedules, reconciliation records, \
      imported bank details, and custom images. Preferences are also saved on your device.

      Bank CSV, OFX, and QIF files, YNAB exports, and Bow backups you select are processed on \
      your device. Bow does not upload those files to the developer. Your file or photo provider \
      may download a selected item from its own cloud storage.

      When you choose an image using the system photo or file picker, Bow receives the selected \
      image and stores a resized copy for the account or payee. Bow does not upload that image \
      to logo.dev or the developer, and does not request access to your entire photo library.
      """),
    Section(title: "Optional SimpleFIN bank sync", body: """
      Connecting a bank requires a separate SimpleFIN Bridge account. You authorize access \
      through that service and give Bow a setup token. Bow exchanges it directly with SimpleFIN \
      for an access credential, stored in your device’s Keychain. Bow does not receive your bank \
      login password.

      Bow uses the credential to request account and institution details, balances, and \
      transaction history, including descriptions, dates, amounts, pending status, and other \
      details supplied by the bank. Downloaded information is stored in your local budget. Bow \
      does not send your manually entered budget, envelope assignments, or notes to SimpleFIN. \
      These requests reveal network information such as your IP address and request times to \
      the service. No bank data passes through a server operated by the developer.

      With Automatic sync enabled, requests can occur while you use Bow and during background \
      refresh when iOS permits. Turn it off in Settings › SimpleFIN bank sync to stop automatic \
      requests; Sync now remains available. Disconnect removes Bow’s saved credential and stops \
      future sync, but keeps previously imported budget data. To revoke provider access, delete \
      provider data, or cancel its service, use SimpleFIN’s own controls. SimpleFIN, its bank \
      connection providers, and your financial institution handle information under their own policies.
      """, links: [simpleFINPrivacy]),
    Section(title: "Online merchant and bank logos", body: """
      Merchant logos are enabled by default. Automatic image requests to logo.dev include a \
      business’s website domain, which may identify a merchant or financial institution in your \
      budget. Opening Find logo also requests a preview: it sends the website domain, or the \
      payee or bank name when no domain is available. This can happen before you choose Use logo.

      These requests do not include transaction amounts, balances, account numbers, notes, or \
      your full transaction history. Logo.dev receives your IP address, the lookup, and request \
      times, and handles them under its own policy. Downloaded images may be cached on your device.

      Turn off Settings › Merchant logos to stop automatic logo requests. Find logo still makes \
      online requests when opened, even with that setting off. To avoid logo.dev requests, keep \
      the setting off and use default icons or your own images instead of Find logo.
      """, links: [logoDevPrivacy]),
    Section(title: "Apple services and external links", body: """
      Bow does not provide its own cloud budget sync. Depending on your device backup settings, \
      Bow’s local data may be included in iCloud or computer backups. Apple handles its services \
      under its own terms and privacy policy.

      If you use Siri or Shortcuts, Bow makes account and envelope names available for selection, \
      uses the transaction details you supply, and returns transaction confirmations or envelope \
      balances to the system. Apple handles Siri requests under its own privacy practices; \
      other actions you add to a shortcut may receive information you pass to them.

      Bow has no built-in analytics reporting service. If you choose to share analytics with \
      app developers through iOS, Apple may provide diagnostic reports or aggregated usage \
      information to the developer. You can manage this in iPhone Settings › Privacy & Security › \
      Analytics & Improvements.

      Opening a payee website or another external link contacts that website through your \
      browser. Using a payee’s web search sends its name to Google. Those websites and your \
      browser handle information under their own policies.
      """, links: [applePrivacy]),
    Section(title: "Exports and backups", body: """
      Settings › Export or restore creates a Bow backup and a CSV transactions spreadsheet \
      locally, then lets you choose where to save or share them. These files contain sensitive \
      financial information and are not password-protected by Bow. Anyone with access to a \
      copy may be able to read it. Choose storage locations and recipients carefully.

      Bow backups include budget data, imported bank records, and custom images, but exclude \
      the SimpleFIN Keychain credential. Restoring a backup replaces the current budget and \
      requires reconnecting bank sync. Copies you save or share are handled by the recipients \
      and storage services you choose.
      """),
    Section(title: "Support messages", body: """
      If you email \(SupportLink.address), the developer receives your email address, your \
      message, and any attachments you choose to send. The feedback link also prepares a \
      subject containing Bow’s version. Email providers process the message to deliver it.

      We use this information to respond to your request and troubleshoot issues, and keep \
      correspondence as needed for those purposes and applicable legal obligations. Do not \
      send bank passwords, SimpleFIN setup tokens or access credentials, or financial records \
      that are unnecessary for your request.
      """),
    Section(title: "Retention, deletion, and your choices", body: """
      Local budget information stays on your device until you delete it, replace the budget \
      through restore, or delete the app. Offloading Bow keeps its data; deleting it removes its \
      local app data. Keychain credentials can remain after app deletion, so disconnect SimpleFIN \
      in Bow before deleting the app and revoke its access token with SimpleFIN.

      Deleting Bow does not delete device backups, exported files, data held by SimpleFIN or \
      other providers, or support correspondence. Manage those copies and accounts separately. \
      The developer cannot retrieve or erase a budget stored only on your device.

      You can view and edit your data in Bow and export it from Settings › Export or restore. \
      To ask about information held by the developer or request access, correction, or deletion, \
      contact \(SupportLink.address). We will handle requests as required by applicable law. \
      Requests about a third-party service’s records should be directed to that service.
      """),
    Section(title: "Location and security", body: """
      Bow does not request device location access or collect precise GPS location. Services \
      receiving online requests may infer an approximate location from your IP address.

      Bow uses iOS app storage protections, the Keychain for bank sync credentials, and HTTPS \
      for bank and logo requests. No device, storage system, or transmission can be guaranteed \
      completely secure. Protect your device and its passcode, and safeguard any exported files \
      and backups. Local storage does not eliminate the risk of unauthorized access or data loss.
      """),
    Section(title: "Children", body: """
      Bow is not directed to children under 13. The developer does not knowingly collect \
      personal information from children under 13. If you believe a child has sent personal \
      information to the developer, contact \(SupportLink.address) so we can address it and \
      delete it as required by law. Third-party services may have their own age requirements.
      """),
    Section(title: "Changes to this policy", body: """
      We may update this policy as Bow’s features or privacy practices change. The updated \
      policy will appear in Settings with a new effective date. We will provide additional \
      notice or request consent when required by applicable law. This policy explains our \
      practices; it does not waive your privacy rights.
      """)
  ]

  private static let termsSections: [Section] = [
    Section(title: "About these terms", body: """
      These Terms of Use apply to Bow (also called Bow Budget), provided by Daniel Baeza \
      (“we,” “us,” or “the developer”). By using Bow, you agree to these terms. If you do not \
      agree, stop using the app. You must be legally able to accept these terms or have the \
      permission of a parent or guardian where required.

      These terms describe Bow’s service and supplement Apple’s Standard Licensed Application \
      End User License Agreement, which governs the app license for App Store downloads. \
      Nothing here limits rights that cannot be excluded under applicable law.
      """, links: [appleEULA]),
    Section(title: "What Bow does", body: """
      Bow helps you organize accounts, transactions, envelopes, schedules, and budgets, and \
      understand your spending. It is a recordkeeping and planning tool, not a bank, payment \
      service, or financial adviser. Recording transfers, payments, allocations, or scheduled \
      transactions in Bow does not move money, pay a bill, or submit instructions to your bank.

      Balances, targets, forecasts, and insights are estimates based on the information available \
      to the app. They are not financial, investment, tax, or legal advice, and do not guarantee \
      a financial outcome. You are responsible for your financial decisions and actual payments.
      """),
    Section(title: "Your data and responsibilities", body: """
      You retain rights to the budget information and images you provide. Only enter or import \
      information you are authorized to use, and only connect accounts you are authorized to access.

      Review entries, imports, suggested matches, scheduled transactions, and calculations for \
      accuracy. Bank information may be incomplete, delayed, duplicated, or incorrect. Check \
      important balances and payments against your financial institution’s records.

      Keep your device and access credentials secure. Your budget is stored locally, so maintain \
      copies using Settings › Export or restore and appropriate device backups. Exported files \
      contain financial information and are not password-protected by Bow. Restoring replaces \
      the current budget. Deleting the app, losing a device, or a storage failure may cause data \
      loss; the developer cannot recover a budget stored only on your device.
      """),
    Section(title: "Privacy", body: """
      Bow’s Privacy Policy, available in Settings, explains local storage, bank sync, online \
      logos, Apple services, exports, and support messages. Third-party services handle \
      information under their own privacy policies.
      """),
    Section(title: "Optional services and connectivity", body: """
      Core manual budgeting works without an internet connection. Bank sync, online logos, \
      external websites, and other online services require connectivity. Your provider’s data \
      charges may apply.

      Bank sync uses a separate SimpleFIN Bridge account and may require payment to SimpleFIN. \
      Its pricing, billing, cancellation, supported institutions, and access rules are set by \
      SimpleFIN. Bow is not affiliated with or endorsed by your bank or SimpleFIN. Sync timing \
      depends on the bank, SimpleFIN, network access, and iOS background refresh; timely or \
      uninterrupted updates are not guaranteed. Disconnecting in Bow does not cancel a \
      SimpleFIN subscription or revoke its provider-side access token.

      Online logos are provided by logo.dev and may be unavailable or inaccurate. A displayed \
      logo does not imply affiliation or endorsement. Third-party services are governed by \
      their own terms and may change, impose limits, or stop operating. To the extent permitted \
      by law, the developer is not responsible for those services or the information they supply.
      """, links: [
        Reference(title: "SimpleFIN Terms of Use", url: URL(string: "https://beta-bridge.simplefin.org/info/terms")!),
        Reference(title: "Logo.dev Terms of Service", url: URL(string: "https://www.logo.dev/legal/terms")!)
      ]),
    Section(title: "Pricing and purchases", body: """
      This version of Bow has no in-app subscriptions, free trials, or lifetime access purchases. \
      Any price for downloading the app is shown by the App Store before purchase. Separate \
      SimpleFIN charges are paid to that service and are not purchases from Bow.

      If Bow introduces paid features in a future version, their price, billing period, renewal \
      conditions, and any trial terms will be disclosed before you purchase. These terms do not \
      authorize an undisclosed charge.
      """),
    Section(title: "License and intellectual property", body: """
      The app is licensed for use under the applicable Apple license agreement. Bow’s software, \
      design, and branding belong to the developer or their licensors; third-party trademarks \
      and logos belong to their respective owners. These terms do not transfer ownership of \
      the app or grant rights to use another party’s branding.

      Do not redistribute, resell, modify, reverse engineer, or create derivative versions of \
      the app except where permitted by applicable law or the licenses of included components. \
      Do not use Bow to violate the law, infringe others’ rights, or interfere with connected services.
      """),
    Section(title: "Updates and availability", body: """
      Features and supported operating system versions may change. Updates may be needed for \
      compatibility, security, or continued access to connected services. We do not guarantee \
      that every feature will remain available indefinitely or work on every future device or \
      operating system.

      We may discontinue the app or a feature, subject to applicable law and any obligations \
      associated with purchases. Keep backups of information you want to retain. You may stop \
      using Bow at any time; separately manage third-party subscriptions and access permissions.
      """),
    Section(title: "Disclaimer of warranties", body: """
      To the extent permitted by applicable law, Bow is provided “as is” and “as available,” \
      without warranties of accuracy, uninterrupted operation, fitness for a particular purpose, \
      or freedom from errors or data loss. Nothing in these terms excludes a warranty or \
      consumer protection that applicable law requires.
      """),
    Section(title: "Limitation of liability", body: """
      To the extent permitted by applicable law, the developer is not liable for indirect, \
      incidental, special, or consequential losses arising from use of or inability to use Bow, \
      including lost profits, lost data, or losses arising from reliance on budget estimates \
      or third-party information.

      These limitations do not exclude liability that cannot legally be excluded, or reduce \
      your mandatory consumer rights. The applicable Apple license agreement may contain \
      additional provisions governing the app license.
      """),
    Section(title: "Changes to these terms", body: """
      Updated terms will appear in Settings with a new effective date. We will provide \
      additional notice or seek agreement when required by applicable law. Changes apply \
      prospectively and do not remove rights that the law protects. If you do not agree to \
      updated terms, stop using Bow.

      Questions about these terms can be sent to \(SupportLink.address).
      """)
  ]
}
