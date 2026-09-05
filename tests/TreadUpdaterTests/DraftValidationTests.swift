import Foundation
import XCTest
@testable import TreadUpdater

@MainActor
final class DraftValidationTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testDraftUsesTheActualImageWithoutChangingIt() {
        let image = repositoryRoot.appendingPathComponent("wheels/w055.png")
        let draft = DraftWheel(url: image)
        draft.numberText = "56"
        draft.coordinateText = "N34°31'22.98\" E135°36'27.93\""
        draft.validate(existingNumbers: [55], batchNumberCounts: [56: 1])

        XCTAssertEqual(draft.sourceFilename, "w055.png")
        XCTAssertEqual(draft.outputFilename, "w056.png")
        XCTAssertEqual(draft.inspection?.width, 533)
        XCTAssertEqual(draft.inspection?.height, 800)
        XCTAssertFalse(draft.hasBlockingError)
        XCTAssertEqual(draft.parsedCoordinates?.latitudeText, "34.52305000")
    }

    func testExistingNumberAndUnreadableImageAreBlockingErrors() {
        let existingImage = repositoryRoot.appendingPathComponent("wheels/w055.png")
        let duplicate = DraftWheel(url: existingImage)
        duplicate.numberText = "55"
        duplicate.coordinateText = "34.52305000, 135.60775833"
        duplicate.validate(existingNumbers: [55], batchNumberCounts: [55: 1])
        XCTAssertTrue(duplicate.hasBlockingError)
        XCTAssertTrue(duplicate.issues.contains { $0.message.contains("既存データ") })

        let nonImage = repositoryRoot.appendingPathComponent("wheels.json")
        let unreadable = DraftWheel(url: nonImage)
        unreadable.numberText = "56"
        unreadable.coordinateText = "34.52305000, 135.60775833"
        unreadable.validate(existingNumbers: [], batchNumberCounts: [56: 1])
        XCTAssertTrue(unreadable.hasBlockingError)
    }

    func testBatchDuplicateAndWrongDimensionsAreBlockingErrors() {
        let image = repositoryRoot.appendingPathComponent("wheels/w055.png")
        let duplicate = DraftWheel(url: image)
        duplicate.numberText = "56"
        duplicate.coordinateText = "34.52305000, 135.60775833"
        duplicate.validate(existingNumbers: [], batchNumberCounts: [56: 2])
        XCTAssertTrue(duplicate.hasBlockingError)
        XCTAssertTrue(duplicate.issues.contains { $0.message.contains("追加項目内で重複") })

        let wrongSize = DraftWheel(url: repositoryRoot.appendingPathComponent("favicon-32.png"))
        wrongSize.numberText = "56"
        wrongSize.coordinateText = "34.52305000, 135.60775833"
        wrongSize.validate(existingNumbers: [], batchNumberCounts: [56: 1])
        XCTAssertTrue(wrongSize.hasBlockingError)
        XCTAssertTrue(wrongSize.issues.contains { $0.message.contains("533 × 800") })
    }
}
