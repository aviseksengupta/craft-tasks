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
    static let destructive = Color(hex: 0xE5484D)  // actual red — delete actions
    static let shadow    = Color.black.opacity(0.35)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Lowercase 6-digit hex string (no leading "#"), matching the format
    /// tag colors are stored in — used to persist a color picked from the
    /// native macOS color panel (ColorPicker), not just the preset swatches.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int((ns.redComponent * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }
}

/// Soft, low, wide shadow — the gentle "paper lifted off the desk" elevation
/// Craft uses on cards and panels, instead of a hard drop shadow.
extension View {
    func craftShadow(radius: CGFloat = 14, y: CGFloat = 5) -> some View {
        shadow(color: Theme.shadow, radius: radius, x: 0, y: y)
    }

    /// Renders `content` as a floating overlay pinned just below this view,
    /// tracking its actual (possibly variable) height via GeometryReader —
    /// used for autocomplete dropdowns. An overlay never affects layout
    /// size, unlike a normal sibling view, which is the point: a dropdown
    /// that resizes as matches change shouldn't make the whole window/sheet
    /// visibly jump while typing.
    func floatingBelow<Content: View>(gap: CGFloat = 4, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(FloatingBelowModifier(gap: gap, overlayContent: content))
    }
}

private struct FloatingBelowModifier<OverlayContent: View>: ViewModifier {
    let gap: CGFloat
    @ViewBuilder let overlayContent: () -> OverlayContent
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.onAppear { height = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, new in height = new }
                }
            )
            .overlay(alignment: .topLeading) {
                overlayContent()
                    .offset(y: height + gap)
            }
            .zIndex(1)
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
