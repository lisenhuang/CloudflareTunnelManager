#!/usr/bin/env swift
//
// Generates the app icon: an original cloud mark in Cloudflare's orange palette
// (NOT the trademarked Cloudflare logo). Produces:
//   Resources/AppIcon.png   — 1024×1024 master (handy for previews / the web)
//   Resources/AppIcon.icns  — multi-resolution icon embedded in the .app bundle
//
// Run:  swift scripts/make-icon.swift
// To use your own artwork instead, replace Resources/AppIcon.png with a 1024×1024
// PNG and re-run (or just supply your own AppIcon.icns).
//
import AppKit
import Foundation

let resourcesDir = "Resources"

/// Draws the icon at an exact pixel size (re-drawn per size for crisp edges).
func cloudIcon(px: Int) -> Data {
    let S = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)

    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    let cg = nsCtx.cgContext

    // White rounded-square (macOS squircle-ish) tile.
    let margin = S * 0.055
    let bg = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let corner = bg.width * 0.2237
    cg.addPath(CGPath(roundedRect: bg, cornerWidth: corner, cornerHeight: corner, transform: nil))
    cg.setFillColor(NSColor.white.cgColor)
    cg.fillPath()

    // Cloud silhouette: union of three bumps + a flat base slab.
    let cloud = CGMutablePath()
    func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) {
        cloud.addEllipse(in: CGRect(x: (x - r) * S, y: (y - r) * S, width: 2 * r * S, height: 2 * r * S))
    }
    cloud.addRoundedRect(in: CGRect(x: 0.24 * S, y: 0.355 * S, width: 0.54 * S, height: 0.16 * S),
                         cornerWidth: 0.07 * S, cornerHeight: 0.07 * S)
    circle(0.380, 0.500, 0.115)
    circle(0.520, 0.550, 0.155)
    circle(0.655, 0.495, 0.125)

    // Fill the cloud with a top-light → bottom-dark orange gradient.
    cg.saveGState()
    cg.addPath(cloud)
    cg.clip()
    let light = NSColor(srgbRed: 0.984, green: 0.678, blue: 0.255, alpha: 1).cgColor // #FBAD41
    let dark  = NSColor(srgbRed: 0.965, green: 0.510, blue: 0.122, alpha: 1).cgColor // #F6821F
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [light, dark] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(grad, start: CGPoint(x: 0.5 * S, y: 0.70 * S),
                          end: CGPoint(x: 0.5 * S, y: 0.34 * S), options: [])
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
try? fm.createDirectory(atPath: resourcesDir, withIntermediateDirectories: true)
try cloudIcon(px: 1024).write(to: URL(fileURLWithPath: "\(resourcesDir)/AppIcon.png"))

let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let entries: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (px, name) in entries {
    try cloudIcon(px: px).write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "\(resourcesDir)/AppIcon.icns"]
try p.run()
p.waitUntilExit()
try? fm.removeItem(atPath: iconset)
print(p.terminationStatus == 0
      ? "✓ Wrote \(resourcesDir)/AppIcon.icns (+ AppIcon.png master)"
      : "✗ iconutil failed (status \(p.terminationStatus))")
exit(p.terminationStatus)
