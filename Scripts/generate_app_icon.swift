import AppKit
import Foundation

struct IconSlot {
    let filename: String
    let size: String
    let scale: String
    let pixels: Int
}

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let assetCatalog = root.appendingPathComponent("Assets.xcassets", isDirectory: true)
let appIconSet = assetCatalog.appendingPathComponent("AppIcon.appiconset", isDirectory: true)

let slots: [IconSlot] = [
    IconSlot(filename: "icon_16x16.png", size: "16x16", scale: "1x", pixels: 16),
    IconSlot(filename: "icon_16x16@2x.png", size: "16x16", scale: "2x", pixels: 32),
    IconSlot(filename: "icon_32x32.png", size: "32x32", scale: "1x", pixels: 32),
    IconSlot(filename: "icon_32x32@2x.png", size: "32x32", scale: "2x", pixels: 64),
    IconSlot(filename: "icon_128x128.png", size: "128x128", scale: "1x", pixels: 128),
    IconSlot(filename: "icon_128x128@2x.png", size: "128x128", scale: "2x", pixels: 256),
    IconSlot(filename: "icon_256x256.png", size: "256x256", scale: "1x", pixels: 256),
    IconSlot(filename: "icon_256x256@2x.png", size: "256x256", scale: "2x", pixels: 512),
    IconSlot(filename: "icon_512x512.png", size: "512x512", scale: "1x", pixels: 512),
    IconSlot(filename: "icon_512x512@2x.png", size: "512x512", scale: "2x", pixels: 1024),
]

try FileManager.default.createDirectory(at: appIconSet, withIntermediateDirectories: true)

for slot in slots {
    let image = makeIcon(pixels: slot.pixels)
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode \(slot.filename)")
    }
    try data.write(to: appIconSet.appendingPathComponent(slot.filename), options: [.atomic])
}

try """
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""".write(to: assetCatalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

let imageEntries = slots.map { slot in
    """
    {
      "filename" : "\(slot.filename)",
      "idiom" : "mac",
      "scale" : "\(slot.scale)",
      "size" : "\(slot.size)"
    }
    """
}.joined(separator: ",\n")

try """
{
  "images" : [
\(imageEntries.split(separator: "\n").map { "    \($0)" }.joined(separator: "\n"))
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
""".write(to: appIconSet.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

func makeIcon(pixels: Int) -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create bitmap context")
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)

    guard let image = context.makeImage() else {
        fatalError("Could not render icon")
    }
    return image
}

func drawIcon(in context: CGContext) {
    let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let squircle = CGPath(roundedRect: canvas.insetBy(dx: 8, dy: 8), cornerWidth: 224, cornerHeight: 224, transform: nil)

    context.addPath(squircle)
    context.clip()

    drawBackground(in: context)
    drawPanel(in: context)
    drawReminderRing(in: context)
    drawStool(in: context)
    drawInnerHighlight(in: context)
}

func drawBackground(in context: CGContext) {
    let colors = [
        CGColor(red: 0.91, green: 0.99, blue: 1.00, alpha: 1.0),
        CGColor(red: 0.57, green: 0.82, blue: 0.93, alpha: 1.0),
        CGColor(red: 0.08, green: 0.42, blue: 0.62, alpha: 1.0),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.57, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 126, y: 988), end: CGPoint(x: 914, y: 82), options: [])

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    context.fillEllipse(in: CGRect(x: -168, y: 622, width: 572, height: 462))

    context.setFillColor(CGColor(red: 0.02, green: 0.19, blue: 0.23, alpha: 0.13))
    context.fillEllipse(in: CGRect(x: 548, y: -158, width: 642, height: 532))
}

func drawPanel(in context: CGContext) {
    let rect = CGRect(x: 184, y: 188, width: 656, height: 648)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 56, color: CGColor(red: 0.02, green: 0.16, blue: 0.18, alpha: 0.22))
    context.setFillColor(CGColor(red: 0.96, green: 1.00, blue: 0.98, alpha: 0.90))
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 208, cornerHeight: 208, transform: nil))
    context.fillPath()
    context.restoreGState()

    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.72))
    context.setLineWidth(10)
    context.addPath(CGPath(roundedRect: rect.insetBy(dx: 8, dy: 8), cornerWidth: 198, cornerHeight: 198, transform: nil))
    context.strokePath()
}

func drawReminderRing(in context: CGContext) {
    let center = CGPoint(x: 512, y: 532)
    let radius: CGFloat = 248
    let width: CGFloat = 68

    context.setFillColor(CGColor(red: 0.02, green: 0.73, blue: 0.36, alpha: 0.08))
    context.fillEllipse(in: CGRect(x: center.x - 258, y: center.y - 258, width: 516, height: 516))

    context.setStrokeColor(CGColor(red: 0.05, green: 0.36, blue: 0.50, alpha: 0.13))
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    context.strokePath()

    let ringColor = CGColor(red: 0.02, green: 0.74, blue: 0.36, alpha: 1)
    context.setStrokeColor(ringColor)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.addArc(center: center, radius: radius, startAngle: 0.18 * .pi, endAngle: 1.54 * .pi, clockwise: false)
    context.strokePath()

    let tip = CGPoint(
        x: center.x + cos(1.54 * .pi) * radius,
        y: center.y + sin(1.54 * .pi) * radius
    )
    context.setFillColor(ringColor)
    context.fillEllipse(in: CGRect(x: tip.x - 30, y: tip.y - 30, width: 60, height: 60))
}

func drawStool(in context: CGContext) {
    let stoolColor = CGColor(red: 0.04, green: 0.20, blue: 0.28, alpha: 1)

    context.setFillColor(CGColor(red: 0.02, green: 0.14, blue: 0.18, alpha: 0.12))
    context.fillEllipse(in: CGRect(x: 350, y: 246, width: 324, height: 50))

    let seat = CGRect(x: 336, y: 350, width: 352, height: 82)
    context.setFillColor(stoolColor)
    context.addPath(CGPath(roundedRect: seat, cornerWidth: 41, cornerHeight: 41, transform: nil))
    context.fillPath()

    strokeLine(in: context, from: CGPoint(x: 450, y: 354), to: CGPoint(x: 420, y: 252), width: 40, color: stoolColor)
    strokeLine(in: context, from: CGPoint(x: 574, y: 354), to: CGPoint(x: 604, y: 252), width: 40, color: stoolColor)
    strokeLine(in: context, from: CGPoint(x: 392, y: 252), to: CGPoint(x: 452, y: 252), width: 28, color: stoolColor)
    strokeLine(in: context, from: CGPoint(x: 572, y: 252), to: CGPoint(x: 632, y: 252), width: 28, color: stoolColor)

    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    context.setLineWidth(8)
    context.addPath(CGPath(roundedRect: seat.insetBy(dx: 12, dy: 12), cornerWidth: 29, cornerHeight: 29, transform: nil))
    context.strokePath()
}

func drawInnerHighlight(in context: CGContext) {
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.23))
    context.setLineWidth(18)
    context.addPath(CGPath(roundedRect: CGRect(x: 30, y: 30, width: 964, height: 964), cornerWidth: 196, cornerHeight: 196, transform: nil))
    context.strokePath()
}

func strokeLine(in context: CGContext, from: CGPoint, to: CGPoint, width: CGFloat, color: CGColor) {
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: from)
    context.addLine(to: to)
    context.strokePath()
}
