#!/usr/bin/env swift
// Generates AppIcon.icns for Smaug.app
// Design: dark charcoal background, gold shield outline, gold "S"

import AppKit

// Shield path (classic pointed-bottom shield)
func shieldPath(in rect: NSRect) -> NSBezierPath {
    let w = rect.width
    let h = rect.height
    let ox = rect.origin.x
    let oy = rect.origin.y
    let p = NSBezierPath()

    // Start at top-left of shield
    p.move(to: NSPoint(x: ox + 0.10 * w, y: oy + h - 0.05 * h))

    // Top edge
    p.line(to: NSPoint(x: ox + 0.90 * w, y: oy + h - 0.05 * h))

    // Right edge curves down
    p.curve(to: NSPoint(x: ox + 0.90 * w, y: oy + h - 0.45 * h),
            controlPoint1: NSPoint(x: ox + 0.90 * w, y: oy + h - 0.15 * h),
            controlPoint2: NSPoint(x: ox + 0.90 * w, y: oy + h - 0.30 * h))

    // Right side tapers to bottom point
    p.curve(to: NSPoint(x: ox + 0.50 * w, y: oy + 0.02 * h),
            controlPoint1: NSPoint(x: ox + 0.90 * w, y: oy + h - 0.60 * h),
            controlPoint2: NSPoint(x: ox + 0.72 * w, y: oy + 0.15 * h))

    // Left side from bottom point
    p.curve(to: NSPoint(x: ox + 0.10 * w, y: oy + h - 0.45 * h),
            controlPoint1: NSPoint(x: ox + 0.28 * w, y: oy + 0.15 * h),
            controlPoint2: NSPoint(x: ox + 0.10 * w, y: oy + h - 0.60 * h))

    // Left edge back up
    p.curve(to: NSPoint(x: ox + 0.10 * w, y: oy + h - 0.05 * h),
            controlPoint1: NSPoint(x: ox + 0.10 * w, y: oy + h - 0.30 * h),
            controlPoint2: NSPoint(x: ox + 0.10 * w, y: oy + h - 0.15 * h))

    p.close()
    return p
}

// Generate icon
let size: CGFloat = 512
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Dark charcoal background with rounded rect (macOS icon shape)
let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.22, yRadius: size * 0.22)

// #1C1C1E
NSColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0).setFill()
bgPath.fill()

// Subtle warm glow behind shield
let glowGradient = NSGradient(colors: [
    NSColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 0.06),
    NSColor.clear
])
glowGradient?.draw(in: bgPath, relativeCenterPosition: NSPoint(x: 0.0, y: 0.05))

// Shield outline
let shieldPadding: CGFloat = size * 0.14
let shieldRect = NSRect(x: shieldPadding, y: shieldPadding * 0.8,
                        width: size - shieldPadding * 2, height: size - shieldPadding * 1.6)
let shield = shieldPath(in: shieldRect)

// Gold gradient for shield stroke
let goldStroke = NSGradient(colors: [
    NSColor(red: 0.92, green: 0.75, blue: 0.22, alpha: 1.0),
    NSColor(red: 0.80, green: 0.58, blue: 0.14, alpha: 1.0),
    NSColor(red: 0.68, green: 0.45, blue: 0.10, alpha: 1.0),
])

// Draw shield outline via clipping
shield.lineWidth = size * 0.025
NSGraphicsContext.current?.saveGraphicsState()
shield.setClip()
goldStroke?.draw(in: shield.bounds, angle: -45)
NSGraphicsContext.current?.restoreGraphicsState()

// Now draw just the stroke
NSColor(red: 0.88, green: 0.70, blue: 0.18, alpha: 1.0).setStroke()
shield.lineWidth = size * 0.022
shield.stroke()

// Inner shield stroke for depth
NSColor(red: 0.92, green: 0.78, blue: 0.30, alpha: 0.3).setStroke()
shield.lineWidth = size * 0.012
shield.stroke()

// Gold "S" letter centered in shield
let fontSize = size * 0.42
let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(red: 0.90, green: 0.72, blue: 0.18, alpha: 1.0),
    .paragraphStyle: paragraphStyle,
]

let sString = NSAttributedString(string: "S", attributes: attrs)
let sSize = sString.size()
let sOrigin = NSPoint(
    x: (size - sSize.width) / 2,
    y: (size - sSize.height) / 2 - size * 0.02
)
sString.draw(at: sOrigin)

image.unlockFocus()

// Save as PNG
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG")
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! png.write(to: URL(fileURLWithPath: outputPath))
print("Generated \(outputPath) (\(size)x\(size))")
