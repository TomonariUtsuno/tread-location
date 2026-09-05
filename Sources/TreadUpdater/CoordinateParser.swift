import Foundation

enum CoordinateInputError: LocalizedError, Equatable {
    case empty
    case format
    case minuteRange
    case secondRange
    case latitudeRange
    case longitudeRange
    case likelyReversed
    case cardinalDirections

    var errorDescription: String? {
        switch self {
        case .empty: "座標を入力してください。"
        case .format: "N/S/E/W付きの度分秒形式、または「緯度, 経度」の十進形式で入力してください。"
        case .minuteRange: "分は60未満で入力してください。"
        case .secondRange: "秒は60未満で入力してください。"
        case .latitudeRange: "緯度は -90〜90 の範囲で入力してください。"
        case .longitudeRange: "経度は -180〜180 の範囲で入力してください。"
        case .likelyReversed: "先頭の値は緯度の範囲外です。緯度と経度が逆の可能性があります。"
        case .cardinalDirections: "度分秒形式にはN/Sを1つ、E/Wを1つ指定してください。"
        }
    }
}

struct ParsedCoordinates: Equatable {
    enum InputFormat: Equatable {
        case dms
        case decimal
    }

    let lat: Decimal
    let lng: Decimal
    let inputFormat: InputFormat
    let warnings: [String]

    var latitudeText: String { CoordinateParser.previewFormatter.string(from: NSDecimalNumber(decimal: lat)) ?? "" }
    var longitudeText: String { CoordinateParser.previewFormatter.string(from: NSDecimalNumber(decimal: lng)) ?? "" }
}

enum CoordinateParser {
    private static let locale = Locale(identifier: "en_US_POSIX")
    static let previewFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        return formatter
    }()

    private static let decimalPattern = try! NSRegularExpression(
        pattern: "^\\s*([+-]?\\d+(?:\\.\\d+)?)\\s*,\\s*([+-]?\\d+(?:\\.\\d+)?)\\s*$"
    )
    private static let dmsPattern = try! NSRegularExpression(
        pattern: "^\\s*([NSEW])\\s*(\\d{1,3})\\s*°\\s*(\\d+(?:\\.\\d+)?)\\s*'\\s*(\\d+(?:\\.\\d+)?)\\s*\"\\s*,?\\s*([NSEW])\\s*(\\d{1,3})\\s*°\\s*(\\d+(?:\\.\\d+)?)\\s*'\\s*(\\d+(?:\\.\\d+)?)\\s*\"\\s*$"
    )

    static func parse(_ input: String) throws -> ParsedCoordinates {
        let normalized = normalize(input)
        guard !normalized.isEmpty else { throw CoordinateInputError.empty }

        if let values = match(decimalPattern, in: normalized) {
            let lat = try decimal(values[0])
            let lng = try decimal(values[1])
            try validate(lat: lat, lng: lng)
            return ParsedCoordinates(
                lat: lat,
                lng: lng,
                inputFormat: .decimal,
                warnings: ["方位記号のない十進形式を「緯度, 経度」の順として解釈しました。公開前に地図を確認してください。"]
            )
        }

        guard let values = match(dmsPattern, in: normalized) else { throw CoordinateInputError.format }
        let first = try dms(direction: values[0], degrees: values[1], minutes: values[2], seconds: values[3])
        let second = try dms(direction: values[4], degrees: values[5], minutes: values[6], seconds: values[7])
        let components = [(values[0], first), (values[4], second)]
        let latitudes = components.filter { $0.0 == "N" || $0.0 == "S" }.map(\.1)
        let longitudes = components.filter { $0.0 == "E" || $0.0 == "W" }.map(\.1)
        guard latitudes.count == 1, longitudes.count == 1 else { throw CoordinateInputError.cardinalDirections }
        try validate(lat: latitudes[0], lng: longitudes[0])
        return ParsedCoordinates(lat: latitudes[0], lng: longitudes[0], inputFormat: .dms, warnings: [])
    }

    static func normalize(_ input: String) -> String {
        let replacements: [Character: Character] = [
            "　": " ", "，": ",", "、": ",", "º": "°", "˚": "°",
            "′": "'", "’": "'", "‘": "'", "＇": "'", "`": "'",
            "″": "\"", "“": "\"", "”": "\"", "＂": "\"",
        ]
        func replaceSymbols(_ value: String) -> String {
            String(value.map { replacements[$0] ?? $0 })
        }
        let compatibility = replaceSymbols(input).precomposedStringWithCompatibilityMapping
        return replaceSymbols(compatibility)
            .uppercased(with: locale)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func match(_ expression: NSRegularExpression, in value: String) -> [String]? {
        let range = NSRange(value.startIndex..., in: value)
        guard let result = expression.firstMatch(in: value, range: range), result.range == range else { return nil }
        return (1 ..< result.numberOfRanges).compactMap { group in
            guard let groupRange = Range(result.range(at: group), in: value) else { return nil }
            return String(value[groupRange])
        }
    }

    private static func decimal(_ value: String) throws -> Decimal {
        guard let result = Decimal(string: value, locale: locale) else { throw CoordinateInputError.format }
        return result
    }

    private static func dms(direction: String, degrees: String, minutes: String, seconds: String) throws -> Decimal {
        let degreeValue = try decimal(degrees)
        let minuteValue = try decimal(minutes)
        let secondValue = try decimal(seconds)
        guard minuteValue < 60 else { throw CoordinateInputError.minuteRange }
        guard secondValue < 60 else { throw CoordinateInputError.secondRange }
        let value = degreeValue + minuteValue / 60 + secondValue / 3600
        return direction == "S" || direction == "W" ? -value : value
    }

    private static func validate(lat: Decimal, lng: Decimal) throws {
        if !(Decimal(-90) ... Decimal(90)).contains(lat) {
            if (Decimal(-180) ... Decimal(180)).contains(lat), (Decimal(-90) ... Decimal(90)).contains(lng) {
                throw CoordinateInputError.likelyReversed
            }
            throw CoordinateInputError.latitudeRange
        }
        guard (Decimal(-180) ... Decimal(180)).contains(lng) else { throw CoordinateInputError.longitudeRange }
    }
}
