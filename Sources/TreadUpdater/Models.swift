import AppKit
import CoreLocation
import Foundation

struct WheelCatalog: Decodable {
    let wheels: [ExistingWheel]
}

struct ExistingWheel: Decodable, Identifiable {
    let number: Int
    let lat: Double
    let lng: Double
    let image: String

    var id: Int { number }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

struct ImageInspection {
    let width: Int
    let height: Int
    let isPNG: Bool
    let isRGB: Bool
    let hasAlpha: Bool
    let isEightBit: Bool
    let preview: NSImage

    var summary: String {
        let format = isPNG ? "PNG" : "非PNG"
        let color = isRGB ? "RGB" : "非RGB"
        let depth = isEightBit ? "8-bit" : "非8-bit"
        return "\(width) × \(height) px ・ \(format) ・ \(color) ・ \(depth)"
    }
}

enum DraftIssueSeverity {
    case error
    case warning
}

struct DraftIssue: Identifiable {
    let severity: DraftIssueSeverity
    let message: String

    var id: String { "\(severity)-\(message)" }
}

struct PreviewPoint: Identifiable {
    enum Kind {
        case existing
        case draft(UUID)
    }

    let id: String
    let number: Int
    let coordinate: CLLocationCoordinate2D
    let kind: Kind
}
