import AppKit
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// Renders the DMG installer window background: a dark charcoal gradient with
// soft radial glows in the app's accent colors. Sized 2x for an 800x470 window.

let W: CGFloat = 1600, H: CGFloat = 940
let rect = CGRect(x: 0, y: 0, width: W, height: H)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

let ctx = CGContext(
    data: nil,
    width: Int(W), height: Int(H),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: sRGB,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Dark charcoal diagonal gradient, slightly lighter through the middle band
let base = CGGradient(
    colorsSpace: sRGB,
    colors: [
        CGColor(srgbRed: 0.082, green: 0.090, blue: 0.106, alpha: 1),
        CGColor(srgbRed: 0.122, green: 0.134, blue: 0.150, alpha: 1),
        CGColor(srgbRed: 0.082, green: 0.090, blue: 0.106, alpha: 1),
    ] as CFArray,
    locations: [0, 0.55, 1])!
ctx.setFillColor(CGColor(srgbRed: 0.082, green: 0.090, blue: 0.106, alpha: 1))
ctx.fill(rect)
ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

// Soft radial glows in the accent colors, kept away from the middle icon row.
// Each fades to fully transparent; alpha stays very low so it stays subtle.
let glows: [(CGColor, CGFloat, CGPoint)] = [
    (CGColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 0.10), 620, CGPoint(x: W * 0.78, y: H * 0.92)),
    (CGColor(srgbRed: 0.20, green: 0.51, blue: 0.98, alpha: 0.09), 700, CGPoint(x: W * 0.15, y: H * 0.05)),
    (CGColor(srgbRed: 0.98, green: 0.55, blue: 0.14, alpha: 0.07), 480, CGPoint(x: W * 0.93, y: H * 0.28)),
]
for (color, radius, center) in glows {
    let grad = CGGradient(
        colorsSpace: sRGB,
        colors: [color, color.copy(alpha: 0)!] as CFArray,
        locations: [0, 1])!
    ctx.drawRadialGradient(
        grad,
        startCenter: center, startRadius: 0,
        endCenter: center, endRadius: radius,
        options: [])
}

let image = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png")
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("background written to \(out.path)")
