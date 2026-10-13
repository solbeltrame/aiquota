// Generates Resources/AppIcon.icns: `swift scripts/make-icon.swift` (then run scripts/make-icon.sh).
// A plain graphite tile with the indicator motif: a number, a tiny "5h" and a hairline bar.
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
NSColor(srgbRed: 0.13, green: 0.13, blue: 0.145, alpha: 1).setFill()
NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()

let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 330, weight: .semibold)
let number = NSAttributedString(string: "83", attributes: [.font: numberFont, .foregroundColor: NSColor(white: 0.96, alpha: 1)])
let numberSize = number.size()
let baseline: CGFloat = 430
let x = tile.midX - numberSize.width / 2 - 40
number.draw(at: NSPoint(x: x, y: baseline + numberFont.descender))

let labelFont = NSFont.systemFont(ofSize: 120, weight: .semibold)
let label = NSAttributedString(string: "5h", attributes: [.font: labelFont, .foregroundColor: NSColor(white: 0.62, alpha: 1)])
label.draw(at: NSPoint(x: x + numberSize.width + 14, y: baseline + numberFont.capHeight - labelFont.capHeight + labelFont.descender))

let track = NSRect(x: x, y: 330, width: numberSize.width, height: 26)
NSColor(white: 1, alpha: 0.16).setFill()
NSBezierPath(roundedRect: track, xRadius: 13, yRadius: 13).fill()
var fill = track
fill.size.width *= 0.83
NSColor(white: 0.96, alpha: 0.7).setFill()
NSBezierPath(roundedRect: fill, xRadius: 13, yRadius: 13).fill()

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
