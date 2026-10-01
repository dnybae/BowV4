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

  private var isFrontmost: Bool { center?.hosts.last == hostID }
  private var visibleToast: BowToast? { isFrontmost ? center?.current : nil }

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .top) {
        if let toast = visibleToast {
          BowToastView(toast: toast) { center?.dismiss(toast) }
            .padding(.horizontal, Bow.Space.s4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: toast.id) {
              try? await Task.sleep(for: .seconds(2.4))
              if !Task.isCancelled { center?.dismiss(toast) }
            }
        }
      }
      .bowAnimation(value: visibleToast?.id)
      .sensoryFeedback(trigger: visibleToast?.id) { _, _ in
        switch visibleToast?.feedback {
        case .success: .success
        case .moved: .impact(weight: .light)
        case .quiet, nil: nil
        }
      }
      .onAppear { center?.register(hostID) }
      .onDisappear { center?.unregister(hostID) }
  }
}

private struct BowToastView: View {
  var toast: BowToast
  var onDismiss: () -> Void

  var body: some View {
    Button(action: onDismiss) {
      Label {
        Text(toast.message)
          .font(.bowSubhead.weight(.semibold))
          .foregroundStyle(Bow.ink)
          .monospacedDigit()
          .lineLimit(2)
      } icon: {
        Image(systemName: toast.systemImage)
          .foregroundStyle(Bow.fundedInk)
      }
      .padding(.horizontal, Bow.Space.s4)
      .padding(.vertical, Bow.Space.s3)
      .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .capsule)
    .accessibilityHint("Dismisses the message")
  }
}
