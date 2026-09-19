import SwiftUI

/// Same warm neutral-grey palette as the Mac app's Theme.swift, ported
/// cross-platform (UIKit instead of AppKit for the hex round-trip).
enum Theme {
    static let bg        = Color(hex: 0x1C1C1E)
    static let panel     = Color(hex: 0x212123)
    static let panelHi   = Color(hex: 0x2C2C2F)
    static let card      = Color(hex: 0x27272A)
    static let stroke    = Color(hex: 0x3A3A3E)
    static let textHi    = Color(hex: 0xF5F1E8)
    static let text      = Color(hex: 0xD6D2C6)
    static let textLo    = Color(hex: 0x9C988D)
    static let textFaint = Color(hex: 0x6B675E)
    static let accent    = Color(hex: 0xF0EBDE)
    static let chipBg    = Color(hex: 0x323235)
    static let danger    = Color(hex: 0xECE6D6)
    static let destructive = Color(hex: 0xE5484D)
    static let shadow    = Color.black.opacity(0.35)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    #if canImport(UIKit)
    /// Lowercase 6-digit hex string (no leading "#") — mirrors the Mac
    /// app's Theme.swift so tag colors round-trip identically.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
    #endif
}

extension View {
    func craftShadow(radius: CGFloat = 14, y: CGFloat = 5) -> some View {
        shadow(color: Theme.shadow, radius: radius, x: 0, y: y)
    }
}

struct Chip: View {
    let text: String
    var icon: String? = nil
    var active: Bool = false
    var small: Bool = false
    var body: some View {
        HStack(spacing: small ? 3 : 4) {
            if let icon { Image(systemName: icon).font(.system(size: small ? 8 : 9, weight: .medium)) }
            Text(text).font(.system(size: small ? 10 : 11, weight: .medium, design: .rounded))
        }
        .padding(.horizontal, small ? 7 : 8).padding(.vertical, small ? 2 : 3)
        .background(active ? Theme.accent : Theme.chipBg)
        .foregroundColor(active ? Color.black : Theme.textLo)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(active ? Color.clear : Theme.stroke, lineWidth: 1))
    }
}
