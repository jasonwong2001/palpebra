#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Original Palpebra artwork: a resting eyelid on the popup's deep-violet gradient.
// Everything is drawn with paths; no symbols, fonts, external images or GUI are used.
// Run from any directory with: swift /path/to/palpebra/scripts/make-icon.swift

enum IconError: LocalizedError {
    case bitmapUnavailable
    case pngUnavailable
    case toolFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .bitmapUnavailable: return "Could not create the icon's drawing context."
        case .pngUnavailable: return "Could not write the icon's master PNG."
        case .toolFailed(let tool, let status): return "\(tool) failed with exit status \(status)."
        }
    }
}

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw IconError.toolFailed(executable, process.terminationStatus)
    }
}

func drawMaster(at url: URL) throws {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw IconError.bitmapUnavailable }

    func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
    }

    // Apple's macOS icon grid: an 824 px body with continuous-curvature corners of radius 185.4.
    // Circular-arc corners look subtly off next to system icons, so the path comes from SwiftUI.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let silhouette = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: tile).cgPath

    // The transparent 100 px margin leaves room for the standard macOS icon shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 24, color: color(0.06, 0.02, 0.13, 0.28))
    context.addPath(silhouette)
    context.setFillColor(color(0.16, 0.10, 0.32))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(silhouette)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0.16, 0.10, 0.32), color(0.34, 0.18, 0.55)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // A quiet highlight and hairline rim give the tile depth without adding detail at small sizes.
    let highlight = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0.80, 0.70, 1, 0.12), color(0.80, 0.70, 1, 0)] as CFArray,
        locations: [0, 1])!
    context.drawRadialGradient(
        highlight, startCenter: CGPoint(x: 360, y: 860), startRadius: 0,
        endCenter: CGPoint(x: 360, y: 860), endRadius: 650, options: [])
    context.addPath(silhouette)
    context.setStrokeColor(color(0.91, 0.85, 1, 0.18))
    context.setLineWidth(4)
    context.strokePath()
    context.restoreGState()

    // One broad closed-lid curve and three short lashes stay readable at 16 x 16.
    let eyelid = CGMutablePath()
    eyelid.move(to: CGPoint(x: 278, y: 584))
    eyelid.addCurve(
        to: CGPoint(x: 746, y: 584), control1: CGPoint(x: 384, y: 410), control2: CGPoint(x: 640, y: 410))
    let lashes = CGMutablePath()
    lashes.move(to: CGPoint(x: 390, y: 472))
    lashes.addLine(to: CGPoint(x: 361, y: 433))
    lashes.move(to: CGPoint(x: 512, y: 444))
    lashes.addLine(to: CGPoint(x: 512, y: 392))
    lashes.move(to: CGPoint(x: 634, y: 472))
    lashes.addLine(to: CGPoint(x: 663, y: 433))

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -5), blur: 8, color: color(0.05, 0.02, 0.12, 0.25))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.setStrokeColor(color(0.97, 0.94, 1))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(42)
    context.addPath(lashes)
    context.strokePath()
    context.setLineWidth(46)
    context.addPath(eyelid)
    context.strokePath()
    context.endTransparencyLayer()
    context.restoreGState()

    guard let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw IconError.pngUnavailable }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.pngUnavailable }
}

// PNG-backed ICNS elements are supported on every macOS version Palpebra targets.
// Some sandboxed hosts reject even valid iconsets in iconutil; this keeps generation offline and reproducible.
func writePNGContainer(iconset: URL, to url: URL) throws {
    let representations = [
        ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
        ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png"),
    ]
    func sizeData(_ size: Int) -> Data {
        withUnsafeBytes(of: UInt32(size).bigEndian) { Data($0) }
    }
    var elements = Data()
    for (type, filename) in representations {
        let png = try Data(contentsOf: iconset.appendingPathComponent(filename))
        elements.append(Data(type.utf8))
        elements.append(sizeData(png.count + 8))
        elements.append(png)
    }
    var container = Data("icns".utf8)
    container.append(sizeData(elements.count + 8))
    container.append(elements)
    try container.write(to: url, options: .atomic)
}

do {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let resources = root.appendingPathComponent("Resources", isDirectory: true)
    let iconset = root.appendingPathComponent("build/AppIcon.iconset", isDirectory: true)
    let master = resources.appendingPathComponent("AppIcon.png")
    let icon = resources.appendingPathComponent("AppIcon.icns")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    try drawMaster(at: master)

    for size in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let suffix = scale == 2 ? "@2x" : ""
            let output = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
            let pixels = String(size * scale)
            try run("/usr/bin/sips", ["-z", pixels, pixels, master.path, "--out", output.path])
        }
    }
    do {
        try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", icon.path])
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription) Writing PNG-backed ICNS directly.\n".utf8))
        try writePNGContainer(iconset: iconset, to: icon)
    }
    print("Generated \(master.path) and \(icon.path)")
} catch {
    FileHandle.standardError.write(Data("Icon generation failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
