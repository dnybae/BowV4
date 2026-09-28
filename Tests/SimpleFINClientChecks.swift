import Foundation

@main
struct SimpleFINClientChecks {
  static func main() throws {
    let data = Data("""
      {
        "errlist": [{"code":"con.auth","msg":"Sign in to the bank"}],
        "accounts": [{
          "id":"checking","name":"Checking","conn_id":"bank-login", "currency":"USD",
          "transactions":[
            {"id":"one","posted":1800000000,"amount":"-25.48","description":"Cafe"},
            {"id":"two","posted":0,"transacted_at":1800000001,"amount":"10.00","description":"Hold","pending":true}
          ]
        }]
      }
      """.utf8)
    let result = try JSONDecoder().decode(SimpleFINAccountSet.self, from: data)
    precondition(result.messages == ["Sign in to the bank"])
    precondition(result.accounts.first?.remoteKey == "bank-login|checking")
    precondition(result.accounts.first?.transactions?.first?.amountMinor == -2_548)
    precondition(result.accounts.first?.transactions?.last?.amountMinor == 1_000)

    let invalidAmount = SimpleFINRemoteTransaction(
      id: "bad", posted: 1_800_000_000, amount: "1.001",
      description: "Bad precision", transactedAt: nil, pending: false
    )
    precondition(invalidAmount.amountMinor == nil)
    print("SimpleFIN client checks passed")
  }
}
