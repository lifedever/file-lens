import SwiftUI
import AppKit

extension Color {
    /// "#3B82F6" / "3B82F6" → SwiftUI Color. Returns gray for malformed input.
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        guard Scanner(string: hex).scanHexInt64(&int), hex.count == 6 else {
            self = Color.gray; return
        }
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255.0,
            green: Double((int >>  8) & 0xFF) / 255.0,
            blue:  Double( int        & 0xFF) / 255.0
        )
    }

    /// Round-trips through NSColor in sRGB so the bytes match what we wrote.
    /// Display-P3 → sRGB conversion can lose precision, but for swatch
    /// presets that's fine — and storing hex keeps the database portable.
    func toHexString() -> String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor.gray
        let r = Int((ns.redComponent   * 255).rounded())
        let g = Int((ns.greenComponent * 255).rounded())
        let b = Int((ns.blueComponent  * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Curated swatch palette used by the rule editor. Intentionally small —
/// users who need an exact color reach for the system ColorPicker beside it.
enum RuleColorPresets {
    static let all: [String] = [
        "#3B82F6", "#0EA5E9", "#10B981", "#059669",
        "#F59E0B", "#F97316", "#EF4444", "#DC2626",
        "#EC4899", "#8B5CF6", "#6B7280", "#9CA3AF",
    ]
}
