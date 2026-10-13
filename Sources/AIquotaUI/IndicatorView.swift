import AppKit
import AIquotaCore

/// Hosted inside an `NSStatusBarButton`. Draws with the button's effective appearance, so it follows
/// light/dark menu bars (including wallpaper-tinted ones) without template-image tricks.
/// Clicks pass through to the button.
public final class IndicatorView: NSView {
    public var cells: [IndicatorCell] = [] {
        didSet { if cells != oldValue { needsDisplay = true } }
    }

    public var settings = AppearanceSettings() {
        didSet { if settings != oldValue { needsDisplay = true } }
    }

    /// Optional provider icon drawn before the numbers.
    public var mark: NSImage? {
        didSet { if mark !== oldValue { needsDisplay = true } }
    }

    public override var isFlipped: Bool { false }
    public override var allowsVibrancy: Bool { false }

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    public func preferredWidth(height: CGFloat) -> CGFloat {
        IndicatorLayout(settings: settings, height: height).totalWidth(cells: cells, hasMark: mark != nil)
    }

    public override func draw(_ dirtyRect: NSRect) {
        Self.drawingAppearance(for: effectiveAppearance).performAsCurrentDrawingAppearance {
            IndicatorRenderer.draw(cells: cells, settings: settings, mark: mark, in: bounds)
        }
    }

    /// The menu bar reports a *vibrant* appearance whose label colors rely on special blending.
    /// This view opts out of vibrancy, so colors are resolved against the matching opaque
    /// appearance: solid black-ish text on light menu bars, white-ish on dark ones.
    public static func drawingAppearance(for appearance: NSAppearance) -> NSAppearance {
        let match = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight,
                                                .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua,
                                                .accessibilityHighContrastVibrantDark, .accessibilityHighContrastVibrantLight])
        switch match {
        case .some(.darkAqua), .some(.vibrantDark): return NSAppearance(named: .darkAqua)!
        case .some(.accessibilityHighContrastDarkAqua), .some(.accessibilityHighContrastVibrantDark):
            return NSAppearance(named: .accessibilityHighContrastDarkAqua) ?? NSAppearance(named: .darkAqua)!
        case .some(.accessibilityHighContrastAqua), .some(.accessibilityHighContrastVibrantLight):
            return NSAppearance(named: .accessibilityHighContrastAqua) ?? NSAppearance(named: .aqua)!
        default: return NSAppearance(named: .aqua)!
        }
    }

    public var isDarkAppearance: Bool {
        Self.drawingAppearance(for: effectiveAppearance).name == .darkAqua
            || Self.drawingAppearance(for: effectiveAppearance).name == .accessibilityHighContrastDarkAqua
    }
}
