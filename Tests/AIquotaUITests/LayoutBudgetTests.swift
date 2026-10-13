import AppKit
import Testing
@testable import AIquotaCore
@testable import AIquotaUI

/// Width budgets: an indicator with both windows must stay small. Values are points at the
/// default sizes on a 22-pt status bar button (the real button height on macOS 14–26).
@Suite struct LayoutBudgetTests {
    static let height: CGFloat = 22

    func width(_ style: IndicatorStyle, cells: Int = 2, percent: Bool = true, value: Int = 42) -> CGFloat {
        var settings = AppearanceSettings()
        settings.style = style
        settings.showPercentSign = percent
        let cell = IndicatorCell(kind: .fiveHour, value: value, fraction: Double(value) / 100, tone: .neutral)
        return IndicatorLayout(settings: settings, height: Self.height).totalWidth(cells: Array(repeating: cell, count: cells))
    }

    @Test(arguments: [(IndicatorStyle.minimal, 84.0), (.microbar, 84.0), (.ring, 68.0)])
    func defaultBudget(style: IndicatorStyle, budget: Double) {
        let measured = width(style)
        print("budget \(style.rawValue): \(measured)pt (2 windows, % sign), 1 window: \(width(style, cells: 1))pt, no %: \(width(style, percent: false))pt")
        #expect(measured <= budget)
    }

    @Test func noLeadingSpaceSoIndicatorsHugTheAppIcon() {
        #expect(IndicatorLayout.leadingPadding == 0)
        #expect(IndicatorLayout.trailingPadding <= 1)
    }

    @Test func providerIconAddsOnlyItsOwnWidth() {
        let settings = AppearanceSettings()
        let layout = IndicatorLayout(settings: settings, height: Self.height)
        let cells = [IndicatorCell(kind: .fiveHour, value: 42, fraction: 0.42, tone: .neutral)]
        let extra = layout.totalWidth(cells: cells, hasMark: true) - layout.totalWidth(cells: cells)
        #expect(layout.markSize == 16)
        #expect(extra <= layout.markSize + 4)
    }

    @Test func hiddenPercentSaves() {
        #expect(width(.microbar, percent: false) < width(.microbar))
    }

    @Test func hundredWithoutPercentGrowsByOneDigitOnly() {
        let normal = width(.minimal, cells: 1, percent: false, value: 99)
        let hundred = width(.minimal, cells: 1, percent: false, value: 100)
        #expect(hundred > normal)
        #expect(hundred - normal <= 9)
    }

    @Test func ringFitsTheMenuBar() {
        let layout = IndicatorLayout(settings: AppearanceSettings(), height: Self.height)
        #expect(layout.ringDiameter <= Self.height - 4)
    }

    @Test func largestSettingsStillFitVertically() {
        var settings = AppearanceSettings()
        settings.numberSize = AppearanceSettings.numberSizeRange.upperBound
        settings.barThickness = AppearanceSettings.barThicknessRange.upperBound
        let fonts = IndicatorLayout.fonts(settings, height: Self.height)
        let labelTop = fonts.number.capHeight + 2 + settings.barThickness + (fonts.label.ascender - fonts.label.capHeight)
        #expect(labelTop < Self.height)
    }

    @Test func darkAndLightDrawingAppearances() {
        #expect(IndicatorView.drawingAppearance(for: NSAppearance(named: .vibrantDark)!).name == .darkAqua)
        #expect(IndicatorView.drawingAppearance(for: NSAppearance(named: .vibrantLight)!).name == .aqua)
        #expect(IndicatorView.drawingAppearance(for: NSAppearance(named: .aqua)!).name == .aqua)
    }

    @Test func paletteHasNoGreenAndAdapts() {
        let light = NSAppearance(named: .aqua)!, dark = NSAppearance(named: .darkAqua)!
        var lightCaution = NSColor.black, darkCaution = NSColor.black
        light.performAsCurrentDrawingAppearance { lightCaution = IndicatorPalette.defaultCaution.usingColorSpace(.sRGB)! }
        dark.performAsCurrentDrawingAppearance { darkCaution = IndicatorPalette.defaultCaution.usingColorSpace(.sRGB)! }
        #expect(lightCaution.hexString != darkCaution.hexString)
        #expect(lightCaution.greenComponent < lightCaution.redComponent)
        #expect(NSColor(hex: "#A8443C")?.hexString == "#A8443C")
        #expect(NSColor(hex: "nope") == nil)
    }
}
