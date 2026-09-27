import Foundation

@main
struct PayeeRuleMatcherChecks {
  static func main() {
    let transportation = UUID()
    let groceries = UUID()
    let matcher = PayeeRuleMatcher()
    let uber = PayeeRuleItem(matchText: "Uber", envelopeID: transportation)
    precondition(matcher.envelopeID(for: " uber ", rules: [uber]) == transportation)
    precondition(matcher.envelopeID(for: "Uber Eats", rules: [uber]) == nil)
    precondition(matcher.envelopeID(for: "", rules: [uber]) == nil)
    let duplicate = PayeeRuleItem(matchText: "UBER", envelopeID: groceries)
    precondition(matcher.envelopeID(for: "Uber", rules: [uber, duplicate]) == nil)
    print("Payee rule matcher checks passed")
  }
}
