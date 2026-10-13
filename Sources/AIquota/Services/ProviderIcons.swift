import AppKit
import AIquotaCore

/// Provider icons for the optional "show AI app icon" setting.
///
/// AIquota ships no third-party logos. It borrows the icon of the app already installed on this Mac
/// (looked up by bundle identifier, then by path). Without the app, a small neutral monogram is drawn.
@MainActor
enum ProviderIcons {
    private static var cache: [ProviderID: NSImage] = [:]

    private static let bundleIDs: [ProviderID: [String]] = [
        .codex: ["com.openai.codex", "com.openai.chat"],
        .claude: ["com.anthropic.claudefordesktop"],
    ]
    private static let paths: [ProviderID: [String]] = [
        .codex: ["/Applications/Codex.app", "/Applications/ChatGPT.app"],
        .claude: ["/Applications/Claude.app"],
    ]
    private static let monograms: [ProviderID: String] = [.codex: "Cx", .claude: "Cl"]

    static func icon(for id: ProviderID) -> NSImage {
        if let cached = cache[id] { return cached }
        let image = installedAppIcon(id) ?? monogram(monograms[id] ?? String(id.rawValue.prefix(2)).capitalized)
        cache[id] = image
        return image
    }

    private static func installedAppIcon(_ id: ProviderID) -> NSImage? {
        let workspace = NSWorkspace.shared
        let fromBundle = (bundleIDs[id] ?? []).lazy.compactMap { workspace.urlForApplication(withBundleIdentifier: $0) }.first
        let fromPath = (paths[id] ?? []).lazy.map(URL.init(fileURLWithPath:))
            .first { FileManager.default.fileExists(atPath: $0.path) }
        guard let url = fromBundle ?? fromPath else { return nil }
        let icon = workspace.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }

    /// Neutral two-letter mark; colors resolve at draw time, so it follows light/dark menu bars.
    private static func monogram(_ text: String) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let box = rect.insetBy(dx: 0.5, dy: 0.5)
            NSColor.labelColor.withAlphaComponent(0.55).setStroke()
            let path = NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5)
            path.lineWidth = 1
            path.stroke()
            let font = NSFont.systemFont(ofSize: 8, weight: .semibold)
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            let size = string.size()
            string.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - font.capHeight / 2 + font.descender))
            return true
        }
    }
}
