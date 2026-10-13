import AppKit
import Testing
@testable import AIquotaCore
@testable import AIquotaUI

/// Renders every style at the reference percentages in light and dark.
/// Set AIQUOTA_GALLERY_DIR to write PNGs for visual review (used for docs/images).
@Suite struct RenderGalleryTests {
    static let percentages: [Double] = [100, 99, 50, 20, 10, 9, 5, 0]
    static let menuBarHeight: CGFloat = 24

    static func cells(available: Double, weekly: Double, mode: ValueMode = .available) -> [IndicatorCell] {
        let status = Fixtures.status(.codex, name: "Codex", fiveHourAvailable: available, weeklyAvailable: weekly)
        return IndicatorModelBuilder.cells(for: status, windows: .both, mode: mode, thresholds: .default, now: Date())
    }

    @Test func galleryRendersAndWidthIsStable() throws {
        for style in IndicatorStyle.allCases {
            var settings = AppearanceSettings()
            settings.style = style
            let layout = IndicatorLayout(settings: settings, height: Self.menuBarHeight)
            let widths = Set(Self.percentages.filter { $0 != 100 }.map {
                layout.totalWidth(cells: Self.cells(available: $0, weekly: 42))
            })
            #expect(widths.count == 1, "\(style) width must not change between 0% and 99%")
            // With the % sign, "100" fits the same slot.
            #expect(layout.totalWidth(cells: Self.cells(available: 100, weekly: 42)) == widths.first)
        }

        guard let dir = ProcessInfo.processInfo.environment["AIQUOTA_GALLERY_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            try writeGallery(appearance: NSAppearance(named: appearanceName)!,
                             to: URL(fileURLWithPath: dir).appendingPathComponent("styles-\(name).png"))
            try writeMenuBar(appearance: NSAppearance(named: appearanceName)!,
                             to: URL(fileURLWithPath: dir).appendingPathComponent("menubar-\(name).png"))
        }
    }

    /// A menu-bar-like strip with both indicators (sample values) for the README.
    func writeMenuBar(appearance: NSAppearance, to url: URL) throws {
        let scale: CGFloat = 2, height: CGFloat = 24
        let settings = AppearanceSettings()
        let codex = Self.cells(available: 83, weekly: 42)
        let claude = IndicatorModelBuilder.cells(
            for: Fixtures.status(.claude, name: "Claude Code", fiveHourAvailable: 15, weeklyAvailable: 7),
            windows: .both, mode: .available, thresholds: .default, now: Date())
        let layout = IndicatorLayout(settings: settings, height: height)
        let size = NSSize(width: 360, height: height)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            let isDark = appearance.name == .darkAqua
            NSColor(rgb: isDark ? 0x2B2B2D : 0xECECEE).setFill()
            NSRect(origin: .zero, size: size).fill()
            let clock: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                                        .foregroundColor: NSColor.labelColor]
            ("Tue 14:08" as NSString).draw(at: NSPoint(x: size.width - 72, y: 4), withAttributes: clock)
            var x: CGFloat = 70
            for cells in [codex, claude] {
                let width = layout.totalWidth(cells: cells)
                IndicatorRenderer.draw(cells: cells, settings: settings, in: NSRect(x: x, y: 0, width: width, height: height))
                x += width + 16
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    func writeGallery(appearance: NSAppearance, to url: URL) throws {
        let scale: CGFloat = 2
        let rowHeight = Self.menuBarHeight
        let rows = Self.percentages.count
        let columnWidth: CGFloat = 120
        let size = NSSize(width: 70 + columnWidth * 3, height: rowHeight * CGFloat(rows + 1) + 8)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            let isDark = appearance.name == .darkAqua
            NSColor(rgb: isDark ? 0x2B2B2D : 0xF2F2F4).setFill()
            NSRect(origin: .zero, size: size).fill()
            let header: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium),
                                                         .foregroundColor: NSColor.secondaryLabelColor]
            for (i, style) in IndicatorStyle.allCases.enumerated() {
                (style.rawValue as NSString).draw(at: NSPoint(x: 70 + CGFloat(i) * columnWidth, y: size.height - 16), withAttributes: header)
            }
            for (row, pct) in Self.percentages.enumerated() {
                let y = size.height - 8 - rowHeight * CGFloat(row + 2)
                ("5h \(Int(pct))%" as NSString).draw(at: NSPoint(x: 8, y: y + 7), withAttributes: header)
                for (i, style) in IndicatorStyle.allCases.enumerated() {
                    var settings = AppearanceSettings()
                    settings.style = style
                    let cells = Self.cells(available: pct, weekly: 42)
                    let width = IndicatorLayout(settings: settings, height: rowHeight).totalWidth(cells: cells)
                    IndicatorRenderer.draw(cells: cells, settings: settings,
                                           in: NSRect(x: 70 + CGFloat(i) * columnWidth, y: y, width: width, height: rowHeight))
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
