import AppKit
import AIquotaCore
import SwiftUI

/// Diagnostics and documentation screenshots without screen-recording permission:
/// renders real app views in an off-screen window and saves PNGs.
///
///     AIQUOTA_DEBUG_DUMP_DIR=/tmp/aiquota AIquota.app/Contents/MacOS/AIquota [--fixtures]
@MainActor
enum DebugSnapshots {
    static func dumpViews(model: AppModel, updates: UpdateManager, to directory: URL) {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .darkAqua ? "dark" : "light"
            for provider in model.store.providers {
                render(PopoverView(providerID: provider.id), model: model, updates: updates, appearance: appearance,
                       to: directory.appendingPathComponent("popover-\(provider.id.rawValue)-\(suffix).png"))
            }
            for tab in SettingsTab.allCases {
                render(SettingsView(tab: .constant(tab)), model: model, updates: updates, appearance: appearance,
                       to: directory.appendingPathComponent("settings-\(tab.rawValue)-\(suffix).png"))
            }
            var withIcons = model.settings.appearance
            withIcons.showProviderIcon = true
            render(PreviewStrip(appearance: withIcons, thresholds: model.settings.thresholds).frame(width: 520).padding(8),
                   model: model, updates: updates, appearance: appearance, to: directory.appendingPathComponent("preview-icons-\(suffix).png"))
            render(OnboardingView(finish: {}), model: model, updates: updates, appearance: appearance,
                   to: directory.appendingPathComponent("onboarding-\(suffix).png"))
        }
    }

    private static func render<V: View>(_ view: V, model: AppModel, updates: UpdateManager,
                                        appearance: NSAppearance.Name, to url: URL) {
        let root = view
            .environmentObject(model)
            .environmentObject(model.store)
            .environmentObject(model.notifications)
            .environmentObject(updates)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
        window.orderOut(nil)
    }
}
