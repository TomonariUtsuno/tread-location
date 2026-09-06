import Foundation
import XCTest
@testable import TreadUpdater

final class KeychainCredentialIdentifierTests: XCTestCase {
    func testInstallableAppAndDevelopmentServicesAreStableAndSeparate() {
        let appBundle = URL(fileURLWithPath: "/Applications/Tread Updater.app", isDirectory: true)
        let developmentBundle = URL(fileURLWithPath: "/tmp/TreadUpdater", isDirectory: true)

        XCTAssertEqual(
            KeychainCredentialIdentifier.service(for: appBundle),
            "jp.tomonariutsuno.tread-updater.github-token.app"
        )
        XCTAssertEqual(
            KeychainCredentialIdentifier.service(for: developmentBundle),
            "jp.tomonariutsuno.tread-updater.github-token.development"
        )
        XCTAssertNotEqual(
            KeychainCredentialIdentifier.service(for: appBundle),
            KeychainCredentialIdentifier.service(for: developmentBundle)
        )
    }
}
