import AppKit
import Combine
import Foundation

@MainActor
final class DraftWheel: ObservableObject, Identifiable {
    let id = UUID()
    let sourceURL: URL
    let sourceFilename: String
    let inspection: ImageInspection?
    let inspectionError: String?
    let suggestedNumber: Int?

    @Published var numberText: String
    @Published var coordinateText = ""
    @Published private(set) var parsedCoordinates: ParsedCoordinates?
    @Published private(set) var issues: [DraftIssue] = []

    init(url: URL) {
        sourceURL = url
        sourceFilename = url.lastPathComponent
        suggestedNumber = Self.inferNumber(from: url.lastPathComponent)
        numberText = suggestedNumber.map(String.init) ?? ""
        do {
            inspection = try ImageInspector.inspect(url: url)
            inspectionError = nil
        } catch {
            inspection = nil
            inspectionError = error.localizedDescription
        }
    }

    var outputFilename: String? {
        guard let number = Self.validNumber(numberText) else { return nil }
        return String(format: "w%03d.png", number)
    }

    var hasBlockingError: Bool { issues.contains { $0.severity == .error } }

    func validate(existingNumbers: Set<Int>, batchNumberCounts: [Int: Int]) {
        var nextIssues: [DraftIssue] = []
        if let inspectionError {
            nextIssues.append(.init(severity: .error, message: inspectionError))
        } else if let inspection {
            if !inspection.isPNG {
                nextIssues.append(.init(severity: .error, message: "PNG形式の画像を選択してください。"))
            }
            if inspection.width != 533 || inspection.height != 800 {
                nextIssues.append(.init(severity: .error, message: "画像寸法は533 × 800 pxである必要があります。変換は行いません。"))
            }
            if !inspection.isRGB || inspection.hasAlpha || !inspection.isEightBit {
                nextIssues.append(.init(severity: .error, message: "8-bit RGB・アルファなしのPNGを選択してください。"))
            }
        }

        guard let number = Self.validNumber(numberText) else {
            nextIssues.append(.init(severity: .error, message: "車輪番号は1〜999の整数で入力してください。"))
            validateCoordinate(into: &nextIssues)
            issues = nextIssues
            return
        }
        if existingNumbers.contains(number) {
            nextIssues.append(.init(severity: .error, message: "No.\(number) は既存データにあります。"))
        }
        if batchNumberCounts[number, default: 0] > 1 {
            nextIssues.append(.init(severity: .error, message: "No.\(number) が今回の追加項目内で重複しています。"))
        }
        if sourceFilename.caseInsensitiveCompare("w\(String(format: "%03d", number)).png") != .orderedSame {
            nextIssues.append(.init(severity: .warning, message: "元ファイル名と公開予定名（w\(String(format: "%03d", number)).png）が異なります。"))
        }
        validateCoordinate(into: &nextIssues)
        issues = nextIssues
    }

    private func validateCoordinate(into issues: inout [DraftIssue]) {
        do {
            parsedCoordinates = try CoordinateParser.parse(coordinateText)
            for warning in parsedCoordinates?.warnings ?? [] {
                issues.append(.init(severity: .warning, message: warning))
            }
        } catch let error as CoordinateInputError {
            parsedCoordinates = nil
            issues.append(.init(severity: .error, message: error.localizedDescription))
        } catch {
            parsedCoordinates = nil
            issues.append(.init(severity: .error, message: "座標を解釈できませんでした。"))
        }
    }

    private static func validNumber(_ input: String) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), (1 ... 999).contains(value) else { return nil }
        return value
    }

    private static func inferNumber(from filename: String) -> Int? {
        let expression = try! NSRegularExpression(pattern: "^w([0-9]{3})\\.png$", options: [.caseInsensitive])
        let range = NSRange(filename.startIndex..., in: filename)
        guard let match = expression.firstMatch(in: filename, range: range),
              let capture = Range(match.range(at: 1), in: filename),
              let number = Int(filename[capture]), (1 ... 999).contains(number)
        else { return nil }
        return number
    }
}

@MainActor
final class DraftStore: ObservableObject {
    @Published private(set) var drafts: [DraftWheel] = []
    @Published private(set) var existingWheels: [ExistingWheel] = []
    @Published private(set) var repositoryError: String?
    @Published var selectedDraftID: UUID?

    private let repositoryRoot: URL?

    init() {
        repositoryRoot = Self.findRepositoryRoot()
        loadExistingWheels()
    }

    var validDrafts: [DraftWheel] {
        drafts.filter { !$0.hasBlockingError && $0.parsedCoordinates != nil }
    }

    var previewPoints: [PreviewPoint] {
        let existing = existingWheels.map {
            PreviewPoint(id: "existing-\($0.number)", number: $0.number, coordinate: $0.coordinate, kind: .existing)
        }
        let additions = validDrafts.compactMap { draft -> PreviewPoint? in
            guard let number = Int(draft.numberText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let coordinate = draft.parsedCoordinates
            else { return nil }
            return PreviewPoint(
                id: "draft-\(draft.id.uuidString)",
                number: number,
                coordinate: .init(latitude: NSDecimalNumber(decimal: coordinate.lat).doubleValue, longitude: NSDecimalNumber(decimal: coordinate.lng).doubleValue),
                kind: .draft(draft.id)
            )
        }
        return existing + additions
    }

    func addFiles(_ urls: [URL]) {
        for url in urls where !drafts.contains(where: { $0.sourceURL.standardizedFileURL == url.standardizedFileURL }) {
            let securityScope = url.startAccessingSecurityScopedResource()
            defer { if securityScope { url.stopAccessingSecurityScopedResource() } }
            drafts.append(DraftWheel(url: url))
        }
        revalidate()
    }

    func remove(_ draft: DraftWheel) {
        drafts.removeAll { $0.id == draft.id }
        if selectedDraftID == draft.id { selectedDraftID = nil }
        revalidate()
    }

    func revalidate() {
        objectWillChange.send()
        let existingNumbers = Set(existingWheels.map(\.number))
        let counts = Dictionary(grouping: drafts.compactMap { Int($0.numberText.trimmingCharacters(in: .whitespacesAndNewlines)) }, by: { $0 })
            .mapValues(\.count)
        for draft in drafts {
            draft.validate(existingNumbers: existingNumbers, batchNumberCounts: counts)
        }
    }

    func select(_ draftID: UUID) {
        selectedDraftID = draftID
    }

    func selectedDraft() -> DraftWheel? {
        guard let selectedDraftID else { return nil }
        return drafts.first { $0.id == selectedDraftID }
    }

    private func loadExistingWheels() {
        guard let repositoryRoot else {
            repositoryError = "wheels.json を含むリポジトリのルートを見つけられませんでした。リポジトリ直下でアプリを起動してください。"
            return
        }
        do {
            let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("wheels.json"))
            existingWheels = try JSONDecoder().decode(WheelCatalog.self, from: data).wheels
        } catch {
            repositoryError = "既存データを読み込めませんでした: \(error.localizedDescription)"
        }
    }

    private static func findRepositoryRoot() -> URL? {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("wheels.json").path),
               FileManager.default.fileExists(atPath: directory.appendingPathComponent("wheels").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
