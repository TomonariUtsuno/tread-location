import Foundation

@MainActor
protocol PagesVerifying {
    func verify(plan: PublicationPlan, commitSHA: String) async -> PagesVerification
}

enum PagesVerification: Equatable {
    case pending
    case live
    case timedOut
    case unavailable
}

@MainActor
final class GitHubPagesVerifier: PagesVerifying {
    private let session: URLSession
    private let timeout: TimeInterval
    private let interval: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 480, interval: TimeInterval = 10) {
        self.session = session
        self.timeout = timeout
        self.interval = interval
    }

    func verify(plan: PublicationPlan, commitSHA: String) async -> PagesVerification {
        guard let dataFile = plan.files.first(where: { $0.path == "data.js" }),
              !plan.entries.isEmpty
        else { return .unavailable }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !Task.isCancelled {
            let dataURL = plan.target.publicSiteURL.appendingPathComponent("data.js")
            let imagesAreLive = await imagesMatch(plan)
            if let siteData = try? await fetch(plan.target.publicSiteURL),
               !siteData.isEmpty,
               let data = try? await fetch(dataURL),
               data == dataFile.data,
               imagesAreLive {
                return .live
            }
            try? await Task.sleep(for: .seconds(interval))
        }
        return Task.isCancelled ? .unavailable : .timedOut
    }

    private func imagesMatch(_ plan: PublicationPlan) async -> Bool {
        for entry in plan.entries {
            let imageURL = plan.target.publicSiteURL.appendingPathComponent(entry.imagePath)
            guard let imageData = try? await fetch(imageURL), imageData == entry.imageData else { return false }
        }
        return true
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}

enum PublicationStage: Equatable {
    case idle
    case preparing
    case ready
    case checkingConflict
    case uploading(Int, Int)
    case creatingCommit
    case updatingBranch
    case githubUpdated(String)
    case pagesLive(String)
    case pagesTimedOut(String)
    case conflict
    case failed(String)
}

extension PublicationStage {
    var isBusy: Bool {
        switch self {
        case .preparing, .checkingConflict, .uploading, .creatingCommit, .updatingBranch: true
        default: false
        }
    }

    var message: String {
        switch self {
        case .idle: ""
        case .preparing: "GitHubの最新状態を確認しています…"
        case .ready: "公開内容を確認してください。"
        case .checkingConflict: "公開直前の競合を確認しています…"
        case let .uploading(index, total): "公開用ファイルを準備しています（\(index)/\(total)）…"
        case .creatingCommit: "1つのGitコミットを作成しています…"
        case .updatingBranch: "mainブランチを安全に更新しています…"
        case let .githubUpdated(sha): "GitHub更新成功（\(sha.prefix(12))）。Pages反映を確認しています…"
        case let .pagesLive(sha): "GitHub更新とPages反映を確認しました（\(sha.prefix(12))）。"
        case let .pagesTimedOut(sha): "GitHub更新成功（\(sha.prefix(12))）。Pages反映は確認待ちです。再公開しないでください。"
        case .conflict: "mainが更新されました。最新データを再取得して再確認してください。"
        case let .failed(message): message
        }
    }
}

@MainActor
final class PublicationCoordinator: ObservableObject {
    @Published private(set) var stage: PublicationStage = .idle
    @Published private(set) var plan: PublicationPlan?
    @Published private(set) var hasStoredToken = false

    private let target: RepositoryTarget
    private let tokenStore: TokenStoring
    private let github: GitHubPublishing
    private let pagesVerifier: PagesVerifying

    init(
        target: RepositoryTarget = .tread,
        tokenStore: TokenStoring = KeychainTokenStore(),
        github: GitHubPublishing = GitHubAPI(),
        pagesVerifier: PagesVerifying = GitHubPagesVerifier()
    ) {
        self.target = target
        self.tokenStore = tokenStore
        self.github = github
        self.pagesVerifier = pagesVerifier
        refreshTokenStatus()
    }

    var canPrepare: Bool { hasStoredToken && !stage.isBusy }
    var canPublish: Bool { plan != nil && stage == .ready }

    func refreshTokenStatus() {
        hasStoredToken = (try? tokenStore.token(for: target)) != nil
    }

    func saveToken(_ token: String) throws {
        try tokenStore.save(token, for: target)
        hasStoredToken = true
    }

    func deleteToken() throws {
        try tokenStore.deleteToken(for: target)
        hasStoredToken = false
        plan = nil
        stage = .idle
    }

    func verifyConnection() async {
        do {
            let token = try requiredToken()
            _ = try await github.head(of: target, token: token)
            stage = .idle
        } catch {
            stage = .failed(safeMessage(error))
        }
    }

    func prepare(drafts: [DraftWheel]) async {
        guard !stage.isBusy else { return }
        stage = .preparing
        plan = nil
        do {
            let token = try requiredToken()
            let head = try await github.head(of: target, token: token)
            let remoteCatalogData = try await github.catalogData(at: head, target: target, token: token)
            plan = try PublicationPlanBuilder.make(catalogData: remoteCatalogData, drafts: drafts, expectedHead: head, target: target)
            stage = .ready
        } catch {
            stage = .failed(safeMessage(error))
        }
    }

    func invalidatePreparedPlan() {
        guard stage == .ready else { return }
        plan = nil
        stage = .idle
    }

    func publish() async {
        guard let plan, stage == .ready else { return }
        stage = .checkingConflict
        do {
            let token = try requiredToken()
            let currentHead = try await github.head(of: target, token: token)
            guard currentHead == plan.expectedHead else {
                self.plan = nil
                stage = .conflict
                return
            }

            var treeEntries: [GitTreeEntry] = []
            for (index, file) in plan.files.enumerated() {
                stage = .uploading(index + 1, plan.files.count)
                let blob = try await github.createBlob(data: file.data, target: target, token: token)
                treeEntries.append(GitTreeEntry(path: file.path, blobSHA: blob))
            }
            let baseTree = try await github.commitTreeSHA(head: currentHead, target: target, token: token)
            stage = .creatingCommit
            let tree = try await github.createTree(baseTree: baseTree, entries: treeEntries, target: target, token: token)
            let commit = try await github.createCommit(message: plan.commitMessage, tree: tree, parent: currentHead, target: target, token: token)
            stage = .updatingBranch
            try await github.updateBranch(head: commit, target: target, token: token)

            stage = .githubUpdated(commit)
            switch await pagesVerifier.verify(plan: plan, commitSHA: commit) {
            case .live: stage = .pagesLive(commit)
            case .pending, .timedOut: stage = .pagesTimedOut(commit)
            case .unavailable: stage = .githubUpdated(commit)
            }
        } catch let error as GitHubAPIError where error == .conflict {
            self.plan = nil
            stage = .conflict
        } catch {
            stage = .failed(safeMessage(error))
        }
    }

    private func requiredToken() throws -> String {
        guard let token = try tokenStore.token(for: target), !token.isEmpty else {
            throw KeychainTokenStoreError.invalidToken
        }
        return token
    }

    private func safeMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError, let message = localized.errorDescription { return message }
        return "公開処理に失敗しました。入力内容は保持されています。"
    }
}
