import AppKit
import Testing
@testable import AIquotaCore
@testable import AIquotaUI

/// Measures real ink: renders each style and checks the empty space above and below is balanced.
@Suite struct VerticalCenteringTests {
    static let height: CGFloat = 22

    /// Returns (top margin, bottom margin) in points of non-transparent pixels.
    static func margins(_ style: IndicatorStyle, numberSize: Double = 12) -> (top: CGFloat, bottom: CGFloat) {
        var settings = AppearanceSettings()
        settings.style = style
        settings.numberSize = numberSize
        let cells = [IndicatorCell(kind: .fiveHour, value: 42, fraction: 0.42, tone: .neutral),
                     IndicatorCell(kind: .weekly, value: 7, fraction: 0.07, tone: .critical)]
        let width = IndicatorLayout(settings: settings, height: height).totalWidth(cells: cells)
        let scale: CGFloat = 4
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            IndicatorRenderer.draw(cells: cells, settings: settings, in: NSRect(x: 0, y: 0, width: width, height: height))
        }
        NSGraphicsContext.restoreGraphicsState()
        var rows: [Int] = []
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 { rows.append(y); break }
        }
        // Bitmap rows go top-down.
        return (CGFloat(rows.min()!) / scale, CGFloat(rep.pixelsHigh - 1 - rows.max()!) / scale)
    }

    @Test func microbarNumbersSitAtTheSameHeightAsMinimal() {
        for size in [10.0, 12.0, 14.0] {
            #expect(Self.margins(.microbar, numberSize: size).top == Self.margins(.minimal, numberSize: size).top)
        }
    }

    @Test(arguments: [IndicatorStyle.minimal, .ring])
    func contentIsVerticallyCentered(style: IndicatorStyle) {
        for size in [10.0, 12.0, 14.0] {
            let m = Self.margins(style, numberSize: size)
            print("\(style.rawValue) size \(size): top \(m.top)pt bottom \(m.bottom)pt")
            #expect(abs(m.top - m.bottom) <= 1, "\(style) at \(size)pt is off-center: top \(m.top), bottom \(m.bottom)")
        }
    }
}
