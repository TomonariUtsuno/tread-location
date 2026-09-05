import Foundation

struct GitHubHTTPResponse {
    let data: Data
    let statusCode: Int
}

@MainActor
protocol GitHubHTTPTransport {
    func send(_ request: URLRequest) async throws -> GitHubHTTPResponse
}

@MainActor
final class URLSessionGitHubTransport: GitHubHTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> GitHubHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GitHubAPIError.network }
            return GitHubHTTPResponse(data: data, statusCode: http.statusCode)
        } catch is CancellationError {
            throw GitHubAPIError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw GitHubAPIError.timeout
        } catch {
            throw GitHubAPIError.network
        }
    }
}

@MainActor
protocol GitHubPublishing {
    func head(of target: RepositoryTarget, token: String) async throws -> String
    func catalogData(at head: String, target: RepositoryTarget, token: String) async throws -> Data
    func commitTreeSHA(head: String, target: RepositoryTarget, token: String) async throws -> String
    func createBlob(data: Data, target: RepositoryTarget, token: String) async throws -> String
    func createTree(baseTree: String, entries: [GitTreeEntry], target: RepositoryTarget, token: String) async throws -> String
    func createCommit(message: String, tree: String, parent: String, target: RepositoryTarget, token: String) async throws -> String
    func updateBranch(head: String, target: RepositoryTarget, token: String) async throws
}

struct GitTreeEntry: Equatable {
    let path: String
    let blobSHA: String
}

enum GitHubAPIError: LocalizedError, Equatable {
    case unauthorized
    case forbidden
    case conflict
    case validation
    case timeout
    case network
    case cancelled
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized: "GitHub認証に失敗しました。トークンを確認してください。"
        case .forbidden: "GitHub権限が不足しています。対象リポジトリのContents読み書き権限を確認してください。"
        case .conflict: "リモートブランチが更新されました。最新データを読み直して再確認してください。"
        case .validation: "GitHubが更新内容を受け付けませんでした。入力とリポジトリ設定を確認してください。"
        case .timeout: "GitHubへの接続がタイムアウトしました。公開済みか確認してから再試行してください。"
        case .network: "GitHubへ接続できませんでした。ネットワーク接続を確認してください。"
        case .cancelled: "公開処理を中止しました。"
        case .malformedResponse: "GitHubから予期しない応答が返りました。"
        }
    }
}

@MainActor
final class GitHubAPI: GitHubPublishing {
    private let transport: GitHubHTTPTransport
    private let baseURL = URL(string: "https://api.github.com")!

    init(transport: GitHubHTTPTransport = URLSessionGitHubTransport()) {
        self.transport = transport
    }

    func head(of target: RepositoryTarget, token: String) async throws -> String {
        let response = try await request(path: "git/ref/heads/\(target.branch)", target: target, token: token)
        return try decode(GitReference.self, from: response.data).object.sha
    }

    func catalogData(at head: String, target: RepositoryTarget, token: String) async throws -> Data {
        let response = try await request(
            path: "contents/wheels.json",
            queryItems: [URLQueryItem(name: "ref", value: head)],
            target: target,
            token: token
        )
        let file = try decode(RepositoryFile.self, from: response.data)
        guard file.encoding == "base64", let data = Data(base64Encoded: file.content.replacingOccurrences(of: "\n", with: "")) else {
            throw GitHubAPIError.malformedResponse
        }
        return data
    }

    func commitTreeSHA(head: String, target: RepositoryTarget, token: String) async throws -> String {
        let response = try await request(path: "git/commits/\(head)", target: target, token: token)
        return try decode(GitCommit.self, from: response.data).tree.sha
    }

    func createBlob(data: Data, target: RepositoryTarget, token: String) async throws -> String {
        let body = BlobRequest(content: data.base64EncodedString(), encoding: "base64")
        let response = try await request(path: "git/blobs", method: "POST", body: try JSONEncoder().encode(body), target: target, token: token)
        return try decode(GitObject.self, from: response.data).sha
    }

    func createTree(baseTree: String, entries: [GitTreeEntry], target: RepositoryTarget, token: String) async throws -> String {
        let body = TreeRequest(
            baseTree: baseTree,
            tree: entries.map { TreeItem(path: $0.path, mode: "100644", type: "blob", sha: $0.blobSHA) }
        )
        let response = try await request(path: "git/trees", method: "POST", body: try JSONEncoder().encode(body), target: target, token: token)
        return try decode(GitObject.self, from: response.data).sha
    }

    func createCommit(message: String, tree: String, parent: String, target: RepositoryTarget, token: String) async throws -> String {
        let body = CommitRequest(message: message, tree: tree, parents: [parent])
        let response = try await request(path: "git/commits", method: "POST", body: try JSONEncoder().encode(body), target: target, token: token)
        return try decode(GitObject.self, from: response.data).sha
    }

    func updateBranch(head: String, target: RepositoryTarget, token: String) async throws {
        let body = UpdateReferenceRequest(sha: head, force: false)
        _ = try await request(path: "git/refs/heads/\(target.branch)", method: "PATCH", body: try JSONEncoder().encode(body), target: target, token: token)
    }

    private func request(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        target: RepositoryTarget,
        token: String
    ) async throws -> GitHubHTTPResponse {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/repos/\(target.owner)/\(target.name)/\(path)"
        components.queryItems = queryItems
        guard let url = components.url else { throw GitHubAPIError.malformedResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let response = try await transport.send(request)
        switch response.statusCode {
        case 200, 201: return response
        case 401: throw GitHubAPIError.unauthorized
        case 403: throw GitHubAPIError.forbidden
        case 409: throw GitHubAPIError.conflict
        case 422: throw GitHubAPIError.validation
        default: throw GitHubAPIError.network
        }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw GitHubAPIError.malformedResponse }
    }
}

private struct GitObject: Decodable { let sha: String }
private struct GitReference: Decodable { let object: GitObject }
private struct GitCommit: Decodable { let tree: GitObject }
private struct RepositoryFile: Decodable { let content: String; let encoding: String }
private struct BlobRequest: Encodable { let content: String; let encoding: String }
private struct TreeRequest: Encodable { let baseTree: String; let tree: [TreeItem] }
private struct TreeItem: Encodable { let path: String; let mode: String; let type: String; let sha: String }
private struct CommitRequest: Encodable { let message: String; let tree: String; let parents: [String] }
private struct UpdateReferenceRequest: Encodable { let sha: String; let force: Bool }
