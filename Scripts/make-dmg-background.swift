import AppKit
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// Renders two DMG backgrounds: dmg-background.png (800x470) and
// dmg-background@2x.png (1600x940). All geometry is in 1x WINDOW points
// (origin top-left, y down); render() converts to CG space.
// OpenCode flavor: charcoal-dotted arrow, green/blue/orange accents —
// the same bars shown in the menu-bar item.

let charcoal = CGColor(srgbRed: 0.09, green: 0.098, blue: 0.109, alpha: 1)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let write2x = CommandLine.arguments.contains("--2x")

// Icon slots: app center (200,280), Applications (600,280), 128 px wide.
let arcStart   = CGPoint(x: 268, y: 300) // inside the icon gap
let arcEnd     = CGPoint(x: 532, y: 300)
let arcControl = CGPoint(x: 400, y: 322)

func render(_ out: String, _ s: CGFloat) {
    let W: CGFloat = 800 * s, H: CGFloat = 470 * s
    let ctx = CGContext(
        data: nil, width: Int(W), height: Int(H),
        bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let C = { (x: CGFloat, _ y: CGFloat) -> CGPoint in CGPoint(x: x * s, y: H - y * s) }

    // Airy light gradient so black Finder labels stay readable
    let base = CGGradient(
        colorsSpace: srgb,
        colors: [
            CGColor(srgbRed: 0.978, green: 0.986, blue: 0.988, alpha: 1),
            CGColor(srgbRed: 0.910, green: 0.945, blue: 0.937, alpha: 1),
            CGColor(srgbRed: 0.867, green: 0.918, blue: 0.918, alpha: 1),
        ] as CFArray,
        locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])
    let glows: [(CGColor, CGFloat, CGPoint)] = [
        (CGColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 0.08), 260 * s, CGPoint(x: W * 0.84, y: H)),
        (CGColor(srgbRed: 0.20, green: 0.51, blue: 0.98, alpha: 0.08), 280 * s, CGPoint(x: W * 0.10, y: H)),
        (CGColor(srgbRed: 0.98, green: 0.55, blue: 0.14, alpha: 0.05), 220 * s, CGPoint(x: W * 0.94, y: H * 0.42)),
    ]
    for (color, radius, center) in glows {
        let grad = CGGradient(colorsSpace: srgb, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(grad, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    // Dotted arrow dipping between the icons
    let start = C(arcStart.x, arcStart.y)
    let end = C(arcEnd.x, arcEnd.y)
    let ctrl = C(arcControl.x, arcControl.y)
    var ux = end.x - ctrl.x, uy = end.y - ctrl.y
    let tl = sqrt(ux * ux + uy * uy)
    ux /= tl; uy /= tl
    let tip = CGPoint(x: end.x + ux * 7 * s, y: end.y + uy * 7 * s)
    let headS: CGFloat = 9 * s

    ctx.saveGState()
    ctx.setStrokeColor(charcoal.copy(alpha: 0.55)!)
    ctx.setLineWidth(1.6 * s)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [0.1, 11 * s])
    let arc = CGMutablePath()
    arc.move(to: start)
    arc.addQuadCurve(to: end, control: ctrl)
    ctx.addPath(arc)
    ctx.strokePath()
    let w1 = CGPoint(x: tip.x - ux * headS - uy * headS * 0.55, y: tip.y - uy * headS + ux * headS * 0.55)
    let w2 = CGPoint(x: tip.x - ux * headS + uy * headS * 0.55, y: tip.y - uy * headS - ux * headS * 0.55)
    let head = CGMutablePath()
    head.move(to: tip)
    head.addLine(to: w1)
    head.addLine(to: w2)
    head.closeSubpath()
    ctx.setFillColor(charcoal.copy(alpha: 0.6)!)
    ctx.addPath(head)
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    // "drag" riding the arc's left descending segment
    let font = NSFont.systemFont(ofSize: 20 * s, weight: .semibold)
    let line = NSAttributedString(string: "drag", attributes: [
        .font: font,
        .foregroundColor: NSColor(cgColor: charcoal)!,
    ])
    let t: CGFloat = 0.25
    let wx = (1 - t) * (1 - t) * arcStart.x + 2 * t * (1 - t) * arcControl.x + t * t * arcEnd.x
    let wy = (1 - t) * (1 - t) * arcStart.y + 2 * t * (1 - t) * arcControl.y + t * t * arcEnd.y
    var dx = 2 * (1 - t) * (arcControl.x - arcStart.x) + 2 * t * (arcEnd.x - arcControl.x)
    var dy = 2 * (1 - t) * (arcControl.y - arcStart.y) + 2 * t * (arcEnd.y - arcControl.y)
    let dlen = sqrt(dx * dx + dy * dy)
    dx /= dlen; dy /= dlen
    let nwx = dy, nwy = -dx                       // up-normal in window space
    let sign: CGFloat = nwy < 0 ? 1 : -1
    let nl = sqrt(nwx * nwx + nwy * nwy)
    let tx = wx + sign * nwx / nl * 12
    let ty = wy + sign * nwy / nl * 12
    let size = line.size()
    ctx.saveGState()
    ctx.translateBy(x: tx * s, y: H - ty * s)
    ctx.rotate(by: -atan2(-sign * -dy, dx))
    line.draw(at: CGPoint(x: -size.width / 2, y: -size.height * 0.32))
    ctx.restoreGState()

    // tiny package sitting near the arrowhead (drag → Applications)
    let pkg = NSAttributedString(string: "📦", attributes: [.font: NSFont.systemFont(ofSize: 18 * s)])
    let psize = pkg.size()
    pkg.draw(at: CGPoint(x: 520 * s - psize.width / 2, y: H - 328 * s - psize.height / 2))

    // accent sparks in the bar colors, away from the icon band
    func star(_ x: CGFloat, _ y: CGFloat, _ r1: CGFloat, _ color: CGColor, _ alpha: CGFloat) {
        let c = C(x, y), r = r1 * s
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: c.y + r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * 0.12, y: c.y + r * 0.12))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + r * 0.12, y: c.y - r * 0.12))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * 0.12, y: c.y - r * 0.12))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - r * 0.12, y: c.y + r * 0.12))
        ctx.addPath(p)
        ctx.setFillColor(color.copy(alpha: alpha)!)
        ctx.fillPath()
    }
    star(150, 150, 7, CGColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1), 0.30)
    star(662, 143, 6, CGColor(srgbRed: 0.20, green: 0.51, blue: 0.98, alpha: 1), 0.28)
    star(744, 352, 5, CGColor(srgbRed: 0.98, green: 0.55, blue: 0.14, alpha: 1), 0.26)

    NSGraphicsContext.restoreGraphicsState()
    let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    print("rendered \(out) \(Int(W))x\(Int(H))")
}

render("dmg-background.png", 1)
if write2x { render("dmg-background@2x.png", 2) }
