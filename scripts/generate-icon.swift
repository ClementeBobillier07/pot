#!/usr/bin/env swift
// Original Pot artwork. Executed only by the macOS packaging script.
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-icon.swift OUTPUT.iconset\n", stderr)
    exit(1)
}
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func color(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255, alpha: 1)
}

func makePNG(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "Pot.Icon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    color(0xEDF1E8).setFill()
    NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 213, yRadius: 213).fill()

    color(0x52755B).setStroke()
    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: 514, y: 374))
    stem.curve(to: NSPoint(x: 545, y: 796), controlPoint1: NSPoint(x: 466, y: 558), controlPoint2: NSPoint(x: 550, y: 656))
    stem.lineWidth = 25
    stem.lineCapStyle = .round
    stem.stroke()

    for (rect, angle, hex) in [
        (NSRect(x: 291, y: 467, width: 220, height: 146), -28.0, UInt32(0x6E9D74)),
        (NSRect(x: 502, y: 572, width: 221, height: 153), 25.0, UInt32(0x91AF86)),
        (NSRect(x: 338, y: 659, width: 190, height: 135), -25.0, UInt32(0x507F5F))
    ] {
        NSGraphicsContext.saveGraphicsState()
        let rotation = NSAffineTransform()
        rotation.translateX(by: rect.midX, yBy: rect.midY)
        rotation.rotate(byDegrees: CGFloat(angle))
        rotation.concat()
        color(hex).setFill()
        NSBezierPath(ovalIn: NSRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    color(0xE8C6D7).setFill()
    for petal in 0..<5 {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 545, yBy: 795)
        transform.rotate(byDegrees: CGFloat(petal) * 72)
        transform.concat()
        NSBezierPath(ovalIn: NSRect(x: -34, y: 4, width: 68, height: 111)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    color(0xDDB85D).setFill()
    NSBezierPath(ovalIn: NSRect(x: 515, y: 765, width: 60, height: 60)).fill()
    color(0x74998F).setFill()
    NSBezierPath(roundedRect: NSRect(x: 325, y: 188, width: 374, height: 222), xRadius: 58, yRadius: 58).fill()
    color(0x89AA9E).setFill()
    NSBezierPath(roundedRect: NSRect(x: 310, y: 375, width: 404, height: 49), xRadius: 18, yRadius: 18).fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Pot.Icon", code: 2)
    }
    return data
}

for size in [16, 32, 128, 256, 512] {
    try makePNG(pixels: size).write(to: destination.appendingPathComponent("icon_\(size)x\(size).png"))
    try makePNG(pixels: size * 2).write(to: destination.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
