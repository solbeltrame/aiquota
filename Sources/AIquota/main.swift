import AppKit

// Menu bar only: no Dock icon (LSUIElement is also set in Info.plist for the bundled app).
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
