import AppKit
import AIquotaCore
import AIquotaUI
import SwiftUI

/// One independent menu bar indicator per provider.
///
/// The item is created once and kept for the app's lifetime. Hiding uses `isVisible` instead of
/// removing it, and the stable `autosaveName` lets macOS remember where the user ⌘-dragged it.
@MainActor
final class StatusItemController: NSObject {
    let providerID: ProviderID
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let indicator = IndicatorView()
    private let popover = NSPopover()

    init(providerID: ProviderID, model: AppModel) {
        self.providerID = providerID
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.autosaveName = "app.aiquota.indicator.\(providerID.rawValue)"

        if let button = statusItem.button {
            indicator.frame = button.bounds
            indicator.autoresizingMask = [.width, .height]
            button.addSubview(indicator)
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: PopoverView(providerID: providerID)
            .environmentObject(model)
            .environmentObject(model.store))
    }

    func update(now: Date = Date()) {
        guard let status = model.store.statuses[providerID] else { return }
        let enabled = model.settings.providerSettings(providerID).enabled && model.isProviderAppRunning(providerID)
        if statusItem.isVisible != enabled { statusItem.isVisible = enabled }
        guard enabled, let button = statusItem.button else {
            closePopover()
            return
        }

        indicator.settings = model.settings.appearance
        indicator.mark = model.settings.appearance.showProviderIcon ? ProviderIcons.icon(for: providerID) : nil
        indicator.cells = model.cells(for: status, now: now)
        let height = button.bounds.height > 0 ? button.bounds.height : NSStatusBar.system.thickness
        let width = indicator.preferredWidth(height: height)
        if abs(statusItem.length - width) > 0.5 { statusItem.length = width }

        button.toolTip = tooltip(status, now: now)
        button.setAccessibilityLabel(accessibilitySummary(status, now: now))
    }

    /// Compact hover text, one line per window:
    /// "Codex\n5h  32% · renews 03:24 (in 2h 10m)\n7d  9% · renews Sun 01:28 (in 5d)".
    private func tooltip(_ status: ProviderStatus, now: Date) -> String {
        var lines = [status.displayName + (status.snapshot?.isFixture == true ? " · " + L("Sample data") : "")]
        let suffix = model.settings.valueMode == .consumed ? " " + L("used") : ""
        for cell in indicator.cells {
            var line = "\(cell.label)  " + (cell.value.map { "\($0)%\(suffix)" } ?? "–")
            if let renewal = renewalText(for: cell.kind, status: status, now: now) { line += " · " + renewal }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// Full sentences for VoiceOver.
    private func accessibilitySummary(_ status: ProviderStatus, now: Date) -> String {
        var parts = [status.displayName]
        for cell in indicator.cells {
            let window = AlertText.windowName(cell.kind)
            var part: String
            if let value = cell.value {
                let mode = model.settings.valueMode == .available ? L("available") : L("used")
                part = "\(window): \(value)% \(mode)"
            } else {
                part = "\(window): \(L("no data"))"
            }
            if let renewal = renewalText(for: cell.kind, status: status, now: now) { part += ", " + renewal }
            parts.append(part)
        }
        if status.snapshot?.isFixture == true { parts.append(L("Sample data")) }
        return parts.joined(separator: " · ")
    }

    /// "renews 03:24 (in 2h 10m)" — only for real, future reset times reported by the source.
    private func renewalText(for kind: WindowKind, status: ProviderStatus, now: Date) -> String? {
        guard let snapshot = status.snapshot, let window = snapshot.window(kind), let resetsAt = window.resetsAt,
              !snapshot.isOutdated(window, at: now) else { return nil }
        return String(format: L("renews %@ (in %@)"), Formatters.time(resetsAt), RelativeTime.countdown(to: resetsAt, from: now))
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        model.store.refresh(providerID, reason: .manual)
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() { popover.performClose(nil) }

    /// Diagnostics: renders the live indicator with the exact cells, settings, size and appearance the
    /// menu bar view is using (no screen recording permission needed). Enabled with AIQUOTA_DEBUG_DUMP_DIR.
    func dumpIndicator(to directory: URL) {
        guard let button = statusItem.button, let window = button.window else { return }
        let bounds = indicator.bounds
        let scale = window.backingScaleFactor
        let isDark = indicator.isDarkAppearance
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale),
                                         pixelsHigh: Int(bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        rep.size = bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // Menu-bar-like backdrop so light text stays visible in the PNG.
        NSColor(white: isDark ? 0.16 : 0.93, alpha: 1).setFill()
        NSRect(origin: .zero, size: bounds.size).fill()
        IndicatorView.drawingAppearance(for: indicator.effectiveAppearance).performAsCurrentDrawingAppearance {
            IndicatorRenderer.draw(cells: indicator.cells, settings: indicator.settings, mark: indicator.mark,
                                   in: NSRect(origin: .zero, size: bounds.size))
        }
        NSGraphicsContext.restoreGraphicsState()
        let base = directory.appendingPathComponent("indicator-\(providerID.rawValue)")
        try? rep.representation(using: .png, properties: [:])?.write(to: base.appendingPathExtension("png"))
        let info = "frame=\(NSStringFromRect(window.frame)) bounds=\(NSStringFromRect(bounds)) visible=\(statusItem.isVisible) "
            + "appearance=\(button.effectiveAppearance.name.rawValue) dark=\(isDark) length=\(statusItem.length)\n"
            + "tooltip=\(button.toolTip ?? "")\n"
            + "buttonInWindow=\(NSStringFromRect(button.convert(button.bounds, to: nil))) "
            + "indicatorInWindow=\(NSStringFromRect(indicator.convert(indicator.bounds, to: nil))) "
            + "content=\(NSStringFromRect(window.contentView?.bounds ?? .zero))\n"
        try? info.write(to: base.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
    }
}
