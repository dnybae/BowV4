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

    let messy = Data("""
      {
        "accounts": [{
          "id":"card","name":"Card","currency":"USD",
          "transactions":[
            {"id":"no-flag","posted":0,"amount":"-4.00","description":"Auth"},
            {"id":"null-description","posted":"1800000000","amount":-12.34,"description":null},
            {"posted":1800000000,"amount":"-1.00","description":"No id"},
            {"id":"memo","posted":1800000000,"amount":"-2.00","description":"Shop",
             "extra":{"memo":"Birthday gift","category":"5411"}}
          ]
        }]
      }
      """.utf8)
    let messyTransactions = try JSONDecoder().decode(SimpleFINAccountSet.self, from: messy)
      .accounts.first?.transactions ?? []
    precondition(messyTransactions.map(\.id) == ["no-flag", "null-description", "memo"])
    precondition(messyTransactions[0].isPending)
    precondition(!messyTransactions[1].isPending && messyTransactions[1].amountMinor == -1_234)
    precondition(messyTransactions[1].description.isEmpty)
    precondition(messyTransactions[2].memo == "Birthday gift")
    precondition(messyTransactions[2].extraJSON.flatMap { String(data: $0, encoding: .utf8) }
      == #"{"category":"5411","memo":"Birthday gift"}"#)
    let institutions = Data("""
      {"connections":[
        {"conn_id":"bank-login","name":"Bank Login","org_url":"https://www.chase.com/login"},
        {"conn_id":"broken","org_url":42}
      ],"accounts":[
        {"id":"modern","conn_id":"bank-login","name":"Checking","currency":"USD"},
        {"id":"legacy","name":"Savings","currency":"USD","org":{"name":"Legacy Bank","domain":"legacy.example"}},
        {"id":"website","name":"Card","currency":"USD","org":{"url":"https://www.bank.example/home"}},
        {"id":"missing","name":"Cash","currency":"USD"},
        {"id":"malformed","name":"Savings","currency":"USD","org":42}
      ]}
      """.utf8)
    let banks = try JSONDecoder().decode(SimpleFINAccountSet.self, from: institutions).accounts
    precondition(banks.count == 5)
    precondition(banks[0].institution?.logoDomain == "chase.com")
    precondition(banks[0].institution?.name == "Bank Login")
    precondition(banks[1].institution?.logoDomain == "legacy.example")
    precondition(banks[2].institution?.logoDomain == "bank.example")
    precondition(banks[3].institution == nil && banks[4].institution == nil)
    precondition(SimpleFINInstitution.domain(from: "not a domain") == nil)
    precondition(SimpleFINInstitution.domain(from: "file:///tmp/logo") == nil)
    print("SimpleFIN client checks passed")
  }
}
