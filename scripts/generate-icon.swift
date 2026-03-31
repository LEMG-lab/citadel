#!/usr/bin/env swift
// Generates AppIcon.icns from DragonIcon shape for Smaug.app

import AppKit
import CryptoKit

// Dragon shape path (same as DragonShape in the app)
func dragonPath(in rect: NSRect) -> NSBezierPath {
    let w = rect.width
    let h = rect.height
    let p = NSBezierPath()

    p.move(to: NSPoint(x: 0.62 * w, y: h - 0.08 * h))
    // Crown
    p.curve(to: NSPoint(x: 0.48 * w, y: h - 0.04 * h),
            controlPoint1: NSPoint(x: 0.58 * w, y: h - 0.04 * h),
            controlPoint2: NSPoint(x: 0.53 * w, y: h - 0.02 * h))
    p.line(to: NSPoint(x: 0.40 * w, y: h - 0.0 * h))
    p.curve(to: NSPoint(x: 0.35 * w, y: h - 0.10 * h),
            controlPoint1: NSPoint(x: 0.38 * w, y: h - 0.04 * h),
            controlPoint2: NSPoint(x: 0.35 * w, y: h - 0.07 * h))
    // Forehead
    p.curve(to: NSPoint(x: 0.22 * w, y: h - 0.22 * h),
            controlPoint1: NSPoint(x: 0.32 * w, y: h - 0.14 * h),
            controlPoint2: NSPoint(x: 0.26 * w, y: h - 0.18 * h))
    p.line(to: NSPoint(x: 0.18 * w, y: h - 0.20 * h))
    // Eye socket
    p.curve(to: NSPoint(x: 0.16 * w, y: h - 0.30 * h),
            controlPoint1: NSPoint(x: 0.15 * w, y: h - 0.23 * h),
            controlPoint2: NSPoint(x: 0.14 * w, y: h - 0.27 * h))
    // Nose
    p.curve(to: NSPoint(x: 0.10 * w, y: h - 0.40 * h),
            controlPoint1: NSPoint(x: 0.15 * w, y: h - 0.34 * h),
            controlPoint2: NSPoint(x: 0.12 * w, y: h - 0.37 * h))
    // Snout
    p.curve(to: NSPoint(x: 0.04 * w, y: h - 0.50 * h),
            controlPoint1: NSPoint(x: 0.08 * w, y: h - 0.44 * h),
            controlPoint2: NSPoint(x: 0.05 * w, y: h - 0.47 * h))
    // Nostril
    p.curve(to: NSPoint(x: 0.06 * w, y: h - 0.54 * h),
            controlPoint1: NSPoint(x: 0.02 * w, y: h - 0.52 * h),
            controlPoint2: NSPoint(x: 0.03 * w, y: h - 0.54 * h))
    // Lower jaw
    p.curve(to: NSPoint(x: 0.08 * w, y: h - 0.58 * h),
            controlPoint1: NSPoint(x: 0.06 * w, y: h - 0.56 * h),
            controlPoint2: NSPoint(x: 0.07 * w, y: h - 0.57 * h))
    // Teeth
    p.line(to: NSPoint(x: 0.12 * w, y: h - 0.56 * h))
    p.line(to: NSPoint(x: 0.15 * w, y: h - 0.59 * h))
    p.line(to: NSPoint(x: 0.18 * w, y: h - 0.56 * h))
    p.line(to: NSPoint(x: 0.21 * w, y: h - 0.59 * h))
    // Jaw back
    p.curve(to: NSPoint(x: 0.35 * w, y: h - 0.62 * h),
            controlPoint1: NSPoint(x: 0.26 * w, y: h - 0.60 * h),
            controlPoint2: NSPoint(x: 0.30 * w, y: h - 0.62 * h))
    // Chin
    p.curve(to: NSPoint(x: 0.42 * w, y: h - 0.58 * h),
            controlPoint1: NSPoint(x: 0.38 * w, y: h - 0.62 * h),
            controlPoint2: NSPoint(x: 0.40 * w, y: h - 0.60 * h))
    // Neck
    p.curve(to: NSPoint(x: 0.50 * w, y: h - 0.55 * h),
            controlPoint1: NSPoint(x: 0.44 * w, y: h - 0.56 * h),
            controlPoint2: NSPoint(x: 0.47 * w, y: h - 0.55 * h))
    p.curve(to: NSPoint(x: 0.60 * w, y: h - 0.58 * h),
            controlPoint1: NSPoint(x: 0.54 * w, y: h - 0.56 * h),
            controlPoint2: NSPoint(x: 0.57 * w, y: h - 0.58 * h))
    // Wing
    p.curve(to: NSPoint(x: 0.78 * w, y: h - 0.42 * h),
            controlPoint1: NSPoint(x: 0.65 * w, y: h - 0.55 * h),
            controlPoint2: NSPoint(x: 0.72 * w, y: h - 0.48 * h))
    p.curve(to: NSPoint(x: 0.95 * w, y: h - 0.28 * h),
            controlPoint1: NSPoint(x: 0.84 * w, y: h - 0.36 * h),
            controlPoint2: NSPoint(x: 0.92 * w, y: h - 0.30 * h))
    // Wing scallops
    p.curve(to: NSPoint(x: 0.88 * w, y: h - 0.45 * h),
            controlPoint1: NSPoint(x: 0.96 * w, y: h - 0.34 * h),
            controlPoint2: NSPoint(x: 0.93 * w, y: h - 0.40 * h))
    p.curve(to: NSPoint(x: 0.92 * w, y: h - 0.52 * h),
            controlPoint1: NSPoint(x: 0.90 * w, y: h - 0.48 * h),
            controlPoint2: NSPoint(x: 0.92 * w, y: h - 0.50 * h))
    p.curve(to: NSPoint(x: 0.85 * w, y: h - 0.62 * h),
            controlPoint1: NSPoint(x: 0.93 * w, y: h - 0.56 * h),
            controlPoint2: NSPoint(x: 0.90 * w, y: h - 0.60 * h))
    p.curve(to: NSPoint(x: 0.80 * w, y: h - 0.72 * h),
            controlPoint1: NSPoint(x: 0.83 * w, y: h - 0.66 * h),
            controlPoint2: NSPoint(x: 0.81 * w, y: h - 0.70 * h))
    // Body
    p.curve(to: NSPoint(x: 0.70 * w, y: h - 0.80 * h),
            controlPoint1: NSPoint(x: 0.78 * w, y: h - 0.76 * h),
            controlPoint2: NSPoint(x: 0.74 * w, y: h - 0.79 * h))
    // Tail
    p.curve(to: NSPoint(x: 0.55 * w, y: h - 0.88 * h),
            controlPoint1: NSPoint(x: 0.65 * w, y: h - 0.82 * h),
            controlPoint2: NSPoint(x: 0.60 * w, y: h - 0.86 * h))
    p.curve(to: NSPoint(x: 0.48 * w, y: h - 0.95 * h),
            controlPoint1: NSPoint(x: 0.50 * w, y: h - 0.90 * h),
            controlPoint2: NSPoint(x: 0.47 * w, y: h - 0.93 * h))
    p.curve(to: NSPoint(x: 0.55 * w, y: h - 0.98 * h),
            controlPoint1: NSPoint(x: 0.49 * w, y: h - 0.97 * h),
            controlPoint2: NSPoint(x: 0.52 * w, y: h - 0.98 * h))
    // Tail underside
    p.curve(to: NSPoint(x: 0.62 * w, y: h - 0.85 * h),
            controlPoint1: NSPoint(x: 0.58 * w, y: h - 0.96 * h),
            controlPoint2: NSPoint(x: 0.61 * w, y: h - 0.90 * h))
    p.curve(to: NSPoint(x: 0.72 * w, y: h - 0.72 * h),
            controlPoint1: NSPoint(x: 0.64 * w, y: h - 0.80 * h),
            controlPoint2: NSPoint(x: 0.68 * w, y: h - 0.75 * h))
    // Back up
    p.curve(to: NSPoint(x: 0.68 * w, y: h - 0.50 * h),
            controlPoint1: NSPoint(x: 0.76 * w, y: h - 0.65 * h),
            controlPoint2: NSPoint(x: 0.74 * w, y: h - 0.56 * h))
    p.curve(to: NSPoint(x: 0.65 * w, y: h - 0.30 * h),
            controlPoint1: NSPoint(x: 0.66 * w, y: h - 0.42 * h),
            controlPoint2: NSPoint(x: 0.65 * w, y: h - 0.36 * h))
    // Spines
    p.line(to: NSPoint(x: 0.68 * w, y: h - 0.24 * h))
    p.line(to: NSPoint(x: 0.64 * w, y: h - 0.20 * h))
    p.line(to: NSPoint(x: 0.67 * w, y: h - 0.14 * h))
    p.curve(to: NSPoint(x: 0.62 * w, y: h - 0.08 * h),
            controlPoint1: NSPoint(x: 0.66 * w, y: h - 0.11 * h),
            controlPoint2: NSPoint(x: 0.64 * w, y: h - 0.09 * h))
    p.close()

    return p
}

// Generate icon
let size: CGFloat = 512
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Dark background with rounded rect
let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: size * 0.22, yRadius: size * 0.22)
NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0).setFill()
bgPath.fill()

// Subtle radial glow
let glowGradient = NSGradient(colors: [
    NSColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 0.08),
    NSColor.clear
])
glowGradient?.draw(in: bgPath, relativeCenterPosition: NSPoint(x: -0.1, y: 0.1))

// Dragon path with padding
let padding: CGFloat = size * 0.12
let dragonRect = NSRect(x: padding, y: padding, width: size - padding * 2, height: size - padding * 2)
let dragon = dragonPath(in: dragonRect)

// Gold gradient fill
let goldGradient = NSGradient(colors: [
    NSColor(red: 0.92, green: 0.75, blue: 0.20, alpha: 1.0),
    NSColor(red: 0.78, green: 0.55, blue: 0.12, alpha: 1.0),
    NSColor(red: 0.65, green: 0.40, blue: 0.08, alpha: 1.0),
])
goldGradient?.draw(in: dragon, angle: -45)

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
