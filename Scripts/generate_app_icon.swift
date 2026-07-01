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
    let squircle = CGPath(roundedRect: canvas.insetBy(dx: 10, dy: 10), cornerWidth: 222, cornerHeight: 222, transform: nil)

    context.addPath(squircle)
    context.clip()

    drawBackground(in: context, rect: canvas)
    drawBadge(in: context)
    drawPostureCue(in: context)
    drawChair(in: context)
    drawPerson(in: context)
    drawInnerHighlight(in: context)
}

func drawBackground(in context: CGContext, rect: CGRect) {
    let colors = [
        CGColor(red: 0.87, green: 0.99, blue: 0.96, alpha: 1.0),
        CGColor(red: 0.54, green: 0.88, blue: 0.85, alpha: 1.0),
        CGColor(red: 0.17, green: 0.62, blue: 0.58, alpha: 1.0),
    ] as CFArray
    let locations: [CGFloat] = [0, 0.52, 1]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations)!
    context.drawLinearGradient(gradient, start: CGPoint(x: 180, y: 970), end: CGPoint(x: 890, y: 90), options: [])

    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    context.fillEllipse(in: CGRect(x: -170, y: 610, width: 580, height: 500))

    context.setFillColor(CGColor(red: 0.04, green: 0.22, blue: 0.26, alpha: 0.14))
    context.fillEllipse(in: CGRect(x: 520, y: -170, width: 650, height: 520))
}

func drawBadge(in context: CGContext) {
    let badge = CGRect(x: 164, y: 158, width: 696, height: 708)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -22), blur: 48, color: CGColor(red: 0.04, green: 0.22, blue: 0.26, alpha: 0.22))
    context.setFillColor(CGColor(red: 0.96, green: 1.0, blue: 0.98, alpha: 0.92))
    context.addPath(CGPath(roundedRect: badge, cornerWidth: 176, cornerHeight: 176, transform: nil))
    context.fillPath()
    context.restoreGState()

    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.72))
    context.setLineWidth(10)
    context.addPath(CGPath(roundedRect: badge.insetBy(dx: 6, dy: 6), cornerWidth: 168, cornerHeight: 168, transform: nil))
    context.strokePath()
}

func drawChair(in context: CGContext) {
    let chairColor = CGColor(red: 0.06, green: 0.24, blue: 0.30, alpha: 1.0)
    let chairShadow = CGColor(red: 0.02, green: 0.14, blue: 0.17, alpha: 0.18)

    context.setFillColor(chairShadow)
    context.fillEllipse(in: CGRect(x: 300, y: 260, width: 440, height: 58))

    context.setFillColor(chairColor)
    context.addPath(CGPath(roundedRect: CGRect(x: 292, y: 340, width: 428, height: 86), cornerWidth: 43, cornerHeight: 43, transform: nil))
    context.fillPath()

    context.addPath(CGPath(roundedRect: CGRect(x: 292, y: 424, width: 92, height: 300), cornerWidth: 46, cornerHeight: 46, transform: nil))
    context.fillPath()

    strokeLine(in: context, from: CGPoint(x: 420, y: 340), to: CGPoint(x: 372, y: 250), width: 38, color: chairColor)
    strokeLine(in: context, from: CGPoint(x: 635, y: 340), to: CGPoint(x: 700, y: 250), width: 38, color: chairColor)
}

func drawPerson(in context: CGContext) {
    let green = CGColor(red: 0.04, green: 0.77, blue: 0.30, alpha: 1.0)
    let greenDark = CGColor(red: 0.03, green: 0.55, blue: 0.26, alpha: 1.0)
    let shine = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.52)

    context.setFillColor(green)
    context.fillEllipse(in: CGRect(x: 462, y: 644, width: 116, height: 116))

    context.setFillColor(green)
    context.addPath(CGPath(roundedRect: CGRect(x: 470, y: 438, width: 102, height: 196), cornerWidth: 51, cornerHeight: 51, transform: nil))
    context.fillPath()

    strokeLine(in: context, from: CGPoint(x: 452, y: 566), to: CGPoint(x: 392, y: 482), width: 44, color: greenDark)
    strokeLine(in: context, from: CGPoint(x: 590, y: 564), to: CGPoint(x: 665, y: 496), width: 44, color: greenDark)
    strokeLine(in: context, from: CGPoint(x: 520, y: 442), to: CGPoint(x: 644, y: 383), width: 52, color: green)
    strokeLine(in: context, from: CGPoint(x: 524, y: 438), to: CGPoint(x: 444, y: 330), width: 52, color: green)

    strokeLine(in: context, from: CGPoint(x: 522, y: 612), to: CGPoint(x: 522, y: 464), width: 15, color: shine)
}

func drawPostureCue(in context: CGContext) {
    let cueColor = CGColor(red: 0.02, green: 0.70, blue: 0.35, alpha: 0.9)
    context.setStrokeColor(cueColor)
    context.setLineWidth(36)
    context.setLineCap(.round)
    context.addArc(center: CGPoint(x: 526, y: 520), radius: 252, startAngle: 0.12 * .pi, endAngle: 0.49 * .pi, clockwise: false)
    context.strokePath()

    strokeLine(in: context, from: CGPoint(x: 532, y: 772), to: CGPoint(x: 532, y: 826), width: 32, color: cueColor)
    strokeLine(in: context, from: CGPoint(x: 532, y: 826), to: CGPoint(x: 492, y: 786), width: 32, color: cueColor)
    strokeLine(in: context, from: CGPoint(x: 532, y: 826), to: CGPoint(x: 572, y: 786), width: 32, color: cueColor)
}

func drawInnerHighlight(in context: CGContext) {
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    context.setLineWidth(18)
    context.addPath(CGPath(roundedRect: CGRect(x: 26, y: 26, width: 972, height: 972), cornerWidth: 204, cornerHeight: 204, transform: nil))
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
