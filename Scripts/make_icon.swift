// Generates a simple 1024x1024 app icon (sun over horizon) with CoreGraphics.
// Run: swift Scripts/make_icon.swift <output.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// Sky gradient: deep blue (top) -> orange (horizon)
let skyColors = [
    CGColor(red: 0.10, green: 0.15, blue: 0.45, alpha: 1),
    CGColor(red: 0.35, green: 0.45, blue: 0.85, alpha: 1),
    CGColor(red: 1.00, green: 0.60, blue: 0.25, alpha: 1),
] as CFArray
let sky = CGGradient(colorsSpace: cs, colors: skyColors, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: Double(size) * 0.38), options: [.drawsAfterEndLocation])

// Sun
let sunCenter = CGPoint(x: Double(size) / 2, y: Double(size) * 0.40)
let sunRadius = Double(size) * 0.22
ctx.saveGState()
ctx.clip(to: CGRect(x: 0, y: Double(size) * 0.38, width: Double(size), height: Double(size)))
let sunColors = [
    CGColor(red: 1.0, green: 0.95, blue: 0.70, alpha: 1),
    CGColor(red: 1.0, green: 0.75, blue: 0.20, alpha: 1),
] as CFArray
let sunGrad = CGGradient(colorsSpace: cs, colors: sunColors, locations: [0, 1])!
ctx.addEllipse(in: CGRect(x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2))
ctx.clip()
ctx.drawRadialGradient(sunGrad, startCenter: sunCenter, startRadius: 0, endCenter: sunCenter, endRadius: sunRadius, options: [])
ctx.restoreGState()

// Ground / horizon band
ctx.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.16, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: Double(size), height: Double(size) * 0.38))

// Horizon lines
ctx.setStrokeColor(CGColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 0.9))
ctx.setLineCap(.round)
for (i, w) in [0.55, 0.40, 0.25].enumerated() {
    let y = Double(size) * (0.32 - Double(i) * 0.06)
    ctx.setLineWidth(Double(size) * 0.028)
    ctx.move(to: CGPoint(x: Double(size) * (0.5 - w / 2), y: y))
    ctx.addLine(to: CGPoint(x: Double(size) * (0.5 + w / 2), y: y))
    ctx.strokePath()
}

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: out) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
