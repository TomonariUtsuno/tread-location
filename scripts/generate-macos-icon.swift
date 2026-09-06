#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IconGenerationError: LocalizedError {
    case unableToReadSource(URL)
    case unableToCreateContext
    case unableToCreateDestination(URL)
    case unableToWrite(URL)

    var errorDescription: String? {
        switch self {
        case let .unableToReadSource(url):
            "Unable to read icon source: \(url.path)"
        case .unableToCreateContext:
            "Unable to create an sRGB icon drawing context."
        case let .unableToCreateDestination(url):
            "Unable to create icon output: \(url.path)"
        case let .unableToWrite(url):
            "Unable to write icon output: \(url.path)"
        }
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: generate-macos-icon.swift SOURCE.png OUTPUT.iconset\\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let iconsetURL = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
else {
    throw IconGenerationError.unableToReadSource(sourceURL)
}

let sourceWidth = CGFloat(sourceImage.width)
let sourceHeight = CGFloat(sourceImage.height)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let iconSizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for (filename, size) in iconSizes {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconGenerationError.unableToCreateContext
    }

    let outputSize = CGFloat(size)
    let scale = min(outputSize / sourceWidth, outputSize / sourceHeight)
    let drawWidth = sourceWidth * scale
    let drawHeight = sourceHeight * scale
    let destination = CGRect(
        x: (outputSize - drawWidth) / 2,
        y: (outputSize - drawHeight) / 2,
        width: drawWidth,
        height: drawHeight
    )

    context.clear(CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
    context.interpolationQuality = .high
    context.draw(sourceImage, in: destination)

    let outputURL = iconsetURL.appendingPathComponent(filename)
    guard let outputImage = context.makeImage() else {
        throw IconGenerationError.unableToCreateContext
    }
    guard let destinationWriter = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw IconGenerationError.unableToCreateDestination(outputURL)
    }
    CGImageDestinationAddImage(destinationWriter, outputImage, nil)
    guard CGImageDestinationFinalize(destinationWriter) else {
        throw IconGenerationError.unableToWrite(outputURL)
    }
}
