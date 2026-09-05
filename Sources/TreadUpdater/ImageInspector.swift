import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageInspectionError: LocalizedError {
    case unreadable

    var errorDescription: String? { "画像を読み込めませんでした。" }
}

enum ImageInspector {
    static func inspect(url: URL) throws -> ImageInspection {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let preview = NSImage(contentsOf: url)
        else {
            throw ImageInspectionError.unreadable
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? image.width
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? image.height
        let typeIdentifier = CGImageSourceGetType(source) as String? ?? ""
        let isPNG = UTType(typeIdentifier)?.conforms(to: .png) ?? false
        let isRGB = image.colorSpace?.model == .rgb
        let alphaValues: Set<CGImageAlphaInfo> = [.first, .last, .premultipliedFirst, .premultipliedLast]

        return ImageInspection(
            width: width,
            height: height,
            isPNG: isPNG,
            isRGB: isRGB,
            hasAlpha: alphaValues.contains(image.alphaInfo),
            isEightBit: image.bitsPerComponent == 8,
            preview: preview
        )
    }
}
