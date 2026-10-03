import Foundation

/// The status shared by individual envelopes, card payments, and group summaries.
enum EnvelopeState {
  case funded, needs, over, empty
}
