#!/usr/bin/swift

import AppKit
import Foundation

enum RenderError: Error, CustomStringConvertible {
    case usage
    case load(URL)
    case bitmap
    case context
    case encode
    case pdf(URL)

    var description: String {
        switch self {
        case .usage:
            "usage: render-svg <png|pdf> <input.svg> <output> <width> <height>"
        case .load(let url):
            "unable to load SVG at \(url.path)"
        case .bitmap:
            "unable to allocate bitmap"
        case .context:
            "unable to create graphics context"
        case .encode:
            "unable to encode PNG"
        case .pdf(let url):
            "unable to create PDF at \(url.path)"
        }
    }
}

func draw(_ image: NSImage, in rect: CGRect) {
    image.draw(
        in: rect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

func deterministicPDFIdentifier(for title: String) -> String {
    func fnv1a64(seed: UInt64) -> UInt64 {
        title.utf8.reduce(seed) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }

    let first = fnv1a64(seed: 14_695_981_039_346_656_037)
    let second = fnv1a64(seed: 7_806_847_911_596_045_841)
    return String(format: "%016llx%016llx", first, second)
}

func normalizePDFMetadata(at output: URL) throws {
    let data = try Data(contentsOf: output)
    guard var contents = String(data: data, encoding: String.Encoding.isoLatin1) else {
        throw RenderError.encode
    }
    contents = contents.replacingOccurrences(
        of: #"D:\d{14}Z00'\d{2}'"#,
        with: "D:20260730000000Z00'00'",
        options: String.CompareOptions.regularExpression
    )

    let identifier = deterministicPDFIdentifier(
        for: output.deletingPathExtension().lastPathComponent
    )
    contents = contents.replacingOccurrences(
        of: #"/ID \[ <[0-9a-fA-F]{32}>\s*<[0-9a-fA-F]{32}> \]"#,
        with: "/ID [ <\(identifier)>\n<\(identifier)> ]",
        options: String.CompareOptions.regularExpression
    )

    guard let normalized = contents.data(using: String.Encoding.isoLatin1) else {
        throw RenderError.encode
    }
    try normalized.write(to: output, options: Data.WritingOptions.atomic)

    guard let provider = CGDataProvider(url: output as CFURL),
          let document = CGPDFDocument(provider),
          document.numberOfPages == 1 else {
        throw RenderError.pdf(output)
    }
}

func renderPNG(image: NSImage, output: URL, width: Int, height: Int) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: NSColorSpaceName.deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { throw RenderError.bitmap }

    bitmap.size = NSSize(width: width, height: height)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw RenderError.context
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = NSImageInterpolation.high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(
        using: NSBitmapImageRep.FileType.png,
        properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 1.0]
    ) else { throw RenderError.encode }
    try data.write(to: output, options: Data.WritingOptions.atomic)
}

func renderPDF(image: NSImage, output: URL, width: Int, height: Int) throws {
    guard let consumer = CGDataConsumer(url: output as CFURL) else {
        throw RenderError.pdf(output)
    }
    var mediaBox = CGRect(x: 0, y: 0, width: width, height: height)
    let metadata: [CFString: Any] = [
        kCGPDFContextCreator: "Lerro deterministic asset renderer",
        kCGPDFContextTitle: output.deletingPathExtension().lastPathComponent
    ]
    guard let context = CGContext(
        consumer: consumer,
        mediaBox: &mediaBox,
        metadata as CFDictionary
    ) else { throw RenderError.pdf(output) }

    context.beginPDFPage(nil)
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    draw(image, in: mediaBox)
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    try normalizePDFMetadata(at: output)
}

do {
    let arguments = CommandLine.arguments
    guard arguments.count == 6,
          let width = Int(arguments[4]),
          let height = Int(arguments[5]),
          width > 0,
          height > 0 else {
        throw RenderError.usage
    }

    let format = arguments[1]
    let input = URL(fileURLWithPath: arguments[2]).standardizedFileURL
    let output = URL(fileURLWithPath: arguments[3]).standardizedFileURL
    guard let image = NSImage(contentsOf: input) else { throw RenderError.load(input) }

    try FileManager.default.createDirectory(
        at: output.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    switch format {
    case "png":
        try renderPNG(image: image, output: output, width: width, height: height)
    case "pdf":
        try renderPDF(image: image, output: output, width: width, height: height)
    default:
        throw RenderError.usage
    }
} catch {
    FileHandle.standardError.write(Data("render-svg: \(error)\n".utf8))
    exit(1)
}
