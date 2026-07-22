import Foundation
import XCTest
@testable import GTA6Countdown

final class NewsRepositoryTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NewsRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        URLProtocolStub.reset()
    }

    override func tearDownWithError() throws {
        URLProtocolStub.reset()
        if let rootURL { try? FileManager.default.removeItem(at: rootURL) }
    }

    func testSystemWidgetReloaderDelegatesThroughInjectedAction() {
        var reloadCount = 0
        let reloader = SystemWidgetReloader { reloadCount += 1 }

        reloader.reloadNewsWidgets()

        XCTAssertEqual(reloadCount, 1)
    }

    func testSystemWidgetReloaderTargetsOnlyNewsKind() {
        var reloadedKinds: [String] = []
        let reloader = SystemWidgetReloader(reloadTimelines: { reloadedKinds.append($0) })

        reloader.reloadNewsWidgets()

        XCTAssertEqual(reloadedKinds, [WidgetKinds.news])
    }

    @MainActor
    func testHydratePublishesValidCacheWithoutStartingNetwork() async throws {
        let cached = try cachedPayload()
        let client = SequenceNewsFetcher(results: [])
        let repository = NewsRepository(
            client: client,
            cache: RawNewsPayloadCache(result: .hit(cached)),
            widgetReloader: WidgetReloaderSpy()
        )

        XCTAssertNil(repository.currentState.payload)
        let state = await repository.hydrate()

        XCTAssertEqual(state.source, .cache)
        XCTAssertEqual(state.payload, cached)
        let fetchCount = await client.fetchCount
        XCTAssertEqual(fetchCount, 0)
    }

    @MainActor
    func testConcurrentHydrationSharesOneActorCacheRead() async throws {
        let cache = CountingNewsPayloadCache(result: .hit(try cachedPayload()))
        let repository = NewsRepository(
            client: SequenceNewsFetcher(results: []),
            cache: cache,
            widgetReloader: WidgetReloaderSpy()
        )

        async let first = repository.hydrate()
        async let second = repository.hydrate()
        let firstState = await first
        let secondState = await second
        let loadCount = await cache.loadCount

        XCTAssertEqual(firstState, secondState)
        XCTAssertEqual(loadCount, 1)
    }

    @MainActor
    func testLateHydrationHitOrFailureCannotOverwriteCompletedRefreshState() async throws {
        let fallback = try cachedPayload()
        let latePayloadData = try replacing(in: fixtureData()) { object in
            object["updatedAt"] = "2026-07-01T00:00:00Z"
        }
        let latePayload = try NewsPayload.decode(from: latePayloadData)

        for lateResult in [NewsCacheLoadResult.hit(latePayload), .failure] {
            let cache = SuspendedHydrationNewsCache(
                refreshFallback: .hit(fallback)
            )
            let repository = NewsRepository(
                client: SequenceNewsFetcher(results: [
                    .failure(URLError(.notConnectedToInternet))
                ]),
                cache: cache,
                widgetReloader: WidgetReloaderSpy()
            )

            let hydration = Task { await repository.hydrate() }
            while !(await cache.hasSuspendedHydration) { await Task.yield() }

            let refreshed = await repository.refresh()
            XCTAssertEqual(refreshed.source, .cache)
            XCTAssertEqual(refreshed.payload, fallback)
            XCTAssertEqual(refreshed.nonblockingIssue, .transport)

            await cache.resumeHydration(with: lateResult)
            _ = await hydration.value

            XCTAssertEqual(repository.currentState, refreshed)
            XCTAssertEqual(repository.currentState.nonblockingIssue, .transport)
        }
    }

    @MainActor
    func testEveryCoalescedRefreshCallerObservesAppliedCurrentState() async throws {
        let payload = try cachedPayload()
        let client = SuspendedNewsFetcher(payload: payload)
        let repository = NewsRepository(
            client: client,
            cache: RawNewsPayloadCache(result: .miss),
            widgetReloader: WidgetReloaderSpy()
        )

        let first = Task { () -> (NewsRepositoryState, NewsRepositoryState) in
            let result = await repository.refresh()
            return (result, repository.currentState)
        }
        while !(await client.hasRequest) { await Task.yield() }
        let second = Task { () -> (NewsRepositoryState, NewsRepositoryState) in
            let result = await repository.refresh()
            return (result, repository.currentState)
        }
        await Task.yield()
        await client.resume()

        let firstObservation = await first.value
        let secondObservation = await second.value

        XCTAssertEqual(firstObservation.0, firstObservation.1)
        XCTAssertEqual(secondObservation.0, secondObservation.1)
        XCTAssertEqual(firstObservation.0, secondObservation.0)
        XCTAssertEqual(repository.currentState, firstObservation.0)
    }

    @MainActor
    func testHydrateRejectsOldSchemaAndContradictoryOfficialCache() async throws {
        let oldSchema = try NewsPayload.decode(from: replacingSchemaVersion(in: fixtureData(), with: 0))
        let contradictoryData = try replacing(in: fixtureData()) { object in
            var articles = try XCTUnwrap(object["articles"] as? [[String: Any]])
            articles[0]["isOfficial"] = false
            object["articles"] = articles
        }
        let contradictory = try NewsPayload.decode(from: contradictoryData)

        for payload in [oldSchema, contradictory] {
            let storage = try makeCache()
            try storage.save(payload)
            let repository = NewsRepository(
                client: SequenceNewsFetcher(results: []),
                cache: NewsPayloadCacheActor(cache: storage),
                widgetReloader: WidgetReloaderSpy()
            )
            let state = await repository.hydrate()
            XCTAssertNil(state.payload)
            XCTAssertEqual(state.source, .unavailable)
            XCTAssertEqual(state.nonblockingIssue, .cacheRead)
        }
    }

    @MainActor
    func testRepositoryRejectsInvalidPayloadFromInjectedNetworkFetcher() async throws {
        let invalid = try NewsPayload.decode(
            from: replacingSchemaVersion(in: fixtureData(), with: 42)
        )
        let repository = NewsRepository(
            client: SequenceNewsFetcher(results: [.success(invalid)]),
            cache: RawNewsPayloadCache(result: .miss),
            widgetReloader: WidgetReloaderSpy()
        )

        let state = await repository.refresh()

        XCTAssertNil(state.payload)
        XCTAssertEqual(state.source, .unavailable)
        XCTAssertEqual(state.nonblockingIssue, .unsupportedSchema(42))
    }

    @MainActor
    func testNetworkFailureNeverFallsBackToInvalidCache() async throws {
        let invalid = try NewsPayload.decode(
            from: replacingSchemaVersion(in: fixtureData(), with: 0)
        )
        let repository = NewsRepository(
            client: SequenceNewsFetcher(results: [
                .failure(URLError(.notConnectedToInternet))
            ]),
            cache: RawNewsPayloadCache(result: .hit(invalid)),
            widgetReloader: WidgetReloaderSpy()
        )

        let state = await repository.refresh()

        XCTAssertNil(state.payload)
        XCTAssertEqual(state.source, .unavailable)
        XCTAssertEqual(state.nonblockingIssue, .transport)
    }

    @MainActor
    func testSuccessfulRefreshPersistsPayloadAndReloadsWidgets() async throws {
        let payloadData = try fixtureData()
        URLProtocolStub.install { request in
            (try Self.response(for: request.url, status: 200), payloadData)
        }
        let reloader = WidgetReloaderSpy()
        let cache = try makeCache()
        let repository = NewsRepository(
            client: makeClient(),
            cache: NewsPayloadCacheActor(cache: cache),
            widgetReloader: reloader
        )

        let state = await repository.refresh()

        XCTAssertEqual(state.source, .network)
        XCTAssertNil(state.nonblockingIssue)
        XCTAssertEqual(state.payload, try NewsPayload.decode(from: payloadData))
        guard case let .hit(cachedPayload) = cache.load(NewsPayload.self) else {
            return XCTFail("Expected persisted payload")
        }
        XCTAssertEqual(cachedPayload, state.payload)
        XCTAssertEqual(reloader.reloadCount, 1)
    }

    @MainActor
    func testHTTPFailureReturnsExistingCacheAndPreservesTimestamp() async throws {
        let cached = try cachedPayload()
        let cache = try makeCache()
        try cache.save(cached)
        URLProtocolStub.install { request in
            (try Self.response(for: request.url, status: 503), Data("unavailable".utf8))
        }
        let repository = NewsRepository(client: makeClient(), cache: NewsPayloadCacheActor(cache: cache), widgetReloader: WidgetReloaderSpy())

        let state = await repository.refresh()

        XCTAssertEqual(state.source, .cache)
        XCTAssertEqual(state.payload, cached)
        XCTAssertEqual(state.lastUpdatedAt, cached.updatedAt)
        XCTAssertEqual(state.nonblockingIssue, .httpStatus(503))
    }

    @MainActor
    func testTimeoutReturnsExistingCache() async throws {
        let cached = try cachedPayload()
        let cache = try makeCache()
        try cache.save(cached)
        URLProtocolStub.install { _ in throw URLError(.timedOut) }
        let repository = NewsRepository(client: makeClient(), cache: NewsPayloadCacheActor(cache: cache), widgetReloader: WidgetReloaderSpy())

        let state = await repository.refresh()

        XCTAssertEqual(state.source, .cache)
        XCTAssertEqual(state.payload, cached)
        XCTAssertEqual(state.nonblockingIssue, .transport)
    }

    @MainActor
    func testUnsupportedSchemaReturnsExistingCache() async throws {
        let cached = try cachedPayload()
        let cache = try makeCache()
        try cache.save(cached)
        let unsupported = try replacingSchemaVersion(in: fixtureData(), with: 99)
        URLProtocolStub.install { request in
            (try Self.response(for: request.url, status: 200), unsupported)
        }
        let repository = NewsRepository(client: makeClient(), cache: NewsPayloadCacheActor(cache: cache), widgetReloader: WidgetReloaderSpy())

        let state = await repository.refresh()

        XCTAssertEqual(state.source, .cache)
        XCTAssertEqual(state.payload, cached)
        XCTAssertEqual(state.nonblockingIssue, .unsupportedSchema(99))
    }

    @MainActor
    func testMalformedPayloadReturnsExistingCache() async throws {
        let cached = try cachedPayload()
        let cache = try makeCache()
        try cache.save(cached)
        URLProtocolStub.install { request in
            (try Self.response(for: request.url, status: 200), Data("{not-json}".utf8))
        }
        let repository = NewsRepository(client: makeClient(), cache: NewsPayloadCacheActor(cache: cache), widgetReloader: WidgetReloaderSpy())

        let state = await repository.refresh()

        XCTAssertEqual(state.source, .cache)
        XCTAssertEqual(state.payload, cached)
        XCTAssertEqual(state.nonblockingIssue, .invalidPayload)
    }

    @MainActor
    func testFailureWithoutCacheIsDistinctlyUnavailable() async throws {
        URLProtocolStub.install { _ in throw URLError(.notConnectedToInternet) }
        let repository = NewsRepository(
            client: makeClient(),
            cache: NewsPayloadCacheActor(cache: try makeCache()),
            widgetReloader: WidgetReloaderSpy()
        )

        let state = await repository.refresh()

        XCTAssertEqual(state.source, .unavailable)
        XCTAssertNil(state.payload)
        XCTAssertNil(state.lastUpdatedAt)
        XCTAssertEqual(state.nonblockingIssue, .transport)
    }

    @MainActor
    func testConcurrentRefreshesShareOneNetworkRequest() async throws {
        let payloadData = try fixtureData()
        URLProtocolStub.install(delay: 0.1) { request in
            (try Self.response(for: request.url, status: 200), payloadData)
        }
        let reloader = WidgetReloaderSpy()
        let repository = NewsRepository(
            client: makeClient(),
            cache: NewsPayloadCacheActor(cache: try makeCache()),
            widgetReloader: reloader
        )

        async let first = repository.refresh()
        async let second = repository.refresh()
        let firstState = await first
        let secondState = await second

        XCTAssertEqual(firstState, secondState)
        XCTAssertEqual(URLProtocolStub.requestCount, 1)
        XCTAssertEqual(reloader.reloadCount, 1)
    }

    @MainActor
    func testMemoryLastGoodSurvivesCacheWriteThenNetworkAndDiskFailure() async throws {
        let payload = try cachedPayload()
        let client = SequenceNewsFetcher(results: [
            .success(payload),
            .failure(URLError(.notConnectedToInternet))
        ])
        let cache = FailingNewsCache()
        let repository = NewsRepository(
            client: client,
            cache: cache,
            widgetReloader: WidgetReloaderSpy()
        )

        let first = await repository.refresh()
        let second = await repository.refresh()

        XCTAssertEqual(first.source, .network)
        XCTAssertEqual(first.payload, payload)
        XCTAssertEqual(first.nonblockingIssue, .cacheWrite)
        XCTAssertEqual(second.source, .cache)
        XCTAssertEqual(second.payload, payload)
        XCTAssertEqual(second.lastUpdatedAt, payload.updatedAt)
        XCTAssertEqual(second.nonblockingIssue, .transport)
    }

    @MainActor
    func testOlderDiskPayloadNeverReplacesNewerInMemoryLastGood() async throws {
        let oldPayload = try cachedPayload()
        let newData = try replacing(in: fixtureData()) { object in
            object["updatedAt"] = "2026-07-21T00:00:00Z"
        }
        let newPayload = try NewsPayload.decode(from: newData)
        let client = SequenceNewsFetcher(results: [
            .success(newPayload),
            .failure(URLError(.notConnectedToInternet))
        ])
        let cache = StaleFailingNewsCache(payload: oldPayload)
        let repository = NewsRepository(
            client: client,
            cache: cache,
            widgetReloader: WidgetReloaderSpy()
        )

        let first = await repository.refresh()
        let second = await repository.refresh()

        XCTAssertEqual(first.payload, newPayload)
        XCTAssertEqual(first.nonblockingIssue, .cacheWrite)
        XCTAssertEqual(second.source, .cache)
        XCTAssertEqual(second.payload, newPayload)
        XCTAssertEqual(second.lastUpdatedAt, newPayload.updatedAt)
        XCTAssertEqual(second.nonblockingIssue, .transport)
    }

    @MainActor
    func testRejectsRemoteConfigSchemaMismatch() async throws {
        let data = try replacing(in: fixtureData()) { object in
            var config = try XCTUnwrap(object["remoteConfig"] as? [String: Any])
            config["schemaVersion"] = 2
            object["remoteConfig"] = config
        }

        let error = await fetchError(for: data)
        XCTAssertEqual(error, .unsupportedSchema(2))
    }

    @MainActor
    func testRejectsBlankPresentationFieldsAndOfficialInconsistency() async throws {
        let mutations: [(inout [String: Any]) throws -> Void] = [
            { object in
                var articles = try XCTUnwrap(object["articles"] as? [[String: Any]])
                articles[0]["title"] = "   "
                object["articles"] = articles
            },
            { object in
                var articles = try XCTUnwrap(object["articles"] as? [[String: Any]])
                articles[0]["summary"] = "\n"
                object["articles"] = articles
            },
            { object in
                var articles = try XCTUnwrap(object["articles"] as? [[String: Any]])
                articles[0]["canonicalTopicKey"] = ""
                object["articles"] = articles
            },
            { object in
                var articles = try XCTUnwrap(object["articles"] as? [[String: Any]])
                articles[0]["isOfficial"] = false
                object["articles"] = articles
            }
        ]

        for mutation in mutations {
            let data = try replacing(in: fixtureData(), mutation)
            let error = await fetchError(for: data)
            XCTAssertEqual(error, .invalidPayload)
        }
    }

    @MainActor
    func testRejectsPinnedOfficialIDThatIsNotPinnedOfficialArticle() async throws {
        let data = try replacing(in: fixtureData()) { object in
            var config = try XCTUnwrap(object["remoteConfig"] as? [String: Any])
            config["pinnedOfficialArticleID"] = "media-1"
            object["remoteConfig"] = config
        }

        let error = await fetchError(for: data)
        XCTAssertEqual(error, .invalidPayload)
    }

    private func makeClient() -> NewsAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return NewsAPIClient(
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://api.example.com/news.json")!
        )
    }

    private func makeCache() throws -> SharedCache {
        try SharedCache(
            appGroupIdentifier: "group.test",
            filename: "news.json",
            appGroupContainerURL: { _ in nil },
            sandboxDirectoryURL: { self.rootURL }
        )
    }

    private func cachedPayload() throws -> NewsPayload {
        try NewsPayload.decode(from: fixtureData())
    }

    private func fixtureData() throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        return try Data(contentsOf: testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/news-payload.json"))
    }

    private func replacingSchemaVersion(in data: Data, with version: Int) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = version
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func replacing(
        in data: Data,
        _ mutation: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try mutation(&object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    @MainActor
    private func fetchError(for data: Data) async -> NewsAPIClientError? {
        URLProtocolStub.install { request in
            (try Self.response(for: request.url, status: 200), data)
        }
        do {
            _ = try await makeClient().fetch()
            XCTFail("Expected payload rejection")
            return nil
        } catch {
            return error as? NewsAPIClientError
        }
    }

    private static func response(for url: URL?, status: Int) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(
            url: try XCTUnwrap(url),
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
    }
}

private final class WidgetReloaderSpy: WidgetReloading {
    private(set) var reloadCount = 0
    func reloadNewsWidgets() { reloadCount += 1 }
}

private actor SequenceNewsFetcher: NewsFetching {
    private var results: [Result<NewsPayload, Error>]
    private(set) var fetchCount = 0

    init(results: [Result<NewsPayload, Error>]) {
        self.results = results
    }

    func fetch() async throws -> NewsPayload {
        fetchCount += 1
        guard !results.isEmpty else { throw URLError(.unknown) }
        return try results.removeFirst().get()
    }
}

private actor FailingNewsCache: NewsPayloadCaching {
    func loadNewsPayload() -> NewsCacheLoadResult { .miss }
    func saveNewsPayload(_ payload: NewsPayload) throws { throw SharedCacheError.writeFailed }
}

private actor StaleFailingNewsCache: NewsPayloadCaching {
    private let payload: NewsPayload

    init(payload: NewsPayload) {
        self.payload = payload
    }

    func loadNewsPayload() -> NewsCacheLoadResult { .hit(payload) }
    func saveNewsPayload(_ payload: NewsPayload) throws { throw SharedCacheError.writeFailed }
}

private actor RawNewsPayloadCache: NewsPayloadCaching {
    let result: NewsCacheLoadResult

    init(result: NewsCacheLoadResult) { self.result = result }

    func loadNewsPayload() -> NewsCacheLoadResult { result }
    func saveNewsPayload(_ payload: NewsPayload) throws {}
}

private actor CountingNewsPayloadCache: NewsPayloadCaching {
    let result: NewsCacheLoadResult
    private(set) var loadCount = 0

    init(result: NewsCacheLoadResult) { self.result = result }

    func loadNewsPayload() -> NewsCacheLoadResult {
        loadCount += 1
        return result
    }

    func saveNewsPayload(_ payload: NewsPayload) throws {}
}

private actor SuspendedHydrationNewsCache: NewsPayloadCaching {
    let refreshFallback: NewsCacheLoadResult
    private var loadCount = 0
    private var hydrationContinuation: CheckedContinuation<NewsCacheLoadResult, Never>?

    init(refreshFallback: NewsCacheLoadResult) {
        self.refreshFallback = refreshFallback
    }

    var hasSuspendedHydration: Bool { hydrationContinuation != nil }

    func loadNewsPayload() async -> NewsCacheLoadResult {
        loadCount += 1
        if loadCount == 1 {
            return await withCheckedContinuation { hydrationContinuation = $0 }
        }
        return refreshFallback
    }

    func resumeHydration(with result: NewsCacheLoadResult) {
        hydrationContinuation?.resume(returning: result)
        hydrationContinuation = nil
    }

    func saveNewsPayload(_ payload: NewsPayload) throws {}
}

private actor SuspendedNewsFetcher: NewsFetching {
    let payload: NewsPayload
    private var continuation: CheckedContinuation<Void, Never>?

    init(payload: NewsPayload) { self.payload = payload }

    var hasRequest: Bool { continuation != nil }

    func fetch() async throws -> NewsPayload {
        await withCheckedContinuation { continuation = $0 }
        return payload
    }

    func resume() {
        continuation?.resume(returning: ())
        continuation = nil
    }
}
