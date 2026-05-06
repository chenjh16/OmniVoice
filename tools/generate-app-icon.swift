#!/usr/bin/env swift

import AppKit
import Foundation

struct IconVariant {
    let filename: String
    let pixels: Int
    let isSmallVariant: Bool
}

let variants: [IconVariant] = [
    IconVariant(filename: "icon_16x16.png", pixels: 16, isSmallVariant: true),
    IconVariant(filename: "icon_16x16@2x.png", pixels: 32, isSmallVariant: true),
    IconVariant(filename: "icon_32x32.png", pixels: 32, isSmallVariant: true),
    IconVariant(filename: "icon_32x32@2x.png", pixels: 64, isSmallVariant: true),
    IconVariant(filename: "icon_128x128.png", pixels: 128, isSmallVariant: false),
    IconVariant(filename: "icon_128x128@2x.png", pixels: 256, isSmallVariant: false),
    IconVariant(filename: "icon_256x256.png", pixels: 256, isSmallVariant: false),
    IconVariant(filename: "icon_256x256@2x.png", pixels: 512, isSmallVariant: false),
    IconVariant(filename: "icon_512x512.png", pixels: 512, isSmallVariant: false)
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetURL = root.appendingPathComponent(".build/AppIcon.iconset")
let previewURL = root.appendingPathComponent(".build/icon-preview")
let outputURL = root.appendingPathComponent("Resources/AppIcon.icns")

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: previewURL, withIntermediateDirectories: true)

let masterIcon = drawIcon(pixels: 1024, small: false)
for variant in variants {
    let image = variant.isSmallVariant
        ? resizeImage(masterIcon, pixels: variant.pixels)
        : drawIcon(pixels: variant.pixels, small: false)
    let data = pngData(for: image)
    try data.write(to: iconsetURL.appendingPathComponent(variant.filename))
    try data.write(to: previewURL.appendingPathComponent(variant.filename))
}

try? FileManager.default.removeItem(at: outputURL)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}

func drawIcon(pixels: Int, small: Bool) -> NSImage {
    let size = CGFloat(pixels)
    return bitmapImage(pixels: pixels) {
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()

        let outerInset = max(1, size * (small ? 0.025 : 0.055))
        let outerRect = NSRect(x: outerInset, y: outerInset, width: size - outerInset * 2, height: size - outerInset * 2)
        let outerRadius = size * (small ? 0.21 : 0.23)
        let outerShell = NSBezierPath(roundedRect: outerRect, xRadius: outerRadius, yRadius: outerRadius)

        if pixels >= 32 {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = size * (small ? 0.045 : 0.035)
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.010)
            shadow.shadowColor = NSColor.black.withAlphaComponent(small ? 0.20 : 0.24)
            shadow.set()
        }

        let shellGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.955, green: 0.965, blue: 0.975, alpha: 1.0),
            NSColor(calibratedRed: 0.690, green: 0.725, blue: 0.765, alpha: 1.0)
        ])!
        shellGradient.draw(in: outerShell, angle: -90)

        NSColor.white.withAlphaComponent(0.78).setStroke()
        outerShell.lineWidth = max(1, size * 0.010)
        outerShell.stroke()

        NSGraphicsContext.current?.saveGraphicsState()
        outerShell.addClip()
        let shellShade = NSBezierPath(
            roundedRect: NSRect(x: outerRect.minX, y: outerRect.minY, width: outerRect.width, height: outerRect.height * 0.45),
            xRadius: outerRadius,
            yRadius: outerRadius
        )
        NSColor.black.withAlphaComponent(0.08).setFill()
        shellShade.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        let innerInset = max(2, size * (small ? 0.100 : 0.125))
        let innerRect = outerRect.insetBy(dx: innerInset, dy: innerInset)
        let innerRadius = size * (small ? 0.135 : 0.150)
        let innerCore = NSBezierPath(roundedRect: innerRect, xRadius: innerRadius, yRadius: innerRadius)

        let innerGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.145, green: 0.175, blue: 0.225, alpha: 1.0),
            NSColor(calibratedRed: 0.085, green: 0.105, blue: 0.145, alpha: 1.0)
        ])!
        innerGradient.draw(in: innerCore, angle: -90)

        NSGraphicsContext.current?.saveGraphicsState()
        innerCore.addClip()
        let innerHighlight = NSBezierPath(
            roundedRect: NSRect(x: innerRect.minX, y: innerRect.midY, width: innerRect.width, height: innerRect.height * 0.50),
            xRadius: innerRadius,
            yRadius: innerRadius
        )
        NSColor.white.withAlphaComponent(small ? 0.050 : 0.040).setFill()
        innerHighlight.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor(calibratedRed: 0.31, green: 0.38, blue: 0.50, alpha: 0.42).setStroke()
        innerCore.lineWidth = max(1, size * 0.005)
        innerCore.stroke()

        let waveformRect = innerRect.insetBy(dx: size * 0.075, dy: size * 0.055)
        drawWaveform(in: waveformRect, size: size, small: small)
    }
}

func resizeImage(_ source: NSImage, pixels: Int) -> NSImage {
    let size = CGFloat(pixels)
    return bitmapImage(pixels: pixels) {
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: NSRect(x: 0, y: 0, width: source.size.width, height: source.size.height),
            operation: .copy,
            fraction: 1.0
        )
    }
}

func bitmapImage(pixels: Int, drawing: () -> Void) -> NSImage {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Could not create bitmap representation")
    }
    let size = NSSize(width: CGFloat(pixels), height: CGFloat(pixels))
    representation.size = size

    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        fatalError("Could not create bitmap context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    drawing()
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: size)
    image.addRepresentation(representation)
    return image
}

func drawWaveform(in rect: NSRect, size: CGFloat, small: Bool) {
    let heights: [CGFloat] = [0.54, 0.82, 0.62, 0.36, 0.66, 0.46]
    let maxHeight = rect.height * 0.66
    let barWidth = max(1.2, rect.width * 0.100)
    let spacing = max(0.9, rect.width * 0.045)
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * spacing
    var x = rect.midX - totalWidth / 2

    let fill = NSColor(calibratedWhite: 0.96, alpha: 1.0)
    fill.setFill()

    for heightFactor in heights {
        let height = max(barWidth * 1.8, maxHeight * heightFactor)
        let barRect = NSRect(
            x: x,
            y: rect.midY - height / 2,
            width: barWidth,
            height: height
        )
        NSBezierPath(
            roundedRect: barRect,
            xRadius: barWidth / 2,
            yRadius: barWidth / 2
        ).fill()
        x += barWidth + spacing
    }
}

func pngData(for image: NSImage) -> Data {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG")
    }
    return png
}
