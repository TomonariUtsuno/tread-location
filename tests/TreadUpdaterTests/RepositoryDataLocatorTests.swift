import Foundation
import XCTest
@testable import TreadUpdater

@MainActor
final class RepositoryDataLocatorTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testBundledDataRootLoadsAllExistingWheels() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TreadUpdaterTests-\(UUID().uuidString)", isDirectory: true)
        let resources = temporaryRoot.appendingPathComponent("Resources", isDirectory: true)
        let bundledRoot = resources.appendingPathComponent("RepositoryData", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        try FileManager.default.createDirectory(
            at: bundledRoot.appendingPathComponent("wheels", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(
            at: repositoryRoot.appendingPathComponent("wheels.json"),
            to: bundledRoot.appendingPathComponent("wheels.json")
        )

        let located = RepositoryDataLocator.locate(
            startingDirectory: temporaryRoot,
            bundleResourceURL: resources
        )
        XCTAssertEqual(located?.standardizedFileURL, bundledRoot.standardizedFileURL)

        let store = DraftStore(repositoryRoot: located)
        XCTAssertNil(store.repositoryError)
        XCTAssertEqual(store.existingWheels.count, 36)
        XCTAssertEqual(store.existingWheels.map(\.number), [
            1, 2, 3, 4, 6, 9, 13, 14, 18, 22, 23, 25, 26, 27, 28, 29, 30, 31,
            32, 33, 35, 36, 37, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 55,
        ])
    }
}
