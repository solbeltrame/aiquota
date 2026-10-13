import AppKit
import AIquotaCore

/// Geometry for one indicator. Widths depend only on settings and the number of cells, never on the
/// current values, so the status item does not jitter as percentages change. The single exception
/// is "100" with the % sign hidden, which needs one extra digit.
public struct IndicatorLayout: Equatable {
    public struct Fonts {
        public let number: NSFont
        public let percent: NSFont
        public let label: NSFont
        public let ringNumber: NSFont
        public let ringNumberHundred: NSFont
    }

    /// No space on the left so the indicator can sit right next to the AI app's own icon; macOS still
    /// adds its standard gap between status items, which public API cannot remove.
    public static let leadingPadding: CGFloat = 0
    public static let trailingPadding: CGFloat = 1
    static let markGap: CGFloat = 3
    static let labelGap: CGFloat = 0.5
    static let barGap: CGFloat = 2

    public let style: IndicatorStyle
    public let slotWidth: CGFloat
    public let wideSlotWidth: CGFloat
    public let labelWidth: CGFloat
    public let ringDiameter: CGFloat
    public let cellSpacing: CGFloat
    /// Side of the optional provider icon.
    public let markSize: CGFloat

    public init(settings: AppearanceSettings, height: CGFloat) {
        style = settings.style
        markSize = floor(min(16, max(10, height - 6)))
        let fonts = Self.fonts(settings, height: height)
        let digit2 = Self.width("00", fonts.number)
        let digit3 = Self.width("100", fonts.number)
        let percent = settings.showPercentSign ? Self.width("%", fonts.percent) + 0.5 : 0
        if settings.showPercentSign {
            // "100" is drawn without % so it fits the "99%" slot.
            slotWidth = ceil(max(digit2 + percent, digit3))
            wideSlotWidth = slotWidth
        } else {
            slotWidth = ceil(digit2)
            wideSlotWidth = ceil(digit3)
        }
        labelWidth = ceil(max(Self.width("5h", fonts.label), Self.width("7d", fonts.label)))
        ringDiameter = Self.ringDiameter(height: height)
        cellSpacing = CGFloat(settings.cellSpacing)
    }

    static func ringDiameter(height: CGFloat) -> CGFloat {
        min(18, max(12, height - 5))
    }

    public static func fonts(_ settings: AppearanceSettings, height: CGFloat) -> Fonts {
        let numberSize = CGFloat(settings.numberSize)
        let ringInner = ringDiameter(height: height) - CGFloat(settings.ringThickness) * 2
        // Ring numbers scale with the ring, then with the user's number size.
        let ringSize = min(numberSize * 0.72, ringInner * 0.62)
        return Fonts(number: .monospacedDigitSystemFont(ofSize: numberSize, weight: .medium),
                     percent: .systemFont(ofSize: numberSize * 0.72, weight: .medium),
                     label: .systemFont(ofSize: CGFloat(settings.labelSize), weight: .semibold),
                     ringNumber: .monospacedDigitSystemFont(ofSize: ringSize, weight: .semibold),
                     ringNumberHundred: .monospacedDigitSystemFont(ofSize: ringSize * 0.8, weight: .semibold))
    }

    static func width(_ string: String, _ font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    public func cellWidth(isWide: Bool) -> CGFloat {
        switch style {
        case .minimal, .microbar:
            return (isWide ? wideSlotWidth : slotWidth) + Self.labelGap + labelWidth
        case .ring:
            return ringDiameter + Self.labelGap + labelWidth
        }
    }

    public func totalWidth(cells: [IndicatorCell], hasMark: Bool = false) -> CGFloat {
        guard !cells.isEmpty else { return 0 }
        let widths = cells.map { cellWidth(isWide: style != .ring && $0.value == 100) }
        let mark = hasMark ? markSize + Self.markGap : 0
        return ceil(mark + widths.reduce(0, +) + cellSpacing * CGFloat(cells.count - 1)
                    + Self.leadingPadding + Self.trailingPadding)
    }
}

/// Draws indicators with AppKit text and Core Graphics paths — no Unicode superscripts.
public enum IndicatorRenderer {
    public static func draw(cells: [IndicatorCell], settings: AppearanceSettings, mark: NSImage? = nil, in bounds: NSRect) {
        let layout = IndicatorLayout(settings: settings, height: bounds.height)
        let fonts = IndicatorLayout.fonts(settings, height: bounds.height)
        var x = bounds.minX + IndicatorLayout.leadingPadding
        if let mark {
            let side = layout.markSize
            mark.draw(in: NSRect(x: x, y: bounds.minY + floor((bounds.height - side) / 2), width: side, height: side),
                      from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            x += side + IndicatorLayout.markGap
        }
        for cell in cells {
            let wide = settings.style != .ring && cell.value == 100
            let width = layout.cellWidth(isWide: wide)
            let rect = NSRect(x: x, y: bounds.minY, width: width, height: bounds.height)
            switch settings.style {
            case .minimal: drawText(cell, settings, layout, fonts, rect, withBar: false, wide: wide)
            case .microbar: drawText(cell, settings, layout, fonts, rect, withBar: true, wide: wide)
            case .ring: drawRing(cell, settings, layout, fonts, rect)
            }
            x += width + layout.cellSpacing
        }
    }

    /// Renders to an image using a specific appearance (settings preview, tests, screenshots).
    public static func image(cells: [IndicatorCell], settings: AppearanceSettings, mark: NSImage? = nil, height: CGFloat,
                             appearance: NSAppearance? = nil) -> NSImage {
        let width = max(1, IndicatorLayout(settings: settings, height: height).totalWidth(cells: cells, hasMark: mark != nil))
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        let drawing = { draw(cells: cells, settings: settings, mark: mark, in: NSRect(x: 0, y: 0, width: width, height: height)) }
        if let appearance { appearance.performAsCurrentDrawingAppearance(drawing) } else { drawing() }
        image.unlockFocus()
        return image
    }

    // MARK: Minimal & Microbar

    private static func drawText(_ cell: IndicatorCell, _ settings: AppearanceSettings, _ layout: IndicatorLayout,
                                 _ fonts: IndicatorLayout.Fonts, _ rect: NSRect, withBar: Bool, wide: Bool) {
        let numberFont = fonts.number
        let capHeight = numberFont.capHeight
        let barHeight = CGFloat(settings.barThickness)
        // Numbers are centered on their cap height, like the menu bar clock; the microbar hangs in the
        // space below instead of pushing the numbers up.
        // Digits overshoot the cap height slightly; nudge down and snap to half points (Retina pixels).
        let baseline = rect.minY + (((rect.height - capHeight) / 2 - 0.35) * 2).rounded() / 2
        let slot = wide ? layout.wideSlotWidth : layout.slotWidth
        let numberColor = IndicatorPalette.number(for: cell.tone, settings: settings)

        // Left-aligned number; the window label follows it directly.
        let text = NSMutableAttributedString()
        if let value = cell.value {
            text.append(NSAttributedString(string: "\(value)", attributes: [.font: numberFont, .foregroundColor: numberColor]))
            if settings.showPercentSign && value != 100 {
                text.append(NSAttributedString(string: "%", attributes: [.font: fonts.percent, .foregroundColor: numberColor]))
            }
        } else {
            text.append(NSAttributedString(string: "–", attributes: [.font: numberFont, .foregroundColor: numberColor]))
        }
        let size = text.size()
        text.draw(at: NSPoint(x: rect.minX, y: baseline + numberFont.descender))

        drawLabel(cell.label, fonts.label, x: rect.minX + ceil(size.width) + IndicatorLayout.labelGap,
                  capTop: baseline + capHeight)

        if withBar {
            let barY = max(rect.minY + 1, baseline - IndicatorLayout.barGap - barHeight)
            let track = NSRect(x: rect.minX, y: barY, width: slot, height: barHeight)
            drawBar(track: track, fraction: cell.value == nil ? 0 : cell.fraction,
                    color: IndicatorPalette.accent(for: cell.tone, settings: settings))
        }
    }

    private static func drawLabel(_ label: String, _ font: NSFont, x: CGFloat, capTop: CGFloat) {
        let attributed = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: IndicatorPalette.label])
        // Align the label's cap top with the number's cap top: a true top-right superscript.
        let baseline = capTop - font.capHeight
        attributed.draw(at: NSPoint(x: x, y: baseline + font.descender))
    }

    private static func drawBar(track: NSRect, fraction: Double, color: NSColor) {
        let radius = track.height / 2
        IndicatorPalette.track.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let clamped = CGFloat(min(1, max(0, fraction)))
        guard clamped > 0 else { return }
        var fill = track
        fill.size.width = max(track.height, track.width * clamped)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }

    // MARK: Ring

    private static func drawRing(_ cell: IndicatorCell, _ settings: AppearanceSettings, _ layout: IndicatorLayout,
                                 _ fonts: IndicatorLayout.Fonts, _ rect: NSRect) {
        let diameter = layout.ringDiameter
        let line = CGFloat(settings.ringThickness)
        let circle = NSRect(x: rect.minX, y: rect.minY + floor((rect.height - diameter) / 2), width: diameter, height: diameter)
        let center = NSPoint(x: circle.midX, y: circle.midY)
        let radius = (diameter - line) / 2

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = line
        IndicatorPalette.track.setStroke()
        track.stroke()

        let fraction = CGFloat(min(1, max(0, cell.value == nil ? 0 : cell.fraction)))
        if fraction > 0 {
            let arc = NSBezierPath()
            // Clockwise from 12 o'clock.
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
            arc.lineWidth = line
            arc.lineCapStyle = fraction < 1 ? .round : .butt
            IndicatorPalette.accent(for: cell.tone, settings: settings).setStroke()
            arc.stroke()
        }

        let font = cell.value == 100 ? fonts.ringNumberHundred : fonts.ringNumber
        let string = cell.value.map(String.init) ?? "–"
        let attributed = NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: IndicatorPalette.number(for: cell.tone, settings: settings),
        ])
        let size = attributed.size()
        // Center optically on the cap height rather than the line box.
        let baseline = center.y - font.capHeight / 2
        attributed.draw(at: NSPoint(x: center.x - size.width / 2, y: baseline + font.descender))

        drawLabel(cell.label, fonts.label, x: circle.maxX + IndicatorLayout.labelGap, capTop: circle.maxY - 0.5)
    }
}
