import SwiftUI

/// Warm neutral-grey palette in Craft's own idiom: soft charcoal surfaces
/// (never pure black), cream/off-white ink, gentle low-contrast elevation
/// via shadow rather than heavy borders.
enum Theme {
    static let bg        = Color(hex: 0x1C1C1E)   // window background
    static let panel     = Color(hex: 0x212123)   // sidebar
    static let panelHi   = Color(hex: 0x2C2C2F)   // hovered / raised
    static let card      = Color(hex: 0x27272A)   // task group blocks
    static let stroke    = Color(hex: 0x3A3A3E)   // hairline borders
    static let textHi    = Color(hex: 0xF5F1E8)   // headings — warm off-white
    static let text      = Color(hex: 0xD6D2C6)   // body text, warm grey
    static let textLo    = Color(hex: 0x9C988D)   // secondary
    static let textFaint = Color(hex: 0x6B675E)   // tertiary
    static let accent    = Color(hex: 0xF0EBDE)   // cream accent — fills, active chips
    static let chipBg    = Color(hex: 0x323235)
    static let danger    = Color(hex: 0xECE6D6)   // "overdue" — bright cream, not red
    static let shadow    = Color.black.opacity(0.35)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Soft, low, wide shadow — the gentle "paper lifted off the desk" elevation
/// Craft uses on cards and panels, instead of a hard drop shadow.
extension View {
    func craftShadow(radius: CGFloat = 14, y: CGFloat = 5) -> some View {
        shadow(color: Theme.shadow, radius: radius, x: 0, y: y)
    }
}

struct Chip: View {
    let text: String
    var icon: String? = nil
    var active: Bool = false
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .medium)) }
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(active ? Theme.accent : Theme.chipBg)
        .foregroundColor(active ? Color.black : Theme.textLo)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(active ? Color.clear : Theme.stroke, lineWidth: 1))
    }
}
