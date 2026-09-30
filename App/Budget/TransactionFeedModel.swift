import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TransactionFeedModel {
  private(set) var items: [TransactionListItem] = []
  private(set) var uncategorizedCount = 0
  private(set) var approvalCount = 0
  private(set) var isLoading = false
  private(set) var hasMore = false
  private(set) var didTrim = false
  private(set) var errorMessage: String?

  private var repository: TransactionPageRepository?
  private var container: ModelContainer?
  private var request = TransactionPageRepository.Request()
  private var nextCursor: TransactionPageRepository.Cursor?
  private var generation = 0

  func reload(
    container: ModelContainer, searchText: String, filter: TransactionFilter,
    scopedAccountID: UUID? = nil, scopedEnvelopeID: UUID? = nil,
    scopedPayeeKey: String? = nil,
    upperBound: Date? = nil, includeUncategorizedCount: Bool = true,
    includesBalanceAdjustments: Bool = false,
    includeApprovalCount: Bool = false
  ) async {
    generation += 1
    let currentGeneration = generation
    self.container = container
    if repository == nil { repository = TransactionPageRepository(modelContainer: container) }
    guard let repository else { return }
    var nextRequest = TransactionPageRepository.Request()
    nextRequest.searchText = searchText
    nextRequest.accountID = filter.accountID ?? scopedAccountID
    nextRequest.payeeKey = scopedPayeeKey
    nextRequest.needsAttentionOnly = filter.status == .needsAttention
    nextRequest.matchedOnly = filter.status == .matched
    nextRequest.includesBalanceAdjustments = includesBalanceAdjustments
    nextRequest.minimumAmountMinor = filter.minimumAmountMinor
    nextRequest.maximumAmountMinor = filter.maximumAmountMinor
    nextRequest.startDate = filter.startDate.map { Calendar.current.startOfDay(for: $0) }
    nextRequest.endDate = filter.endDate.flatMap {
      Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: $0))
    }
    if let upperBound { nextRequest.endDate = min(nextRequest.endDate ?? upperBound, upperBound) }
    switch filter.envelopeScope {
    case .all: nextRequest.envelopeID = scopedEnvelopeID
    case .uncategorized: nextRequest.uncategorizedOnly = true
    case .envelope(let id): nextRequest.envelopeID = id
    }
    request = nextRequest
    let requestToLoad = nextRequest
    items = []
    didTrim = false
    nextCursor = nil
    hasMore = false
    isLoading = true
    errorMessage = nil
    do {
      async let page = repository.page(requestToLoad)
      let loadedPage = try await page
      let loadedCount = includeUncategorizedCount
        ? try await repository.countUncategorized() : 0
      let loadedApprovalCount = includeApprovalCount
        ? try await repository.countNeedsApproval() : 0
      guard currentGeneration == generation, !Task.isCancelled else { return }
      items = loadedPage.items
      nextCursor = loadedPage.nextCursor
      hasMore = nextCursor != nil
      uncategorizedCount = loadedCount
      approvalCount = loadedApprovalCount
    } catch is CancellationError {
      return
    } catch {
      guard currentGeneration == generation else { return }
      errorMessage = error.localizedDescription
    }
    if currentGeneration == generation { isLoading = false }
  }

  func loadNext() async {
    guard !isLoading, let nextCursor, let repository else { return }
    let currentGeneration = generation
    isLoading = true
    var nextRequest = request
    nextRequest.cursor = nextCursor
    do {
      let page = try await repository.page(nextRequest)
      guard currentGeneration == generation, !Task.isCancelled else { return }
      items.append(contentsOf: page.items)
      if items.count > 480 {
        items.removeFirst(items.count - 400)
        didTrim = true
      }
      self.nextCursor = page.nextCursor
      hasMore = page.nextCursor != nil
    } catch is CancellationError {
      return
    } catch {
      guard currentGeneration == generation else { return }
      errorMessage = error.localizedDescription
    }
    if currentGeneration == generation { isLoading = false }
  }

  func returnToNewest(searchText: String, filter: TransactionFilter) async {
    guard let container else { return }
    await reload(container: container, searchText: searchText, filter: filter)
  }
}
