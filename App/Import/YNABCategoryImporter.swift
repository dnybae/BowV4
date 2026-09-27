import Foundation
import SwiftData

struct YNABCategoryImporter {
  func save(
    _ preview: YNABCategoryPreview,
    existingGroups: [BudgetGroup],
    existingEnvelopes: [BudgetEnvelope],
    in context: ModelContext
  ) throws -> (groups: Int, envelopes: Int) {
    var groups = existingGroups
    var envelopes = existingEnvelopes
    var addedGroups = 0
    var addedEnvelopes = 0
    for sourceGroup in preview.groups {
      let group: BudgetGroup
      if let match = groups.first(where: {
        $0.name.localizedCaseInsensitiveCompare(sourceGroup.name) == .orderedSame
      }) {
        group = match
      } else {
        group = BudgetGroup(name: sourceGroup.name, sortOrder: groups.count)
        context.insert(group)
        groups.append(group)
        addedGroups += 1
      }
      for name in sourceGroup.envelopes {
        let exists = envelopes.contains {
          $0.groupID == group.id
            && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard !exists else { continue }
        let order = envelopes.filter { $0.groupID == group.id }.count
        let envelope = BudgetEnvelope(
          groupID: group.id,
          name: name,
          symbol: symbol(for: name),
          sortOrder: order
        )
        context.insert(envelope)
        envelopes.append(envelope)
        addedEnvelopes += 1
      }
    }
    try context.save()
    return (addedGroups, addedEnvelopes)
  }

  private func symbol(for name: String) -> String {
    let lower = name.lowercased()
    if lower.contains("grocer") || lower.contains("market") { return "cart.fill" }
    if lower.contains("home") || lower.contains("rent") || lower.contains("mortgage") {
      return "house.fill"
    }
    if lower.contains("dining") || lower.contains("restaurant") || lower.contains("coffee") {
      return "fork.knife"
    }
    if lower.contains("car") || lower.contains("transport") || lower.contains("fuel") {
      return "car.fill"
    }
    if lower.contains("health") || lower.contains("medical") { return "heart.fill" }
    if lower.contains("saving") || lower.contains("emergency") { return "banknote.fill" }
    if lower.contains("shop") || lower.contains("clothing") { return "bag.fill" }
    return "square.grid.2x2.fill"
  }
}
