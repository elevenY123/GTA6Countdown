import Foundation
import XCTest
@testable import GTA6Countdown

final class NewsPresentationTests: XCTestCase {
    func testOnlyConfiguredPinnedOfficialArticleIsPromotedAndRemovedFromRows() throws {
        let official = try article(
            id: "rockstar-latest",
            publishedAt: "2026-07-18T10:00:00Z",
            credibility: "official",
            isOfficial: true,
            isPinned: true
        )
        let impostor = try article(
            id: "media-pinned",
            publishedAt: "2026-07-20T10:00:00Z",
            credibility: "media",
            isOfficial: false,
            isPinned: true
        )
        let ordinary = try article(id: "ordinary", publishedAt: "2026-07-19T10:00:00Z")

        let presentation = NewsPresentation(
            articles: [ordinary, impostor, official],
            pinnedOfficialArticleID: official.id
        )

        XCTAssertEqual(presentation.pinnedOfficial?.id, official.id)
        XCTAssertEqual(presentation.articles.map(\.id), [impostor.id, ordinary.id])
        XCTAssertFalse(presentation.articles.contains { $0.id == official.id })
    }

    func testRowsAreNewestFirstWhenNoValidOfficialPinExists() throws {
        let old = try article(id: "old", publishedAt: "2026-07-01T10:00:00Z")
        let newest = try article(id: "newest", publishedAt: "2026-07-20T10:00:00Z")

        let presentation = NewsPresentation(
            articles: [old, newest],
            pinnedOfficialArticleID: "missing"
        )

        XCTAssertNil(presentation.pinnedOfficial)
        XCTAssertEqual(presentation.articles.map(\.id), [newest.id, old.id])
    }

    func testCanonicalTopicDedupPrefersValidOfficialThenCredibilityThenNewestThenStableID() throws {
        let unverified = try article(
            id: "rumour",
            publishedAt: "2026-07-20T12:00:00Z",
            credibility: "unverified",
            canonicalTopicKey: "trailer"
        )
        let media = try article(
            id: "media",
            publishedAt: "2026-07-19T12:00:00Z",
            credibility: "media",
            canonicalTopicKey: "trailer"
        )
        let official = try article(
            id: "official",
            publishedAt: "2026-07-18T12:00:00Z",
            credibility: "official",
            isOfficial: true,
            relatedSourceCount: 7,
            canonicalTopicKey: "trailer"
        )
        let newerMedia = try article(
            id: "z-newer",
            publishedAt: "2026-07-20T12:00:00Z",
            credibility: "media",
            canonicalTopicKey: "platforms"
        )
        let olderMedia = try article(
            id: "a-older",
            publishedAt: "2026-07-18T12:00:00Z",
            credibility: "media",
            canonicalTopicKey: "platforms"
        )
        let stableB = try article(
            id: "b",
            publishedAt: "2026-07-17T12:00:00Z",
            credibility: "media",
            canonicalTopicKey: "release"
        )
        let stableA = try article(
            id: "a",
            publishedAt: "2026-07-17T12:00:00Z",
            credibility: "media",
            canonicalTopicKey: "release"
        )

        let result = NewsPresentation(
            articles: [unverified, media, official, olderMedia, newerMedia, stableB, stableA],
            pinnedOfficialArticleID: nil
        )

        XCTAssertEqual(Set(result.articles.map(\.id)), Set(["official", "z-newer", "a"]))
        XCTAssertEqual(result.articles.first(where: { $0.id == "official" })?.relatedSourceCount, 7)
    }

    func testPinnedTopicDoesNotReappearThroughAnotherSourceID() throws {
        let pinned = try article(
            id: "rockstar",
            publishedAt: "2026-07-18T12:00:00Z",
            credibility: "official",
            isOfficial: true,
            isPinned: true,
            canonicalTopicKey: "release-date"
        )
        let duplicate = try article(
            id: "media-copy",
            publishedAt: "2026-07-20T12:00:00Z",
            canonicalTopicKey: "release-date"
        )

        let result = NewsPresentation(
            articles: [duplicate, pinned],
            pinnedOfficialArticleID: pinned.id
        )

        XCTAssertEqual(result.pinnedOfficial?.id, pinned.id)
        XCTAssertTrue(result.articles.isEmpty)
    }

    func testCanonicalTopicDedupTrimsWhitespaceAndUsesLocaleStableCaseFolding() throws {
        let first = try article(
            id: "first",
            publishedAt: "2026-07-20T12:00:00Z",
            canonicalTopicKey: "  TRAILER-ONE  "
        )
        let preferred = try article(
            id: "preferred",
            publishedAt: "2026-07-21T12:00:00Z",
            canonicalTopicKey: "trailer-one"
        )

        let result = NewsPresentation(articles: [first, preferred], pinnedOfficialArticleID: nil)

        XCTAssertEqual(result.articles.map(\.id), ["preferred"])
    }

    func testCredibilityCopyExplainsEveryLevelWithoutClaimingRumoursAreFacts() {
        XCTAssertEqual(Credibility.official.displayName, "官方")
        XCTAssertEqual(Credibility.media.displayName, "媒体报道")
        XCTAssertEqual(Credibility.unverified.displayName, "未经证实")
        XCTAssertTrue(Credibility.unverified.explanation.contains("尚未"))
    }

    func testMetadataAlwaysIncludesSourceAndPublishedTime() throws {
        let value = try article(id: "metadata", publishedAt: "2026-07-20T10:30:00Z")
        let metadata = NewsMetadata(article: value)

        XCTAssertEqual(metadata.sourceName, "测试媒体")
        XCTAssertFalse(metadata.publishedText.isEmpty)
        XCTAssertTrue(metadata.accessibilityText.contains("测试媒体"))
        XCTAssertTrue(metadata.accessibilityText.contains(metadata.publishedText))
    }

    func testStableArticleDeepLinkRoundTripsUnicodeSafeID() {
        let id = "rockstar/露西亚 1"
        let url = NewsRoute.articleURL(id: id)

        XCTAssertEqual(NewsRoute(url: url), .article(id: id))
        XCTAssertNil(NewsRoute(url: URL(string: "https://example.com/news/article/1")!))
    }

    @MainActor
    func testCachedContentIsVisibleBeforeRefreshAndFailureStaysNonblocking() async throws {
        let payload = try fixturePayload()
        let repository = NewsRepositoryPresentationStub(
            initial: NewsRepositoryState(
                source: .cache,
                payload: payload,
                lastUpdatedAt: payload.updatedAt,
                nonblockingIssue: nil
            ),
            refreshResult: .cache(payload, issue: .transport)
        )
        let viewModel = NewsViewModel(repository: repository)

        XCTAssertFalse(viewModel.isInitialLoading)
        XCTAssertEqual(viewModel.presentation.pinnedOfficial?.id, "rockstar-1")

        await viewModel.refresh()

        XCTAssertEqual(viewModel.source, .cache)
        XCTAssertEqual(viewModel.issue, .transport)
        XCTAssertFalse(viewModel.isUnavailable)
        XCTAssertEqual(viewModel.presentation.articles.map(\.id), ["media-1"])
    }

    @MainActor
    func testInitialNetworkFailureWithoutCacheBecomesRecoverableUnavailableState() async {
        let repository = NewsRepositoryPresentationStub(
            initial: NewsRepositoryState(
                source: .unavailable,
                payload: nil,
                lastUpdatedAt: nil,
                nonblockingIssue: nil
            ),
            refreshResult: .unavailable(issue: .transport)
        )
        let viewModel = NewsViewModel(repository: repository)

        XCTAssertTrue(viewModel.isInitialLoading)
        await viewModel.load()

        XCTAssertTrue(viewModel.isUnavailable)
        XCTAssertEqual(viewModel.issue, .transport)
        XCTAssertEqual(repository.refreshCount, 1)
    }

    @MainActor
    func testInitialLoadHydratesCacheBeforeRefreshExactlyOnce() async throws {
        let payload = try fixturePayload()
        let hydrated = NewsRepositoryState(
            source: .cache,
            payload: payload,
            lastUpdatedAt: payload.updatedAt,
            nonblockingIssue: nil
        )
        let repository = NewsRepositoryPresentationStub(
            initial: NewsRepositoryState(
                source: .unavailable,
                payload: nil,
                lastUpdatedAt: nil,
                nonblockingIssue: nil
            ),
            refreshResult: .cache(payload, issue: .transport),
            hydrateResult: hydrated
        )
        let viewModel = NewsViewModel(repository: repository)

        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(repository.hydrateCount, 1)
        XCTAssertEqual(repository.refreshCount, 1)
        XCTAssertEqual(viewModel.payload, payload)
        XCTAssertEqual(viewModel.issue, .transport)
    }

    @MainActor
    func testEmptyPayloadAndRefreshingLifecycleAreObservable() async throws {
        let emptyPayload = try payload(replacingArticlesWith: [])
        let suspended = SuspendingNewsRepositoryStub(initial: .network(emptyPayload))
        let viewModel = NewsViewModel(repository: suspended)

        XCTAssertTrue(viewModel.isEmpty)
        let refresh = Task { await viewModel.refresh() }
        while !suspended.hasPendingRefresh { await Task.yield() }
        XCTAssertTrue(viewModel.isRefreshing)

        suspended.finish(with: .network(emptyPayload))
        await refresh.value
        XCTAssertFalse(viewModel.isRefreshing)
        XCTAssertTrue(viewModel.isEmpty)
    }

    func testDetailContractUsesOnlyShortSummaryAndValidatedOriginalURL() throws {
        let value = try article(id: "detail", publishedAt: "2026-07-20T10:30:00Z")
        let content = NewsDetailContent(article: value)
        var openedURL: URL?
        let action = NewsOriginalLinkAction { openedURL = $0 }

        XCTAssertEqual(content.summary, value.summary)
        XCTAssertEqual(content.originalURL, value.sourceURL)
        XCTAssertEqual(content.originalButtonTitle, "阅读原文")
        action.open(value.sourceURL)
        XCTAssertEqual(openedURL, value.sourceURL)
    }

    private func article(
        id: String,
        publishedAt: String,
        credibility: String = "media",
        isOfficial: Bool = false,
        isPinned: Bool = false,
        relatedSourceCount: Int = 0,
        canonicalTopicKey: String? = nil
    ) throws -> NewsArticle {
        let object: [String: Any] = [
            "id": id,
            "title": "\(id) 标题",
            "summary": "只展示简短导语，不复制新闻全文。",
            "sourceName": isOfficial ? "Rockstar Games" : "测试媒体",
            "sourceURL": "https://example.com/articles/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)",
            "publishedAt": publishedAt,
            "imageURL": "https://example.com/cover.jpg",
            "credibility": credibility,
            "isOfficial": isOfficial,
            "isPinned": isPinned,
            "relatedSourceCount": relatedSourceCount,
            "canonicalTopicKey": canonicalTopicKey ?? id
        ]
        return try JSONDecoder().decode(
            NewsArticle.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func payload(replacingArticlesWith articles: [[String: Any]]) throws -> NewsPayload {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/news-payload.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["articles"] = articles
        var config = try XCTUnwrap(object["remoteConfig"] as? [String: Any])
        config["pinnedOfficialArticleID"] = NSNull()
        object["remoteConfig"] = config
        return try NewsPayload.decode(from: JSONSerialization.data(withJSONObject: object))
    }

    private func fixturePayload() throws -> NewsPayload {
        let testsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let data = try Data(contentsOf: testsURL
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/news-payload.json"))
        return try NewsPayload.decode(from: data)
    }
}

@MainActor
private final class SuspendingNewsRepositoryStub: NewsRepositoryServing {
    let currentState: NewsRepositoryState
    private var continuation: CheckedContinuation<NewsRepositoryState, Never>?

    init(initial: NewsRepositoryState) { currentState = initial }

    var hasPendingRefresh: Bool { continuation != nil }

    func hydrate() async -> NewsRepositoryState { currentState }

    func refresh() async -> NewsRepositoryState {
        await withCheckedContinuation { continuation = $0 }
    }

    func finish(with state: NewsRepositoryState) {
        continuation?.resume(returning: state)
        continuation = nil
    }
}

@MainActor
private final class NewsRepositoryPresentationStub: NewsRepositoryServing {
    let currentState: NewsRepositoryState
    let refreshResult: NewsRepositoryState
    let hydrateResult: NewsRepositoryState
    private(set) var refreshCount = 0
    private(set) var hydrateCount = 0

    init(
        initial: NewsRepositoryState,
        refreshResult: NewsRepositoryState,
        hydrateResult: NewsRepositoryState? = nil
    ) {
        currentState = initial
        self.refreshResult = refreshResult
        self.hydrateResult = hydrateResult ?? initial
    }

    func refresh() async -> NewsRepositoryState {
        refreshCount += 1
        return refreshResult
    }

    func hydrate() async -> NewsRepositoryState {
        hydrateCount += 1
        return hydrateResult
    }
}
