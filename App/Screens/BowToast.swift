import SwiftUI

/// Brief, self-dismissing confirmations ("Moved $50.00 to Groceries"), shown as a Liquid Glass
/// capsule floating at the bottom of the screen. One center for the whole app, so a sheet can
/// confirm its save after it closes.
@MainActor
@Observable
final class BowToastCenter {
  private(set) var current: BowToast?
  /// Hosts in presentation order. Only the frontmost one shows the toast and plays its haptic.
  private(set) var hosts: [UUID] = []

  func show(_ toast: BowToast) {
    current = toast
    AccessibilityNotification.Announcement(toast.message).post()
  }

  func dismiss(_ toast: BowToast) {
    if current?.id == toast.id { current = nil }
  }

  fileprivate func register(_ host: UUID) {
    hosts.removeAll { $0 == host }
    hosts.append(host)
  }

  fileprivate func unregister(_ host: UUID) {
    hosts.removeAll { $0 == host }
  }
}

struct BowToast: Identifiable, Equatable {
  var id = UUID()
  var message: String
  var systemImage: String
  var feedback: Feedback = .success
  /// Puts back what the toast confirms. Shown as an Undo button; the toast stays up longer.
  var undo: UndoableChanges.Action? = nil

  static func == (lhs: BowToast, rhs: BowToast) -> Bool { lhs.id == rhs.id }

  /// Long enough to reach Undo, short enough not to linger.
  var duration: Duration { undo == nil ? .seconds(2.4) : .seconds(10) }

  enum Feedback: Equatable {
    /// A save or a goal reached.
    case success
    /// Money moved between envelopes.
    case moved
    /// Something removed: deleted, ignored or skipped.
    case removed
    /// Information only.
    case quiet
  }

  static func saved(_ message: String) -> BowToast {
    BowToast(message: message, systemImage: "checkmark.circle.fill")
  }

  static func deleted(_ message: String, undo: UndoableChanges.Action? = nil) -> BowToast {
    BowToast(message: message, systemImage: "trash.circle.fill", feedback: .removed, undo: undo)
  }

  static func moved(_ message: String) -> BowToast {
    BowToast(message: message, systemImage: "arrow.left.arrow.right.circle.fill", feedback: .moved)
  }
}

extension EnvironmentValues {
  @Entry var bowToasts: BowToastCenter? = nil
}

extension View {
  /// Shows the app's toasts over this view: the app root, and any sheet that stays open while it
  /// confirms something (Settings, for bank sync). Pass `clearsTabBar` on the tab view, so the
  /// toast floats above the tab bar rather than on it.
  func bowToastHost(clearsTabBar: Bool = false) -> some View {
    modifier(BowToastHost(clearsTabBar: clearsTabBar))
  }
}

private struct BowToastHost: ViewModifier {
  @Environment(\.bowToasts) private var center
  @State private var hostID = UUID()
  @State private var undoError: String?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var clearsTabBar: Bool
  /// Height of the floating tab bar, so the toast sits just above it.
  private static let tabBarClearance: CGFloat = 64

  private var isFrontmost: Bool { center?.hosts.last == hostID }
  private var visibleToast: BowToast? { isFrontmost ? center?.current : nil }

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .bottom) {
        if let toast = visibleToast {
          BowToastView(toast: toast, onDismiss: { center?.dismiss(toast) }, onUndoError: { undoError = $0 })
            .padding(.horizontal, Bow.Space.s4)
            // Just above the tab bar, so glass never sits on the bar's own glass controls.
            .padding(.bottom, clearsTabBar ? Self.tabBarClearance : Bow.Space.s4)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .task(id: toast.id) {
              try? await Task.sleep(for: toast.duration)
              if !Task.isCancelled { center?.dismiss(toast) }
            }
        }
      }
      .bowErrorAlert("Couldn’t Undo", message: $undoError)
    .bowAnimation(value: visibleToast?.id)
      .sensoryFeedback(trigger: center?.current?.id) { _, _ in
        // Moving a toast from a closing sheet to its parent must not replay its haptic.
        guard isFrontmost else { return nil }
        switch center?.current?.feedback {
        case .success: return .success
        case .moved: return .impact(weight: .light)
        case .removed: return .warning
        case .quiet, nil: return nil
        }
      }
      .onAppear { center?.register(hostID) }
      .onDisappear { center?.unregister(hostID) }
  }
}

private struct BowToastView: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  var toast: BowToast
  var onDismiss: () -> Void
  var onUndoError: (String) -> Void

  var body: some View {
    HStack(spacing: Bow.Space.s2) {
      Button(action: onDismiss) {
        Label {
          Text(toast.message)
            .font(.bowSubhead.weight(.semibold))
            .foregroundStyle(Bow.ink)
            .monospacedDigit()
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: toast.systemImage)
            .foregroundStyle(toast.feedback == .removed ? Bow.inkSoft : Bow.fundedInk)
        }
        .contentShape(.capsule)
      }
      .buttonStyle(.plain)
      .accessibilityHint("Dismisses the message")
      if let undo = toast.undo {
        Button("Undo") {
          do {
            try undo()
            onDismiss()
          } catch {
            onUndoError(error.localizedDescription)
          }
        }
        .font(.bowSubhead.weight(.semibold))
        .foregroundStyle(Bow.bowInk)
        .frame(minHeight: 44)
        .contentShape(.rect)
      }
    }
    .padding(.horizontal, Bow.Space.s4)
    .padding(.vertical, toast.undo == nil ? Bow.Space.s3 : Bow.Space.s1)
    .background {
      if reduceTransparency { Capsule().fill(Bow.card) }
    }
    .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: .capsule)
  }
}
