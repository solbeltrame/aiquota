import AppKit
import AIquotaCore

/// Muted, low-saturation alert colors. No green: "fine" is simply the system's neutral color.
public enum IndicatorPalette {
    public static let defaultCaution = dynamic(light: 0x946510, dark: 0xD9B36A)
    public static let defaultCritical = dynamic(light: 0xA8443C, dark: 0xE5867D)

    public static func caution(_ settings: AppearanceSettings) -> NSColor {
        settings.cautionColorHex.flatMap(NSColor.init(hex:)) ?? defaultCaution
    }

    public static func critical(_ settings: AppearanceSettings) -> NSColor {
        settings.criticalColorHex.flatMap(NSColor.init(hex:)) ?? defaultCritical
    }

    /// Color for bars and rings.
    public static func accent(for tone: Tone, settings: AppearanceSettings) -> NSColor {
        switch tone {
        case .neutral: return NSColor.labelColor.withAlphaComponent(0.62)
        case .caution: return caution(settings)
        case .critical: return critical(settings)
        case .muted: return NSColor.tertiaryLabelColor
        }
    }

    /// Color for the number itself: neutral unless the user opted into colored numbers.
    public static func number(for tone: Tone, settings: AppearanceSettings) -> NSColor {
        switch tone {
        case .muted: return NSColor.tertiaryLabelColor
        case .neutral: return NSColor.labelColor
        case .caution, .critical: return settings.colorizeNumbers ? accent(for: tone, settings: settings) : .labelColor
        }
    }

    public static var track: NSColor { NSColor.labelColor.withAlphaComponent(0.16) }
    public static var label: NSColor { NSColor.secondaryLabelColor }

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua, .vibrantDark, .vibrantLight]).map {
                $0 == .darkAqua || $0 == .vibrantDark
            } ?? false
            return NSColor(rgb: isDark ? dark : light)
        }
    }
}

public extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    convenience init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if string.hasPrefix("#") { string.removeFirst() }
        guard string.count == 6, let value = UInt32(string, radix: 16) else { return nil }
        self.init(rgb: value)
    }

    var hexString: String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent * 255).rounded()), g = Int((rgb.greenComponent * 255).rounded()),
            b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
