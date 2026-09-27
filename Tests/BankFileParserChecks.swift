import Foundation

@main
struct BankFileParserChecks {
  static func main() throws {
    let parser = BankFileParser()
    let csv = """
    Date,Description,Debit,Credit,Memo
    9/15/2026,"Corner, Cafe",15.48,,Lunch
    9/16/2026,Payroll,,1,Paycheck
    """
    let table = try parser.csvTable(csv)
    let mapping = BankCSVMapping.suggested(for: table.headers)
    precondition(mapping.separateAmounts)
    let csvRows = try parser.csvRows(table, mapping: mapping)
    precondition(csvRows.count == 2)
    precondition(csvRows[0].payee == "Corner, Cafe")
    precondition(csvRows[0].amountMinor == -1_548)
    precondition(csvRows[1].amountMinor == 100)
    var reversed = mapping
    reversed.reverseSigns = true
    let reversedRows = try parser.csvRows(table, mapping: reversed)
    precondition(reversedRows[0].amountMinor == 1_548)

    let ofx = """
    OFXHEADER:100
    <OFX><BANKTRANLIST><STMTTRN>
    <DTPOSTED>20260915120000[-5:EST]
    <TRNAMT>-25.48
    <FITID>tx-123
    <NAME>Corner &amp; Cafe
    <MEMO>Lunch
    </STMTTRN></BANKTRANLIST></OFX>
    """
    let ofxRows = try parser.ofxRows(ofx)
    precondition(ofxRows.count == 1)
    precondition(ofxRows[0].externalID == "tx-123")
    precondition(ofxRows[0].payee == "Corner & Cafe")
    precondition(ofxRows[0].amountMinor == -2_548)

    let qif = """
    !Type:Bank
    D9/15/2026
    T-42.10
    PGrocery Store
    MWeekly shop
    ^
    """
    let qifRows = try parser.qifRows(qif, dateOrder: .monthDayYear)
    precondition(qifRows.count == 1)
    precondition(qifRows[0].payee == "Grocery Store")
    precondition(qifRows[0].amountMinor == -4_210)
    print("Bank file parser checks passed")
  }
}
