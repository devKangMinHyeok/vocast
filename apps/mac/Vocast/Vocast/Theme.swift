import SwiftUI

// MARK: - Color hex helper

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Semantic palette (dark appearance)
//
// Named by role, not by raw value, so a light appearance can be added later
// by swapping the values behind these names.

enum Palette {
    static let canvas = Color(hex: 0x07080A)          // window background
    static let surface = Color(hex: 0x0D0D0D)          // cards, sidebar, inspector
    static let surfaceElevated = Color(hex: 0x101111)  // inputs, selected rows, hover
    static let surfaceCard = Color(hex: 0x121212)      // raised cards

    static let hairline = Color(hex: 0x242728)         // 1px borders / dividers
    static let hairlineStrong = Color.white.opacity(0.16)

    static let ink = Color(hex: 0xF4F4F6)              // headings / primary text
    static let body = Color(hex: 0xCDCDCD)             // body text
    static let mute = Color(hex: 0x9C9C9D)             // secondary text
    static let ash = Color(hex: 0x6A6B6C)              // tertiary / mono meta
    static let stone = Color(hex: 0x434345)            // disabled, inactive waveform bars

    static let white = Color(hex: 0xFFFFFF)            // the only primary-action color
    static let onWhite = Color.black                   // text on white
    static let primaryPressed = Color(hex: 0xE8E8E8)

    static let accent = Color(hex: 0xF5732B)           // brand orange
    static let accentSoft = Color(hex: 0xFF9448)
    static let accentDeep = Color(hex: 0xE0561C)

    static let good = Color(hex: 0x59D499)             // pass dots, offline, completed
    static let attention = Color(hex: 0xF5732B)        // scorecard attention, running
    static let danger = Color(hex: 0xFF6161)           // destructive, live record dot

    // Brand gradient (logo mark, progress fills, hero glow) ~ linear-gradient(100deg)
    static let brandGradient = LinearGradient(
        colors: [accentSoft, accentDeep],
        startPoint: UnitPoint(x: 0.05, y: 0.0),
        endPoint: UnitPoint(x: 0.95, y: 1.0)
    )
}

// MARK: - Typography
//
// UI font: SF Pro (system). Mono font: SF Mono (system monospaced).

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// Named type roles from the scale (display 30/600 ... eyebrow 11 mono upper).
enum TypeRole {
    static let display = Font.ui(30, .semibold)
    static let title = Font.ui(19, .semibold)
    static let section = Font.ui(14.5, .semibold)
    static let body = Font.ui(14, .regular)
    static let label = Font.ui(12.5, .medium)
    static let monoMeta = Font.mono(11, .regular)
    static let eyebrow = Font.mono(11, .regular)
}

// MARK: - Radii & spacing

enum Radius {
    static let keycap: CGFloat = 4
    static let row: CGFloat = 6
    static let control: CGFloat = 8
    static let card: CGFloat = 12
    static let window: CGFloat = 12
}

enum Space {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
}

// MARK: - Reusable view modifiers

struct HairlineBorder: ViewModifier {
    var radius: CGFloat = Radius.card
    var color: Color = Palette.hairline
    var width: CGFloat = 1
    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: width)
        )
    }
}

extension View {
    /// 1px hairline border on a rounded rect (depth comes from the surface ladder, never shadow).
    func hairline(_ radius: CGFloat = Radius.card, color: Color = Palette.hairline, width: CGFloat = 1) -> some View {
        modifier(HairlineBorder(radius: radius, color: color, width: width))
    }

    /// A raised card: surface fill + hairline border, no drop shadow.
    func card(_ fill: Color = Palette.surface, radius: CGFloat = Radius.card, border: Color = Palette.hairline) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .hairline(radius, color: border)
    }
}

// Calm motion timing used across the app.
enum Motion {
    static let calm = Animation.easeInOut(duration: 0.15)
    static let progress = Animation.easeOut(duration: 0.3)
}
