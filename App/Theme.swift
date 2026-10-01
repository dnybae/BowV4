// Theme.swift — Bow design system for SwiftUI (iOS 26)
// Source of truth for colors, type, spacing, radii and the signature components.
// See DESIGN.md for when to use each piece.
// Native first: never replace TabView, toolbars, sheets, List or Form with custom views.
// These are content components only. Navigation, toolbars, tab bar, sheets, buttons,
// forms, toggles and pickers must be the native SwiftUI / Liquid Glass versions.

import SwiftUI
import UIKit

// MARK: - Color tokens (light / dark)

extension Color {
    /// `highContrastLight` / `highContrastDark` are used when Increase Contrast is on.
    fileprivate init(light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1,
                     highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) {
        self.init(uiColor: UIColor { trait in
            let isHigh = trait.accessibilityContrast == .high
            let hex = trait.userInterfaceStyle == .dark
                ? (isHigh ? highContrastDark ?? dark : dark)
                : (isHigh ? highContrastLight ?? light : light)
            let a = trait.userInterfaceStyle == .dark ? darkAlpha : lightAlpha
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: a)
        })
    }
}

enum Bow {
    // Surfaces and text
    static let mist       = Color(light: 0xF1F3F7, dark: 0x0C0E13)   // screen background
    static let card       = Color(light: 0xFFFFFF, dark: 0x181B22)   // cards, list groups
    static let well       = Color(light: 0xE9ECF2, dark: 0x232731)   // ring tracks, inputs, icon discs
    static let line       = Color(light: 0xE2E5EC, dark: 0x2B303B, highContrastLight: 0xB9BECA, highContrastDark: 0x4A5161)   // separators
    static let ink        = Color(light: 0x141821, dark: 0xF1F3F8)   // primary text, money
    static let inkSoft    = Color(light: 0x596071, dark: 0xA3AAB9, highContrastLight: 0x3A404D, highContrastDark: 0xCDD2DC)   // secondary text
    static let inkFaint   = Color(light: 0x8B92A2, dark: 0x6E7585, highContrastLight: 0x5E6575, highContrastDark: 0x9AA1B0)   // chevrons, disabled (not for text)

    // Brand
    static let bow        = Color(light: 0x5B7FEA, dark: 0x7F9CF5)   // rings, selected tab, mark
    static let bowSolid   = Color(light: 0x4263D6, dark: 0x7F9CF5)   // toggles, selected chips, add button
    static let onBow      = Color(light: 0xFFFFFF, dark: 0x0C0E13)
    static let bowInk     = Color(light: 0x3D5FD0, dark: 0x9DB3FF, highContrastLight: 0x2A47A8, highContrastDark: 0xBFCDFF)   // links, tappable text
    static let bowTint    = Color(light: 0xE6ECFD, dark: 0x1D2744)   // selected rows, icon tiles

    // Primary button tint: .buttonStyle(.glassProminent).tint(Bow.button)
    static let button     = Color(light: 0x141821, dark: 0xF1F3F8)
    static let onButton   = Color(light: 0xFFFFFF, dark: 0x0C0E13)

    // Status: funded / needs / over
    static let funded     = Color(light: 0x3FA37A, dark: 0x5CC495)
    static let fundedInk  = Color(light: 0x1F7A53, dark: 0x6FD3A4, highContrastLight: 0x115C3B, highContrastDark: 0x97E5C0)
    static let fundedTint = Color(light: 0xE2F3EA, dark: 0x16302A)
    static let needs      = Color(light: 0xE6A23C, dark: 0xF0B45A)
    static let needsInk   = Color(light: 0x9A5F08, dark: 0xF3C27A, highContrastLight: 0x6F4300, highContrastDark: 0xF8D7A6)
    static let needsTint  = Color(light: 0xFBF0DC, dark: 0x33291A)
    static let over       = Color(light: 0xE5645A, dark: 0xF07C72)
    static let overInk    = Color(light: 0xBF3A30, dark: 0xFF9A91, highContrastLight: 0x952218, highContrastDark: 0xFFBDB7)
    static let overTint   = Color(light: 0xFCE6E3, dark: 0x3A1F1E)

    // Spacing and radii
    enum Space { static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s5: CGFloat = 20, s6: CGFloat = 24, s8: CGFloat = 32 }
    enum Radius { static let sm: CGFloat = 10, md: CGFloat = 16, lg: CGFloat = 24, xl: CGFloat = 32 }
}

// MARK: - Type (SF Pro Rounded for numbers and titles, SF Pro for text)
// Every style is built on a system text style so it follows Dynamic Type.
// Never use light, thin or ultralight weights. Secondary lines use .bowSubhead, not caption;
// .bowCaption is only for small badges.

extension Font {
    static let bowLargeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let bowTitle      = Font.system(.title2, design: .rounded, weight: .semibold)
    static let bowAmount     = Font.system(.body, design: .rounded, weight: .semibold)
    static let bowAmountSm   = Font.system(.subheadline, design: .rounded, weight: .semibold)
    static let bowHeadline   = Font.headline
    static let bowBody       = Font.body
    static let bowSubhead    = Font.subheadline
    static let bowFootnote   = Font.footnote
    static let bowCaption    = Font.caption.weight(.medium)
}
// Always add .monospacedDigit() to money. Sentence case everywhere.

// MARK: - Dynamic Type helpers

extension Bow {
    /// Icons, logos and rings grow with Dynamic Type but stop here so rows stay proportionate.
    static let maxGraphicScale: CGFloat = 1.6
}

/// The hero amount: 44pt rounded semibold at the default size, scaled like Large Title.
private struct BowHeroFont: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 44
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .semibold, design: .rounded))
    }
}

/// A symbol in a fixed tile (disc, rounded square) whose glyph and frame scale together.
private struct BowScaledIcon: ViewModifier {
    @ScaledMetric private var scale: CGFloat = 1
    var frame: CGFloat
    var glyph: CGFloat
    var weight: Font.Weight
    func body(content: Content) -> some View {
        let s = min(scale, Bow.maxGraphicScale)
        content
            .font(.system(size: glyph * s, weight: weight))
            .frame(width: frame * s, height: frame * s)
    }
}

// MARK: - Motion
// Every Bow animation goes through these so Reduce Motion is always respected.

extension Bow {
    /// The house spring for state changes: month changes, money moves, banners.
    static let motion = Animation.snappy
    /// Rings sweep a little softer than numbers roll.
    static let ringMotion = Animation.smooth

    /// The house spring, or no animation when Reduce Motion is on.
    static func motion(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : motion }
}

private struct BowAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animation: Animation
    var value: Value
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that turns itself off when Reduce Motion is on.
    func bowAnimation<Value: Equatable>(_ animation: Animation = Bow.motion, value: Value) -> some View {
        modifier(BowAnimation(animation: animation, value: value))
    }
}

extension View {
    func bowHeroFont() -> some View { modifier(BowHeroFont()) }

    /// Use for symbols that sit in a tile of a known size, instead of `.font(.system(size:))` plus `.frame`.
    func bowScaledIcon(frame: CGFloat, glyph: CGFloat, weight: Font.Weight = .semibold) -> some View {
        modifier(BowScaledIcon(frame: frame, glyph: glyph, weight: weight))
    }
}

// MARK: - Envelope status

enum EnvelopeState {
    case funded, needs, over, empty
    var ring: Color { switch self { case .funded: Bow.funded; case .needs: Bow.needs; case .over: Bow.over; case .empty: Bow.well } }
    var ink: Color  { switch self { case .funded: Bow.fundedInk; case .needs: Bow.needsInk; case .over: Bow.overInk; case .empty: Bow.inkSoft } }
    var tint: Color { switch self { case .funded: Bow.fundedTint; case .needs: Bow.needsTint; case .over: Bow.overTint; case .empty: Bow.well } }
    /// Shown inside rings when Differentiate Without Color is on.
    var glyph: String? { switch self { case .funded: "checkmark"; case .needs: "minus"; case .over: "exclamationmark"; case .empty: nil } }
    var sky: SkyMood { switch self { case .funded: .mint; case .needs: .amber; case .over: .coral; case .empty: .dawn } }
}

// MARK: - Small ring (rows, 28pt)

struct StatusRing: View {
    var fraction: Double
    var state: EnvelopeState
    var size: CGFloat = 28
    @ScaledMetric private var scale: CGFloat = 1
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    var body: some View {
        let side = size * min(scale, Bow.maxGraphicScale)
        ZStack {
            Circle().stroke(Bow.well, lineWidth: 3)
            Circle().trim(from: 0, to: state == .over ? 1 : fraction)
                .stroke(state.ring, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // With Differentiate Without Color, the ring's state also reads as a shape.
            if differentiateWithoutColor, let glyph = state.glyph {
                Image(systemName: glyph)
                    .font(.system(size: side * 0.4, weight: .bold))
                    .foregroundStyle(state.ink)
            }
        }
        .frame(width: side, height: side)
        .bowAnimation(Bow.ringMotion, value: fraction)
        .bowAnimation(Bow.ringMotion, value: state)
        .accessibilityHidden(true)
    }
}

// MARK: - Status pill ("Over $196.80", "Needs $80.00", "$330.00")

struct StatusPill: View {
    var text: String
    var state: EnvelopeState
    /// Optional symbol before the amount, e.g. a card for credit overspending.
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.bowAmountSm)
        .foregroundStyle(state.ink)
        .padding(.vertical, 5).padding(.horizontal, 10)
        .background(state.tint, in: Capsule())
        .bowAnimation(value: text)
        .bowAnimation(value: state)
    }
}

// MARK: - Sky background (atmosphere)

enum SkyMood {
    case dawn, mint, amber, coral
    var top: Color {
        switch self {
        case .dawn:  Color(light: 0xD6E0FF, dark: 0x1D2750)
        case .mint:  Color(light: 0xD3F0E2, dark: 0x16302A)
        case .amber: Color(light: 0xFFE7C2, dark: 0x33291A)
        case .coral: Color(light: 0xFFD9D3, dark: 0x3A1F1E)
        }
    }
    var warm: Color { Color(light: 0xFFE1D2, dark: 0x35264F) }
    var hill: Color {
        switch self {
        case .dawn:  Color(light: 0xC9D4F6, dark: 0x1A2140)
        case .mint:  Color(light: 0xC6E6D6, dark: 0x173028)
        case .amber: Color(light: 0xF6DDB4, dark: 0x2E2518)
        case .coral: Color(light: 0xF5CFC9, dark: 0x331D1C)
        }
    }
}

/// Place behind a hero screen: `.background(alignment: .top) { SkyBackground(mood: .dawn) }`
struct SkyBackground: View {
    var mood: SkyMood = .dawn
    var height: CGFloat = 520
    var showsTrail = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Bow.mist
            LinearGradient(colors: [mood.top.opacity(0.6), Bow.mist], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [mood.top, mood.top.opacity(0)], center: UnitPoint(x: 0.3, y: 0), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [mood.warm.opacity(0.9), mood.warm.opacity(0)], center: UnitPoint(x: 0.85, y: 0.08), startRadius: 0, endRadius: 280)
            if scheme == .dark { Stars().opacity(0.8) }
            Hills(color: mood.hill).frame(height: 200).frame(maxHeight: .infinity, alignment: .bottom)
            if showsTrail { Trail().stroke(.white.opacity(scheme == .dark ? 0.3 : 0.75), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [1, 6])) }
            LinearGradient(colors: [Bow.mist.opacity(0), Bow.mist], startPoint: .top, endPoint: .bottom)
                .frame(height: 140).frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: height)
        .ignoresSafeArea(edges: .top)
        .accessibilityHidden(true)
    }

    private struct Hills: View {
        var color: Color
        var body: some View {
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h * 0.25))
                        p.addCurve(to: CGPoint(x: w * 0.56, y: h * 0.07), control1: CGPoint(x: w * 0.18, y: 0.05 * h), control2: CGPoint(x: w * 0.38, y: 0.15 * h))
                        p.addCurve(to: CGPoint(x: w, y: h * 0.12), control1: CGPoint(x: w * 0.75, y: 0), control2: CGPoint(x: w * 0.9, y: 0.02 * h))
                        p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                    }.fill(color.opacity(0.55))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h * 0.45))
                        p.addCurve(to: CGPoint(x: w * 0.64, y: h * 0.3), control1: CGPoint(x: w * 0.23, y: 0.25 * h), control2: CGPoint(x: w * 0.44, y: 0.4 * h))
                        p.addCurve(to: CGPoint(x: w, y: h * 0.25), control1: CGPoint(x: w * 0.8, y: 0.25 * h), control2: CGPoint(x: w * 0.92, y: 0.3 * h))
                        p.addLine(to: CGPoint(x: w, y: h)); p.addLine(to: CGPoint(x: 0, y: h)); p.closeSubpath()
                    }.fill(color.opacity(0.7))
                }
            }
        }
    }
    private struct Trail: Shape {
        func path(in r: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: -10, y: r.height - 120))
            p.addQuadCurve(to: CGPoint(x: r.width + 10, y: r.height - 300), control: CGPoint(x: r.width * 0.5, y: r.height - 420))
            return p
        }
    }
    private struct Stars: View {
        var body: some View {
            Canvas { ctx, size in
                var rng = SeededRandom(seed: 7)
                for _ in 0..<46 {
                    let x = Double.random(in: 0...size.width, using: &rng)
                    let y = Double.random(in: 0...(size.height * 0.7), using: &rng)
                    let r = [0.6, 0.8, 1.0, 1.2].randomElement(using: &rng)!
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.5)))
                }
            }
        }
    }
}

struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}

// MARK: - Glow ring (hero)

/// Budget: fraction = share of cash assigned, color Bow.bow.
/// Envelope / card payment: fraction = progress to target, color = state.ring.
struct GlowRing<Center: View>: View {
    var fraction: Double
    var color: Color
    var highlight: Color = .white
    var size: CGFloat = 210
    @ViewBuilder var center: () -> Center
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let stroke = size * 0.085
        ZStack {
            Circle().fill(RadialGradient(colors: [color.opacity(0.22), color.opacity(0.1), .clear], center: .center, startRadius: 0, endRadius: size * 0.72))
                .frame(width: size * 1.45, height: size * 1.45)
            Circle().fill(.white.opacity(scheme == .dark ? 0.06 : 0.55))
                .overlay(Circle().stroke(.white.opacity(scheme == .dark ? 0.06 : 0.9), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 25, y: 20)
                .frame(width: size + 20, height: size + 20)
            Circle().stroke(.white.opacity(scheme == .dark ? 0.08 : 0.85), lineWidth: stroke).frame(width: size - stroke, height: size - stroke)
            Circle().trim(from: 0, to: fraction)
                .stroke(LinearGradient(colors: [highlight.mix(with: color, by: 0.45), color], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size - stroke, height: size - stroke)
                .shadow(color: color.opacity(0.55), radius: 10)
            Circle()
                .fill(scheme == .dark
                      ? LinearGradient(colors: [Color(red: 0.15, green: 0.17, blue: 0.23), Color(red: 0.10, green: 0.12, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing)
                      : LinearGradient(colors: [.white, Color(red: 0.957, green: 0.965, blue: 0.984)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: scheme == .dark ? .black.opacity(0.45) : color.opacity(0.18), radius: 15, y: 12)
                .frame(width: size * 0.7, height: size * 0.7)
            center().multilineTextAlignment(.center)
        }
        .frame(width: size * 1.45, height: size * 1.45)
        .bowAnimation(Bow.ringMotion, value: fraction)
        .bowAnimation(Bow.ringMotion, value: color)
    }
}

// MARK: - Pulse target (action and success moments)

struct PulseTarget<Content: View>: View {
    var color: Color = Bow.bow
    var size: CGFloat = 190
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.10))
            Circle().fill(color.opacity(0.18)).padding(size * 0.12)
            Circle()
                .fill(LinearGradient(colors: [.white, Color(red: 0.953, green: 0.965, blue: 0.992)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: color.opacity(0.35), radius: 15, y: 10)
                .padding(size * 0.25)
            content()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Native styling helpers
// Bow uses system controls everywhere. These helpers only apply tint, shape and background.

extension View {
    /// Main action: system Liquid Glass prominent button, tinted ink. One per screen.
    func bowPrimaryButton(size: ControlSize = .large) -> some View {
        self.buttonStyle(.glassProminent).tint(Bow.button)
            .foregroundStyle(Bow.onButton)
            .buttonBorderShape(.capsule).controlSize(size)
    }
    /// Secondary action: system Liquid Glass button.
    func bowSecondaryButton(size: ControlSize = .large) -> some View {
        self.buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(size)
    }
    /// Put on a List or Form so the Bow background (or a SkyBackground) shows through.
    func bowListBackground<Background: View>(@ViewBuilder _ background: () -> Background = { Bow.mist }) -> some View {
        self.listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background { background().ignoresSafeArea() }
    }
    /// Put on the app root once: system controls pick up the brand tint.
    func bowAppTint() -> some View { self.tint(Bow.bow) }
}
// Rows: use .listRowBackground(Bow.card). Hero sections: .listRowBackground(Color.clear).
// Toolbars, tab bar, sheets, pickers, toggles, menus: leave them native; they render Liquid Glass automatically.

// MARK: - Card container (only for non-list content such as the stats strip)

extension View {
    /// White card on mist. Light: soft shadow. Dark: no shadow.
    func bowCard(radius: CGFloat = Bow.Radius.lg) -> some View {
        self.background(Bow.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 6)
    }
}
