import SwiftUI

/// Brief, self-dismissing confirmations ("Moved $50.00 to Groceries"), shown as a Liquid Glass
/// capsule floating at the top of the screen. One center for the whole app, so a sheet can
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

  enum Feedback: Equatable {
    /// A save or a goal reached.
    case success
    /// Money moved between envelopes.
    case moved
    /// Information only.
    case quiet
  }

  static func saved(_ message: String) -> BowToast {
    BowToast(message: message, systemImage: "checkmark.circle.fill")
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
  /// confirms something (Settings, for bank sync).
  func bowToastHost() -> some View {
    modifier(BowToastHost())
  }
}

private struct BowToastHost: ViewModifier {
  @Environment(\.bowToasts) private var center
  @State private var hostID = UUID()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Height of an inline navigation bar, so the toast clears it.
  private static let navigationBarClearance: CGFloat = 58

  private var isFrontmost: Bool { center?.hosts.last == hostID }
  private var visibleToast: BowToast? { isFrontmost ? center?.current : nil }

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .top) {
        if let toast = visibleToast {
          BowToastView(toast: toast) { center?.dismiss(toast) }
            .padding(.horizontal, Bow.Space.s4)
            // Just below the navigation bar, so glass never sits on the bar's own glass controls.
            .padding(.top, Self.navigationBarClearance)
            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            .task(id: toast.id) {
              try? await Task.sleep(for: .seconds(2.4))
              if !Task.isCancelled { center?.dismiss(toast) }
            }
        }
      }
      .bowAnimation(value: visibleToast?.id)
      .sensoryFeedback(trigger: center?.current?.id) { _, _ in
        // Moving a toast from a closing sheet to its parent must not replay its haptic.
        guard isFrontmost else { return nil }
        switch center?.current?.feedback {
        case .success: return .success
        case .moved: return .impact(weight: .light)
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

  var body: some View {
    Button(action: onDismiss) {
      Label {
        Text(toast.message)
          .font(.bowSubhead.weight(.semibold))
          .foregroundStyle(Bow.ink)
          .monospacedDigit()
          .fixedSize(horizontal: false, vertical: true)
      } icon: {
        Image(systemName: toast.systemImage)
          .foregroundStyle(Bow.fundedInk)
      }
      .padding(.horizontal, Bow.Space.s4)
      .padding(.vertical, Bow.Space.s3)
      .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .background {
      if reduceTransparency { Capsule().fill(Bow.card) }
    }
    .glassEffect(reduceTransparency ? .identity : .regular.interactive(), in: .capsule)
    .accessibilityHint("Dismisses the message")
  }
}
