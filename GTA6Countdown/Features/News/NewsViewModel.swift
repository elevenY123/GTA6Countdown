import Combine
import Foundation

struct NewsPresentation: Equatable {
    let pinnedOfficial: NewsArticle?
    let articles: [NewsArticle]

    init(articles: [NewsArticle], pinnedOfficialArticleID: String?) {
        let pinnedOfficial = articles.first { article in
            article.id == pinnedOfficialArticleID
                && article.isPinned
                && article.isOfficial
                && article.credibility == .official
        }
        self.pinnedOfficial = pinnedOfficial
        let pinnedTopicKey = pinnedOfficial.map { Self.normalizedTopicKey($0.canonicalTopicKey) }
        let eligible = articles.filter { article in
            article.id != pinnedOfficial?.id
                && (pinnedTopicKey == nil
                    || Self.normalizedTopicKey(article.canonicalTopicKey) != pinnedTopicKey)
        }
        let deduplicated = Dictionary(grouping: eligible) {
            Self.normalizedTopicKey($0.canonicalTopicKey)
        }
            .compactMap { _, candidates in candidates.min(by: Self.isPreferred(_:over:)) }

        self.articles = deduplicated
            .sorted {
                if $0.publishedAt == $1.publishedAt { return $0.id < $1.id }
                return $0.publishedAt > $1.publishedAt
            }
    }

    private static func isPreferred(_ lhs: NewsArticle, over rhs: NewsArticle) -> Bool {
        let lhsRank = preferenceRank(for: lhs)
        let rhsRank = preferenceRank(for: rhs)
        if lhsRank != rhsRank { return lhsRank > rhsRank }
        if lhs.publishedAt != rhs.publishedAt { return lhs.publishedAt > rhs.publishedAt }
        return lhs.id < rhs.id
    }

    private static func preferenceRank(for article: NewsArticle) -> Int {
        if article.isOfficial && article.credibility == .official { return 3 }
        switch article.credibility {
        case .media: return 2
        case .unverified: return 1
        case .official: return 0
        }
    }

    private static func normalizedTopicKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

enum NewsRoute: Hashable {
    case article(id: String)

    static func articleURL(id: String) -> URL {
        WidgetNewsRoute.articleURL(id: id)!
    }

    init?(url: URL) {
        guard
            url.scheme?.lowercased() == "gta6countdown",
            url.host?.lowercased() == "news",
            url.path == "/article",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let id = components.queryItems?.first(where: { $0.name == "id" })?.value,
            !id.isEmpty
        else { return nil }
        self = .article(id: id)
    }
}

@MainActor
final class NewsViewModel: ObservableObject {
    @Published private(set) var payload: NewsPayload?
    @Published private(set) var source: NewsRepositorySource
    @Published private(set) var issue: NewsRepositoryIssue?
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasAttemptedRefresh = false

    private let repository: NewsRepositoryServing
    private var hasStartedInitialLoad = false

    init(repository: NewsRepositoryServing) {
        self.repository = repository
        let initial = repository.currentState
        payload = initial.payload
        source = initial.source
        issue = initial.nonblockingIssue
    }

    convenience init() {
        let endpointString = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        let endpoint = endpointString.flatMap(URL.init(string:))
            ?? URL(string: "https://example.invalid/v1/news.json")!
        let cache = try? SharedCache(
            appGroupIdentifier: "group.com.jaysuen.gta6countdown",
            filename: "news-payload.json"
        )
        let client: NewsFetching
        if ProcessInfo.processInfo.arguments.contains("--uitest-news-fixture"),
           let fixtureURL = Bundle.main.url(forResource: "news-payload", withExtension: "json") {
            client = BundledNewsFetcher(url: fixtureURL)
        } else {
            client = NewsAPIClient(endpoint: endpoint)
        }
        let payloadCache: NewsPayloadCaching
        if let cache {
            payloadCache = NewsPayloadCacheActor(cache: cache)
        } else {
            payloadCache = VolatileNewsCache()
        }
        self.init(repository: NewsRepository(
            client: client,
            cache: payloadCache
        ))
    }

    var presentation: NewsPresentation {
        NewsPresentation(
            articles: payload?.articles ?? [],
            pinnedOfficialArticleID: payload?.remoteConfig.pinnedOfficialArticleID
        )
    }

    var isInitialLoading: Bool {
        payload == nil && !hasAttemptedRefresh
    }

    var isUnavailable: Bool {
        payload == nil && hasAttemptedRefresh
    }

    var isEmpty: Bool {
        payload?.articles.isEmpty == true
    }

    func article(id: String) -> NewsArticle? {
        payload?.articles.first { $0.id == id }
    }

    func load() async {
        guard !hasStartedInitialLoad else { return }
        hasStartedInitialLoad = true
        apply(await repository.hydrate())
        await refresh()
    }

    func refresh() async {
        isRefreshing = true
        defer {
            isRefreshing = false
            hasAttemptedRefresh = true
        }
        apply(await repository.refresh())
    }

    private func apply(_ state: NewsRepositoryState) {
        payload = state.payload
        source = state.source
        issue = state.nonblockingIssue
    }
}

actor BundledNewsFetcher: NewsFetching {
    let url: URL

    init(url: URL) { self.url = url }

    func fetch() async throws -> NewsPayload {
        let payload: NewsPayload
        do {
            payload = try NewsPayload.decode(from: Data(contentsOf: url))
        } catch {
            throw NewsAPIClientError.invalidPayload
        }
        do {
            return try NewsPayloadValidator.validate(payload)
        } catch let error as NewsPayloadValidationError {
            switch error {
            case let .unsupportedSchema(version):
                throw NewsAPIClientError.unsupportedSchema(version)
            case .invalidPayload:
                throw NewsAPIClientError.invalidPayload
            }
        }
    }
}

private actor VolatileNewsCache: NewsPayloadCaching {
    func loadNewsPayload() -> NewsCacheLoadResult { .miss }
    func saveNewsPayload(_ payload: NewsPayload) throws {
        _ = try NewsPayloadValidator.validate(payload)
    }
}
