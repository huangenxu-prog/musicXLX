import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Unable to create icon bitmap")
}
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

// Background: deep navy diagonal gradient.
let bgColors = [
    CGColor(red: 0.16, green: 0.14, blue: 0.22, alpha: 1),
    CGColor(red: 0.055, green: 0.12, blue: 0.25, alpha: 1)
] as CFArray
let bg = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 1])!
context.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Sunset disc, 600 px diameter.
let disc = CGRect(x: 212, y: 212, width: 600, height: 600)
context.saveGState()
context.addEllipse(in: disc)
context.clip()
let sunsetColors = [
    CGColor(red: 1.0, green: 0.66, blue: 0.31, alpha: 1),
    CGColor(red: 1.0, green: 0.48, blue: 0.39, alpha: 1),
    CGColor(red: 0.91, green: 0.25, blue: 0.51, alpha: 1)
] as CFArray
let sunset = CGGradient(colorsSpace: colorSpace, colors: sunsetColors, locations: [0, 0.48, 1])!
context.drawLinearGradient(sunset, start: CGPoint(x: 512, y: 812), end: CGPoint(x: 512, y: 212), options: [])

// Horizon bands clipped to the disc.
context.setFillColor(CGColor(red: 0.045, green: 0.10, blue: 0.25, alpha: 1))
context.fill(CGRect(x: 180, y: 264, width: 664, height: 22))
context.setFillColor(CGColor(red: 0.035, green: 0.075, blue: 0.22, alpha: 1))
context.fill(CGRect(x: 180, y: 242, width: 664, height: 22))
context.restoreGState()

// Five warm-white rounded equalizer bars.
context.setFillColor(CGColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1))
let bars: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (326, 450, 52, 124),
    (406, 380, 52, 264),
    (486, 320, 52, 384),
    (566, 400, 52, 224),
    (646, 440, 52, 144)
]
for (x, y, w, h) in bars {
    let path = CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
    context.addPath(path)
    context.fillPath()
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Unable to encode icon")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write icon") }
