import XCTest
@testable import TreadUpdater

final class PublicationButtonStateTests: XCTestCase {
    func testPublishConfirmationRequiresAuthenticationEvenForValidDrafts() {
        let state = PublicationButtonState.resolve(hasToken: false, draftCount: 1, validDraftCount: 1, isPublishing: false)
        XCTAssertEqual(state, .authenticationRequired)
        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.explanation, "GitHub認証を設定すると公開内容を確認できます。")
    }

    func testPublishConfirmationStatesKeepAllSafetyGates() {
        XCTAssertEqual(PublicationButtonState.resolve(hasToken: true, draftCount: 0, validDraftCount: 0, isPublishing: false), .noDrafts)
        XCTAssertEqual(PublicationButtonState.resolve(hasToken: true, draftCount: 2, validDraftCount: 1, isPublishing: false), .validationErrors)
        XCTAssertEqual(PublicationButtonState.resolve(hasToken: true, draftCount: 1, validDraftCount: 1, isPublishing: true), .publishing)
        XCTAssertEqual(PublicationButtonState.resolve(hasToken: true, draftCount: 2, validDraftCount: 2, isPublishing: false), .ready)
    }
}
