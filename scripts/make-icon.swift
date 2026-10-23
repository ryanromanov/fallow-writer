// Draws Fallow's app icon, a fallow field under a pale sky, and writes it as an .icns file.
// Optionally also writes a PNG of the icon, as the macOS Dock rounds it, for the README.
//
//     swift scripts/make-icon.swift Fallow.app/Contents/Resources/AppIcon.icns [icon.png]
//     swift scripts/make-icon.swift --ios iOS/Fallow/Assets.xcassets/AppIcon.appiconset/AppIcon.png
//
// The iOS icon is one 1024-pixel PNG with no alpha channel, which the App Store requires.
//
// The art fills the whole square: macOS 26 rounds the corners and adds its own edge. An
// icon with its own transparent shape would be put on a gray plate instead.
//
// The sky and the soil split the square half and half. A pale sun sits in the sky, and a few
// broad, barely darker bands run across the soil to the horizon, like the rows of a field (and
// lines of writing). Each size is drawn from scratch rather than scaled down, so the small
// ones stay crisp.

import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

func gradient(_ context: CGContext, _ colors: [UInt32], from start: CGPoint, to end: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: colors.map { color($0) } as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Draws the icon on a 1024-point canvas, whatever the context's real size.
func drawIcon(_ context: CGContext) {
    let size = 1024.0, horizon = 512.0
    // Sky: Fallow's paper tones.
    gradient(context, [0xF6F1E7, 0xEADFCB], from: CGPoint(x: 0, y: size), to: CGPoint(x: 0, y: horizon))
    context.setFillColor(color(0xF3DFB8))
    context.fillEllipse(in: CGRect(x: 640, y: 700, width: 150, height: 150))

    // Soil: the loam brown of Fallow's insertion point, darker toward the front.
    context.saveGState()
    context.clip(to: CGRect(x: 0, y: 0, width: size, height: horizon))
    gradient(context, [0x6E4A33, 0xA77B55], from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: horizon))
    let vanishingPoint = CGPoint(x: 512, y: 760)
    context.setFillColor(color(0x3E281B, 0.13))
    for band in stride(from: -3, through: 3, by: 2) {
        let left = 512 + Double(band) * 230 - 115
        context.move(to: CGPoint(x: left, y: -20))
        context.addLine(to: CGPoint(x: left + 230, y: -20))
        context.addLine(to: vanishingPoint)
        context.closePath()
        context.fillPath()
    }
    context.restoreGState()
}

func image(pixels: Int, rounded: Bool = false, opaque: Bool = false) -> CGImage {
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: alpha.rawValue)!
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    if rounded {
        // About the Dock's rounding, for the README's picture only.
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                               cornerWidth: 230, cornerHeight: 230, transform: nil))
        context.clip()
    }
    drawIcon(context)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
}

let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "--ios" {
    try writePNG(image(pixels: 1024, opaque: true), to: URL(fileURLWithPath: arguments[2]))
    exit(0)
}
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: swift scripts/make-icon.swift AppIcon.icns [icon.png] | --ios AppIcon.png\n".data(using: .utf8)!)
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Fallow-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for points in [16, 32, 128, 256, 512] {
    try writePNG(image(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writePNG(image(pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(1) }
if arguments.count >= 3 {
    try writePNG(image(pixels: 256, rounded: true), to: URL(fileURLWithPath: arguments[2]))
}
