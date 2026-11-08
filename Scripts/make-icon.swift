import AppKit
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// Renders the OpenCode Usage menu-bar app icon: three usage bars on a dark tile,
// matching the live status-bar view (UsageBarView).

struct Renderer {
    static func draw(size: CGFloat) -> CGImage? {
        let s = size / 1024.0
        let ctx = CGContext(
            data: nil,
            width: Int(size), height: Int(size),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

        // macOS-style rounded tile
        let inset: CGFloat = 24 * s
        let tile = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let radius = tile.width * 0.22
        ctx.saveGState()
        let path = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.clip()

        // Deep charcoal gradient background
        let colors = [
            CGColor(srgbRed: 0.118, green: 0.129, blue: 0.145, alpha: 1),
            CGColor(srgbRed: 0.082, green: 0.090, blue: 0.106, alpha: 1),
        ] as CFArray
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: tile.midX, y: tile.maxY),
            end: CGPoint(x: tile.midX, y: tile.minY),
            options: [])

        // Bars: green 80%, blue 55%, orange 30% — app accent colors
        let barColors: [CGColor] = [
            CGColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
            CGColor(srgbRed: 0.20, green: 0.51, blue: 0.98, alpha: 1),
            CGColor(srgbRed: 0.98, green: 0.55, blue: 0.14, alpha: 1),
        ]
        let fills: [CGFloat] = [0.80, 0.55, 0.30]
        let trackColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)

        let barWidth = tile.width * 0.60
        let barHeight = tile.width * 0.075
        let gap = tile.width * 0.085
        let blockX = tile.minX + (tile.width - barWidth) / 2
        let totalHeight = barHeight * 3 + gap * 2
        let startY = tile.midY - totalHeight / 2

        // Soft glow behind the bars
        ctx.saveGState()
        ctx.setShadow(
            offset: .zero,
            blur: tile.width * 0.04,
            color: CGColor(srgbRed: 0.3, green: 0.9, blue: 0.8, alpha: 0.28))
        for (i, color) in barColors.enumerated() {
            let y = tile.maxY - startY - (CGFloat(i) + 1) * barHeight - CGFloat(i) * gap
            let fill = CGRect(x: blockX, y: y, width: barWidth * fills[i], height: barHeight)
            ctx.setFillColor(color)
            ctx.addPath(CGPath(roundedRect: fill, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()

        for (i, color) in barColors.enumerated() {
            let y = tile.maxY - startY - (CGFloat(i) + 1) * barHeight - CGFloat(i) * gap
            let track = CGRect(x: blockX, y: y, width: barWidth, height: barHeight)
            ctx.setFillColor(trackColor)
            ctx.addPath(CGPath(roundedRect: track, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
            ctx.fillPath()

            let fill = CGRect(x: blockX, y: y, width: barWidth * fills[i], height: barHeight)
            ctx.setFillColor(color)
            ctx.addPath(CGPath(roundedRect: fill, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()

        return ctx.makeImage()
    }
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let specs: [(String, Int)] = [
    ("Icon-16.png", 16), ("Icon-16@2x.png", 32),
    ("Icon-32.png", 32), ("Icon-32@2x.png", 64),
    ("Icon-128.png", 128), ("Icon-128@2x.png", 256),
    ("Icon-256.png", 256), ("Icon-256@2x.png", 512),
    ("Icon-512.png", 512), ("Icon-512@2x.png", 1024),
]

// macOS Betsey Ross: anti-alias is on by default with CG. Render supersampled for small sizes.
for (name, px) in specs {
    let image: CGImage?
    if px < 64 {
        image = Renderer.draw(size: CGFloat(px * 4))?.resampled(to: px)
    } else {
        image = Renderer.draw(size: CGFloat(px))
    }
    guard let image else {
        FileHandle.standardError.write(Data("render failed for \(name)\n".utf8))
        continue
    }
    let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
print("icons written to \(dir)")

extension CGImage {
    func resampled(to pixel: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: pixel, height: pixel,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)! as CGContext
        ctx.interpolationQuality = .high
        ctx.draw(self, in: CGRect(x: 0, y: 0, width: pixel, height: pixel))
        return ctx.makeImage()!
    }
}
