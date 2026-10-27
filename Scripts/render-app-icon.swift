#!/usr/bin/env swift
// Renders Apps/Mac/Icon/scythe-icon.svg into the asset catalog: swift Scripts/render-app-icon.swift
import AppKit
import Foundation

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = root.appending(path: "Apps/Mac/Icon/scythe-icon.svg")
let catalog = root.appending(path: "Apps/Mac/Resources/Assets.xcassets")
let iconSet = catalog.appending(path: "AppIcon.appiconset")

guard let image = NSImage(contentsOf: source) else {
    FileHandle.standardError.write(Data("cannot read \(source.path)\n".utf8))
    exit(1)
}

try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

func render(pixels: Int, to url: URL) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { throw CocoaError(.fileWriteUnknown) }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])?.write(to: url)
}

struct Slot {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var name: String { "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png" }
}

let slots = [16, 32, 128, 256, 512].flatMap { [Slot(points: $0, scale: 1), Slot(points: $0, scale: 2)] }
for slot in slots {
    try render(pixels: slot.pixels, to: iconSet.appending(path: slot.name))
}

let images = slots.map {
    """
        { "filename" : "\($0.name)", "idiom" : "mac", "scale" : "\($0.scale)x", "size" : "\($0.points)x\($0.points)" }
    """
}.joined(separator: ",\n")
try """
{
  "images" : [
\(images)
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: iconSet.appending(path: "Contents.json"), atomically: true, encoding: .utf8)

try """
{
  "info" : { "author" : "xcode", "version" : 1 }
}

""".write(to: catalog.appending(path: "Contents.json"), atomically: true, encoding: .utf8)

print("wrote \(slots.count) icons to \(iconSet.path)")
