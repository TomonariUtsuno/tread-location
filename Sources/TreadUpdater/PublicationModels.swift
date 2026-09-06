import Foundation

struct RepositoryTarget: Equatable {
    let owner: String
    let name: String
    let branch: String
    let publicSiteURL: URL

    static let tread = RepositoryTarget(
        owner: "TomonariUtsuno",
        name: "tread-location",
        branch: "main",
        publicSiteURL: URL(string: "https://tomonariutsuno.github.io/tread-location/")!
    )

    var identifier: String { "\(owner)/\(name)" }
}

struct CatalogImageSpecification: Codable, Equatable {
    let format: String
    let width: Int
    let height: Int
    let colorModel: String
    let bitDepth: Int
    let alpha: Bool
}

struct PublicationCatalog: Codable, Equatable {
    let schemaVersion: Int
    let imageSpecification: CatalogImageSpecification
    var wheels: [ExistingWheel]
}

struct PublicationFile: Equatable {
    let path: String
    let data: Data
    let isBinary: Bool
}

struct PublicationEntry: Identifiable, Equatable {
    let number: Int
    let sourceFilename: String
    let outputFilename: String
    let lat: Decimal
    let lng: Decimal
    let imageData: Data

    var id: Int { number }
    var imagePath: String { "wheels/\(outputFilename)" }
}

struct PublicationPlan: Equatable {
    let target: RepositoryTarget
    let expectedHead: String
    let entries: [PublicationEntry]
    let files: [PublicationFile]
    let commitMessage: String
    let warnings: [String]
}

enum PublicationButtonState: Equatable {
    case ready
    case authenticationRequired
    case noDrafts
    case validationErrors
    case publishing

    static func resolve(hasToken: Bool, draftCount: Int, validDraftCount: Int, isPublishing: Bool) -> PublicationButtonState {
        if isPublishing { return .publishing }
        if !hasToken { return .authenticationRequired }
        if draftCount == 0 { return .noDrafts }
        if draftCount != validDraftCount { return .validationErrors }
        return .ready
    }

    var isEnabled: Bool { self == .ready }

    var explanation: String? {
        switch self {
        case .ready: nil
        case .authenticationRequired: "GitHub認証を設定すると公開内容を確認できます。"
        case .noDrafts: "公開する画像を追加すると公開内容を確認できます。"
        case .validationErrors: "公開不能エラーを解消すると公開内容を確認できます。"
        case .publishing: "公開処理中です。完了するまで入力・公開操作はできません。"
        }
    }
}

enum PublicationPlanError: LocalizedError {
    case missingSourceData(String)
    case invalidDraft(String)
    case duplicateExistingNumber(Int)
    case duplicateNumber(Int)
    case invalidImageSpecification

    var errorDescription: String? {
        switch self {
        case let .missingSourceData(filename): "画像データを読み込めませんでした: \(filename)"
        case let .invalidDraft(filename): "公開できないドラフトがあります: \(filename)"
        case let .duplicateExistingNumber(number): "No.\(number) は既存データにあります。"
        case let .duplicateNumber(number): "No.\(number) が追加項目内で重複しています。"
        case .invalidImageSpecification: "既存の画像仕様が公開仕様と一致しません。"
        }
    }
}

@MainActor
enum PublicationPlanBuilder {
    static func make(
        catalogData: Data,
        drafts: [DraftWheel],
        expectedHead: String,
        target: RepositoryTarget = .tread
    ) throws -> PublicationPlan {
        var catalog = try JSONDecoder().decode(PublicationCatalog.self, from: catalogData)
        guard catalog.imageSpecification == CatalogImageSpecification(
            format: "png", width: 533, height: 800, colorModel: "RGB", bitDepth: 8, alpha: false
        ) else {
            throw PublicationPlanError.invalidImageSpecification
        }

        let existingNumbers = Set(catalog.wheels.map(\.number))
        var newNumbers = Set<Int>()
        let entries = try drafts.map { draft -> PublicationEntry in
            guard !draft.hasBlockingError,
                  let number = Int(draft.numberText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let coordinates = draft.parsedCoordinates,
                  let outputFilename = draft.outputFilename
            else { throw PublicationPlanError.invalidDraft(draft.sourceFilename) }
            guard let imageData = draft.sourceData else { throw PublicationPlanError.missingSourceData(draft.sourceFilename) }
            if existingNumbers.contains(number) { throw PublicationPlanError.duplicateExistingNumber(number) }
            if !newNumbers.insert(number).inserted { throw PublicationPlanError.duplicateNumber(number) }
            return PublicationEntry(
                number: number,
                sourceFilename: draft.sourceFilename,
                outputFilename: outputFilename,
                lat: coordinates.lat,
                lng: coordinates.lng,
                imageData: imageData
            )
        }

        catalog.wheels += entries.map {
            ExistingWheel(
                number: $0.number,
                lat: NSDecimalNumber(decimal: $0.lat).doubleValue,
                lng: NSDecimalNumber(decimal: $0.lng).doubleValue,
                image: $0.imagePath
            )
        }
        let wheelsJSON = renderWheelsJSON(catalog)
        let dataJS = renderDataJS(catalog.wheels)
        let images = entries.map { PublicationFile(path: $0.imagePath, data: $0.imageData, isBinary: true) }
        let files = images + [
            PublicationFile(path: "wheels.json", data: Data(wheelsJSON.utf8), isBinary: false),
            PublicationFile(path: "data.js", data: Data(dataJS.utf8), isBinary: false),
        ]
        let warnings = drafts.flatMap { draft in
            draft.issues
                .filter { $0.severity == .warning }
                .map(\.message)
        }
        return PublicationPlan(
            target: target,
            expectedHead: expectedHead,
            entries: entries,
            files: files,
            commitMessage: "Add \(entries.count) tread wheel\(entries.count == 1 ? "" : "s")",
            warnings: warnings
        )
    }

    static func renderWheelsJSON(_ catalog: PublicationCatalog) -> String {
        let specification = catalog.imageSpecification
        var lines = [
            "{",
            "  \"schemaVersion\": \(catalog.schemaVersion),",
            "  \"imageSpecification\": {",
            "    \"format\": \"\(specification.format)\",",
            "    \"width\": \(specification.width),",
            "    \"height\": \(specification.height),",
            "    \"colorModel\": \"\(specification.colorModel)\",",
            "    \"bitDepth\": \(specification.bitDepth),",
            "    \"alpha\": \(specification.alpha ? "true" : "false")",
            "  },",
            "  \"wheels\": [",
        ]
        for (index, wheel) in catalog.wheels.enumerated() {
            let suffix = index == catalog.wheels.indices.last ? "" : ","
            lines.append("    { \"number\": \(wheel.number), \"lat\": \(number(wheel.lat)), \"lng\": \(number(wheel.lng)), \"image\": \"\(wheel.image)\" }\(suffix)")
        }
        lines += ["  ]", "}", ""]
        return lines.joined(separator: "\n")
    }

    static func renderDataJS(_ wheels: [ExistingWheel]) -> String {
        var lines = ["window.TREAD_WHEELS = Object.freeze(["]
        for (index, wheel) in wheels.enumerated() {
            let suffix = index == wheels.indices.last ? "" : ","
            lines.append("  { number: \(wheel.number), lat: \(number(wheel.lat)), lng: \(number(wheel.lng)), image: \"\(wheel.image)\" }\(suffix)")
        }
        lines += ["]);", ""]
        return lines.joined(separator: "\n")
    }

    private static func number(_ value: Double) -> String {
        String(value)
    }
}
