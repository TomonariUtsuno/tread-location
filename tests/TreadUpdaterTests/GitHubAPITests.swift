import Foundation
import XCTest
@testable import TreadUpdater

@MainActor
final class GitHubAPITests: XCTestCase {
    func testHeadRequestUsesBearerAuthenticationWithoutExposingItInModels() async throws {
        let transport = MockHTTPTransport(response: .init(data: Data("{\"object\":{\"sha\":\"head-sha\"}}".utf8), statusCode: 200))
        let api = GitHubAPI(transport: transport)
        let token = "ephemeral-test-token"
        let sha = try await api.head(of: .tread, token: token)

        XCTAssertEqual(sha, "head-sha")
        XCTAssertEqual(transport.lastRequest?.url?.path, "/repos/TomonariUtsuno/tread-location/git/ref/heads/main")
        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertNil(UserDefaults.standard.string(forKey: "githubToken"))
    }

    func testGitHubStatusCodesMapToSafeSpecificErrors() async {
        let expected: [(Int, GitHubAPIError)] = [
            (401, .unauthorized), (403, .forbidden), (409, .conflict), (422, .validation),
        ]
        for (status, error) in expected {
            let api = GitHubAPI(transport: MockHTTPTransport(response: .init(data: Data(), statusCode: status)))
            do {
                _ = try await api.head(of: .tread, token: "ephemeral-test-token")
                XCTFail("expected status \(status) to fail")
            } catch let actual as GitHubAPIError {
                XCTAssertEqual(actual, error)
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
    }
}

@MainActor
private final class MockHTTPTransport: GitHubHTTPTransport {
    let response: GitHubHTTPResponse
    var lastRequest: URLRequest?

    init(response: GitHubHTTPResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> GitHubHTTPResponse {
        lastRequest = request
        return response
    }
}
