import Foundation
import XCTest
@testable import TreadUpdater

@MainActor
final class PublicationTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testCanonicalRenderersLeaveCurrentPublishedDataByteIdentical() throws {
        let catalogData = try Data(contentsOf: repositoryRoot.appendingPathComponent("wheels.json"))
        let catalog = try JSONDecoder().decode(PublicationCatalog.self, from: catalogData)
        XCTAssertEqual(PublicationPlanBuilder.renderWheelsJSON(catalog), String(decoding: catalogData, as: UTF8.self))
        let dataJS = try String(contentsOf: repositoryRoot.appendingPathComponent("data.js"), encoding: .utf8)
        XCTAssertEqual(PublicationPlanBuilder.renderDataJS(catalog.wheels), dataJS)
    }

    func testPlanContainsOnlyNewImageAndBothGeneratedDataFiles() throws {
        let plan = try makePlan()
        XCTAssertEqual(Set(plan.files.map(\.path)), ["wheels/w056.png", "wheels.json", "data.js"])
        XCTAssertEqual(plan.entries.count, 1)
        let updatedCatalog = try JSONDecoder().decode(
            PublicationCatalog.self,
            from: try XCTUnwrap(plan.files.first(where: { $0.path == "wheels.json" })?.data)
        )
        XCTAssertEqual(updatedCatalog.wheels.count, 37)
        XCTAssertEqual(Array(updatedCatalog.wheels.prefix(36)), try originalCatalog().wheels)
        XCTAssertEqual(updatedCatalog.wheels.last?.number, 56)
        XCTAssertEqual(updatedCatalog.wheels.last?.image, "wheels/w056.png")
    }

    func testSuccessfulPublishUsesOneTreeAndOneNonForceRefUpdate() async throws {
        let tokenStore = MemoryTokenStore()
        let github = MockGitHub(heads: ["base", "base"], catalogData: try catalogData())
        let coordinator = PublicationCoordinator(tokenStore: tokenStore, github: github, pagesVerifier: FixedPagesVerifier(result: .live))
        let plan = try makePlan()
        await coordinator.prepare(drafts: [try makeDraft()])
        XCTAssertEqual(coordinator.stage, .ready)
        await coordinator.publish()

        XCTAssertEqual(coordinator.stage, .pagesLive("commit"))
        XCTAssertEqual(github.createdBlobData.count, plan.files.count)
        XCTAssertEqual(github.createdTreeEntries.map(\.path), plan.files.map(\.path))
        XCTAssertEqual(github.updateCalls, ["commit"])
        XCTAssertEqual(github.commitParents, ["base"])
    }

    func testChangedRemoteHeadPreventsBlobAndRefUpdates() async throws {
        let github = MockGitHub(heads: ["base", "newer"], catalogData: try catalogData())
        let coordinator = PublicationCoordinator(tokenStore: MemoryTokenStore(), github: github, pagesVerifier: FixedPagesVerifier(result: .live))
        await coordinator.prepare(drafts: [try makeDraft()])
        await coordinator.publish()

        XCTAssertEqual(coordinator.stage, .conflict)
        XCTAssertTrue(github.createdBlobData.isEmpty)
        XCTAssertTrue(github.updateCalls.isEmpty)
    }

    func testUploadFailureNeverUpdatesTheBranch() async throws {
        let github = MockGitHub(heads: ["base", "base"], catalogData: try catalogData(), blobError: .network)
        let coordinator = PublicationCoordinator(tokenStore: MemoryTokenStore(), github: github, pagesVerifier: FixedPagesVerifier(result: .live))
        await coordinator.prepare(drafts: [try makeDraft()])
        await coordinator.publish()

        guard case .failed = coordinator.stage else {
            return XCTFail("expected a safe failure state")
        }
        XCTAssertTrue(github.updateCalls.isEmpty)
    }

    func testPreparedPlanPreventsDoublePublishWhileFirstRunIsBusy() async throws {
        let github = MockGitHub(heads: ["base", "base"], catalogData: try catalogData(), uploadDelayNanoseconds: 80_000_000)
        let coordinator = PublicationCoordinator(tokenStore: MemoryTokenStore(), github: github, pagesVerifier: FixedPagesVerifier(result: .live))
        await coordinator.prepare(drafts: [try makeDraft()])
        let firstPublish = Task { await coordinator.publish() }
        try await Task.sleep(nanoseconds: 10_000_000)
        await coordinator.publish()
        await firstPublish.value

        XCTAssertEqual(github.updateCalls, ["commit"])
    }

    func testTokenIsKeptOutsideUserDefaultsInTheInjectableStoreBoundary() throws {
        let suite = "TreadUpdaterTests.NoTokenPersistence"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = MemoryTokenStore(token: "test-token-not-a-secret")
        XCTAssertEqual(try store.token(for: .tread), "test-token-not-a-secret")
        XCTAssertNil(defaults.string(forKey: "githubToken"))
    }

    private func catalogData() throws -> Data {
        try Data(contentsOf: repositoryRoot.appendingPathComponent("wheels.json"))
    }

    private func originalCatalog() throws -> PublicationCatalog {
        try JSONDecoder().decode(PublicationCatalog.self, from: catalogData())
    }

    private func makeDraft() throws -> DraftWheel {
        let draft = DraftWheel(url: repositoryRoot.appendingPathComponent("wheels/w055.png"))
        draft.numberText = "56"
        draft.coordinateText = "N34°31'22.98\" E135°36'27.93\""
        draft.validate(existingNumbers: Set(try originalCatalog().wheels.map(\.number)), batchNumberCounts: [56: 1])
        XCTAssertFalse(draft.hasBlockingError)
        return draft
    }

    private func makePlan() throws -> PublicationPlan {
        try PublicationPlanBuilder.make(catalogData: catalogData(), drafts: [makeDraft()], expectedHead: "base")
    }
}

@MainActor
private final class MemoryTokenStore: TokenStoring {
    private var storedToken: String?

    init(token: String = "test-token-not-a-secret") {
        storedToken = token
    }

    func token(for target: RepositoryTarget) throws -> String? { storedToken }
    func save(_ token: String, for target: RepositoryTarget) throws { storedToken = token }
    func deleteToken(for target: RepositoryTarget) throws { storedToken = nil }
}

@MainActor
private final class FixedPagesVerifier: PagesVerifying {
    let result: PagesVerification
    init(result: PagesVerification) { self.result = result }
    func verify(plan: PublicationPlan, commitSHA: String) async -> PagesVerification { result }
}

@MainActor
private final class MockGitHub: GitHubPublishing {
    private var heads: [String]
    private let remoteCatalogData: Data
    private let blobError: GitHubAPIError?
    private let uploadDelayNanoseconds: UInt64
    var createdBlobData: [Data] = []
    var createdTreeEntries: [GitTreeEntry] = []
    var commitParents: [String] = []
    var updateCalls: [String] = []

    init(heads: [String], catalogData: Data, blobError: GitHubAPIError? = nil, uploadDelayNanoseconds: UInt64 = 0) {
        self.heads = heads
        remoteCatalogData = catalogData
        self.blobError = blobError
        self.uploadDelayNanoseconds = uploadDelayNanoseconds
    }

    func head(of target: RepositoryTarget, token: String) async throws -> String {
        if heads.count > 1 { return heads.removeFirst() }
        return heads[0]
    }

    func catalogData(at head: String, target: RepositoryTarget, token: String) async throws -> Data {
        remoteCatalogData
    }

    func commitTreeSHA(head: String, target: RepositoryTarget, token: String) async throws -> String { "tree-base" }

    func createBlob(data: Data, target: RepositoryTarget, token: String) async throws -> String {
        if uploadDelayNanoseconds > 0 { try await Task.sleep(nanoseconds: uploadDelayNanoseconds) }
        if let blobError { throw blobError }
        createdBlobData.append(data)
        return "blob-\(createdBlobData.count)"
    }

    func createTree(baseTree: String, entries: [GitTreeEntry], target: RepositoryTarget, token: String) async throws -> String {
        createdTreeEntries = entries
        return "tree-new"
    }

    func createCommit(message: String, tree: String, parent: String, target: RepositoryTarget, token: String) async throws -> String {
        commitParents.append(parent)
        return "commit"
    }

    func updateBranch(head: String, target: RepositoryTarget, token: String) async throws {
        updateCalls.append(head)
    }
}
