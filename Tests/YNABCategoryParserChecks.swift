import Foundation

@main
struct YNABCategoryParserChecks {
  static func main() throws {
    let csv = """
    \u{FEFF}Month,Category Group,Category,Assigned,Activity,Available
    Sep 2026,"🏡 Food, Home",🛒 Groceries,$100,$50,$50
    Oct 2026,"🏡 Food, Home",🛒 Groceries,$100,$50,$50
    Sep 2026,"🏡 Food, Home",Dining Out,$40,$10,$30
    Sep 2026,Credit Card Payments,Visa,$20,$0,$20
    Sep 2026,Future,🎯 Emergency Fund,$30,$0,$30
    """
    let preview = try YNABCategoryParser().parse(csv)
    precondition(preview.groups.count == 2)
    precondition(preview.envelopeCount == 3)
    precondition(preview.groups[0].name == "Food, Home")
    precondition(preview.groups[0].envelopes == ["Groceries", "Dining Out"])
    precondition(preview.groups[1].envelopes == ["Emergency Fund"])

    let tsv = """
    Month\tCategory Group\tCategory\tAssigned
    2026-09\tFood & Home\tGroceries\t100,00
    2026-10\tFood & Home\tGroceries\t20,00
    """
    let tabPreview = try YNABCategoryParser().parse(tsv)
    precondition(tabPreview.groups.count == 1)
    precondition(tabPreview.envelopeCount == 1)

    // YNAB writes Windows line endings, quoting every field.
    let crlf = "\"Month\",\"Category Group/Category\",\"Category Group\",\"Category\"\r\n"
      + "\"Oct 2026\",\"Bills: Rent\",\"Bills\",\"Rent\"\r\n"
      + "\"Oct 2026\",\"Bills: Phone\",\"Bills\",\"Phone\"\r\n"
    let crlfPreview = try YNABCategoryParser().parse(crlf)
    precondition(crlfPreview.groups.count == 1)
    precondition(crlfPreview.groups[0].envelopes == ["Rent", "Phone"])

    do {
      _ = try YNABCategoryParser().parse("Month,Name\nSep 2026,Groceries")
      preconditionFailure("missing headers should fail")
    } catch YNABImportError.missingColumns {
      // Expected.
    }
    print("YNAB category parser checks passed")
  }
}
