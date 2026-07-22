import Foundation
import UIKit
import XCTest
@testable import GTA6Countdown

final class WidgetTimelineTests: XCTestCase {
    func testCountdownTimelineIncludesTodayAndRefreshesAtNextLocalMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try date(2026, 8, 11, hour: 14, calendar: calendar)

        let plan = WidgetTimelinePlanner.countdownPlan(from: now, calendar: calendar)

        XCTAssertEqual(plan.entryDates, [now, try date(2026, 8, 12, hour: 0, calendar: calendar)])
        XCTAssertEqual(plan.nextRefresh, try date(2026, 8, 12, hour: 0, calendar: calendar))
    }

    func testCountdownPlanUsesNextLocalMidnightAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try date(2026, 3, 8, hour: 0, minute: 30, calendar: calendar)

        let plan = WidgetTimelinePlanner.countdownPlan(from: now, calendar: calendar)

        let nextMidnight = try date(2026, 3, 9, hour: 0, calendar: calendar)
        XCTAssertEqual(plan.entryDates.last, nextMidnight)
        XCTAssertEqual(plan.nextRefresh, nextMidnight)
        XCTAssertEqual(nextMidnight.timeIntervalSince(now), 22.5 * 60 * 60, accuracy: 1)
    }

    func testCountdownContentUsesRemoteDateAndSharedMilestoneCopy() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let release = DateComponents(year: 2026, month: 11, day: 20, hour: 0)
        let now = try date(2026, 11, 18, hour: 12, calendar: calendar)

        let content = WidgetCountdownContent.make(
            at: now,
            calendar: calendar,
            releaseDateComponents: release,
            remoteMilestoneMessages: ["2": "后天，新的莱昂尼达见。"]
        )

        XCTAssertEqual(content.daysRemaining, 2)
        XCTAssertEqual(content.message, "后天，新的莱昂尼达见。")
        XCTAssertFalse(content.isReleased)
        XCTAssertEqual(content.releaseDate, try date(2026, 11, 20, hour: 0, calendar: calendar))
    }

    func testCountdownContentShowsReleaseDayCopy() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let now = try date(2026, 11, 19, hour: 0, calendar: calendar)

        let content = WidgetCountdownContent.make(at: now, calendar: calendar)

        XCTAssertEqual(content.daysRemaining, 0)
        XCTAssertEqual(content.message, "等待结束。欢迎来到莱昂尼达。")
        XCTAssertTrue(content.isReleased)
    }

    func testCountdownContentCoversEveryRequiredMilestone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let release = try date(2026, 11, 19, hour: 0, calendar: calendar)
        let expected = [
            100: "最后一百天，正式开始。",
            50: "五十天后，阳光之州见。",
            20: "漫长等待，只剩二十天。",
            10: "两只手，已经数得过来了。",
            7: "最后一周，准备前往罪恶城。",
            6: "数字终于对上了：VI 天。",
            5: "等了这么多年，只剩五天。",
            4: "四天后，莱昂尼达见。",
            3: "三天。真的快了。",
            2: "后天，杰森与露西亚登场。",
            1: "明天。今晚大概睡不着了。"
        ]

        for (days, message) in expected {
            let start = try XCTUnwrap(calendar.date(byAdding: .day, value: -days, to: release))
            let midday = try XCTUnwrap(calendar.date(byAdding: .hour, value: 12, to: start))
            let content = WidgetCountdownContent.make(at: midday, calendar: calendar)
            XCTAssertEqual(content.daysRemaining, days)
            XCTAssertEqual(content.message, message)
        }
    }

    func testMediumNewsSelectsTwoItemsWithOfficialFirst() throws {
        let media = try article(id: "media", credibility: .media, isOfficial: false, offset: 30)
        let official = try article(id: "official", credibility: .official, isOfficial: true, offset: 0)
        let secondMedia = try article(id: "media-2", credibility: .media, isOfficial: false, offset: 20)

        let selection = WidgetNewsSelection.make(
            articles: [media, secondMedia, official],
            pinnedOfficialArticleID: "official"
        )

        XCTAssertEqual(selection.medium.map(\.id), ["official", "media"])
    }

    func testLargeNewsSelectsOneLeadOfficialAndThreeDistinctRows() throws {
        let official = try article(id: "official", topic: "trailer", credibility: .official, isOfficial: true, offset: 0)
        let duplicate = try article(id: "duplicate", topic: "trailer", credibility: .media, isOfficial: false, offset: 40)
        let rows = try (1...4).map { index in
            try article(
                id: "row-\(index)",
                topic: "topic-\(index)",
                credibility: .media,
                isOfficial: false,
                offset: TimeInterval(50 - index)
            )
        }

        let selection = WidgetNewsSelection.make(
            articles: [duplicate] + rows + [official],
            pinnedOfficialArticleID: "official"
        )

        XCTAssertEqual(selection.largeLead?.id, "official")
        XCTAssertEqual(selection.largeRows.map(\.id), ["row-1", "row-2", "row-3"])
        XCTAssertFalse(selection.largeRows.contains { $0.canonicalTopicKey == "trailer" })
    }

    func testArticleDeepLinkPercentEncodesUnicodeIdentifier() throws {
        let url = try XCTUnwrap(WidgetNewsRoute.articleURL(id: "中文 / VI?"))

        XCTAssertEqual(url.scheme, "gta6countdown")
        XCTAssertEqual(url.host, "news")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "中文 / VI?")
        XCTAssertEqual(WidgetNewsRoute.homeURL.absoluteString, "gta6countdown://home")
        XCTAssertEqual(WidgetNewsRoute.newsURL.absoluteString, "gta6countdown://news")
    }

    func testNewsLoaderFallsBackToNetworkWhenSharedCacheFails() async throws {
        let payload = try payload(articles: [
            article(id: "network", credibility: .media, isOfficial: false, offset: 0)
        ])
        var fetchCount = 0
        let loader = WidgetNewsLoader(
            readCache: { .failure },
            fetchNetwork: {
                fetchCount += 1
                return payload
            }
        )

        let result = await loader.load()

        XCTAssertEqual(result, .network(payload))
        XCTAssertEqual(fetchCount, 1)
    }

    func testNewsLoaderUsesValidCacheWithoutNetwork() async throws {
        let payload = try payload(articles: [
            article(id: "cached", credibility: .media, isOfficial: false, offset: 0)
        ])
        var fetchCount = 0
        let loader = WidgetNewsLoader(
            readCache: { .hit(payload) },
            fetchNetwork: {
                fetchCount += 1
                return payload
            },
            now: { payload.updatedAt }
        )

        let result = await loader.load()

        XCTAssertEqual(result, .cache(payload))
        XCTAssertEqual(fetchCount, 0)
    }

    func testNewsLoaderKeepsStaleSnapshotWhenRefreshFails() async throws {
        let payload = try payload(articles: [
            article(id: "stale", credibility: .media, isOfficial: false, offset: 0)
        ])
        let loader = WidgetNewsLoader(
            readCache: { .hit(payload) },
            fetchNetwork: { throw URLError(.notConnectedToInternet) },
            now: { payload.updatedAt.addingTimeInterval(3 * 60 * 60) }
        )

        let result = await loader.load()

        XCTAssertEqual(result, .cache(payload))
    }

    func testNewsLoaderRejectsImplausiblyFutureCacheTimestamp() async throws {
        let payload = try payload(articles: [
            article(id: "future", credibility: .media, isOfficial: false, offset: 0)
        ])
        var fetchCount = 0
        let loader = WidgetNewsLoader(
            readCache: { .hit(payload) },
            fetchNetwork: {
                fetchCount += 1
                return payload
            },
            now: { payload.updatedAt.addingTimeInterval(-6 * 60) }
        )

        _ = await loader.load()

        XCTAssertEqual(fetchCount, 1)
    }

    func testWidgetLayoutPolicyCompactsAccessibilitySizes() {
        let normalMedium = WidgetLayoutPolicy.make(family: .medium, isAccessibilitySize: false)
        let accessibleMedium = WidgetLayoutPolicy.make(family: .medium, isAccessibilitySize: true)
        let accessibleLarge = WidgetLayoutPolicy.make(family: .large, isAccessibilitySize: true)

        XCTAssertEqual(normalMedium.newsRowLimit, 2)
        XCTAssertEqual(accessibleMedium.newsRowLimit, 1)
        XCTAssertFalse(accessibleMedium.showsNewsMetadata)
        XCTAssertEqual(accessibleLarge.newsRowLimit, 1)
        XCTAssertFalse(accessibleLarge.showsCountdownMessage)
    }

    func testImageResponseValidatorRejectsHTTPMimeAndSizeViolations() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/cover.jpg"))
        let valid = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg", "Content-Length": "1024"]
        ))
        XCTAssertNoThrow(try WidgetImageResponseValidator.validate(valid, fileSize: 1024, maximumSize: 2048))

        let html = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        ))
        let serverError = try XCTUnwrap(HTTPURLResponse(
            url: url,
            statusCode: 503,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        ))
        XCTAssertThrowsError(try WidgetImageResponseValidator.validate(html, fileSize: 100, maximumSize: 2048))
        XCTAssertThrowsError(try WidgetImageResponseValidator.validate(serverError, fileSize: 100, maximumSize: 2048))
        XCTAssertThrowsError(try WidgetImageResponseValidator.validate(valid, fileSize: 4096, maximumSize: 2048))
    }

    func testCoverPipelineLimitsConcurrencyAndSkipsFailures() async throws {
        let tracker = WidgetImageConcurrencyTracker()
        let articles = try (1...5).map {
            try article(id: "image-\($0)", credibility: .media, isOfficial: false, offset: TimeInterval($0))
        }
        let pipeline = WidgetCoverPipeline(maximumConcurrentLoads: 2) { article in
            await tracker.started()
            await tracker.finished()
            return article.id == "image-3" ? nil : Data(article.id.utf8)
        }

        let covers = await pipeline.load(for: articles, maximumCount: 4)

        let maximumObserved = await tracker.maximumObserved
        let startedCount = await tracker.startedCount

        XCTAssertEqual(maximumObserved, 2)
        XCTAssertEqual(startedCount, 4)
        XCTAssertNil(covers["image-3"])
        XCTAssertEqual(covers.count, 3)
    }

    func testCoverPipelineDropsOversizedDataBeforeBuildingEntry() async throws {
        let article = try article(
            id: "oversized",
            credibility: .media,
            isOfficial: false,
            offset: 0
        )
        let pipeline = WidgetCoverPipeline(maximumItemSize: 4) { _ in Data(repeating: 1, count: 5) }

        let covers = await pipeline.load(for: [article], maximumCount: 1)

        XCTAssertTrue(covers.isEmpty)
    }

    func testBoundedTransportCancelsStreamingResponseAsSoonAsLimitIsExceeded() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/large-cover.jpg"))
        WidgetStreamingURLProtocolStub.configure(
            response: try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/jpeg"]
            )),
            chunks: [Data(repeating: 1, count: 3), Data(repeating: 2, count: 3), Data(repeating: 3, count: 3)]
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WidgetStreamingURLProtocolStub.self]
        let transport = WidgetBoundedImageTransport(configuration: configuration)

        do {
            _ = try await transport.data(from: url, maximumSize: 5)
            XCTFail("Expected the streaming transfer to stop at the hard limit")
        } catch {
            XCTAssertEqual(error as? WidgetImageResponseError, .responseTooLarge)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        let observation = WidgetStreamingURLProtocolStub.observation()
        XCTAssertTrue(observation.didStop)
        XCTAssertLessThan(observation.deliveredChunks, 3)
    }

    func testBoundedTransportRejectsOversizedDeclaredLengthBeforeBody() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/declared-large.jpg"))
        WidgetStreamingURLProtocolStub.configure(
            response: try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/jpeg", "Content-Length": "100"]
            )),
            chunks: [Data([1])]
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WidgetStreamingURLProtocolStub.self]
        let transport = WidgetBoundedImageTransport(configuration: configuration)

        do {
            _ = try await transport.data(from: url, maximumSize: 5)
            XCTFail("Expected rejection from Content-Length")
        } catch {
            XCTAssertEqual(error as? WidgetImageResponseError, .responseTooLarge)
        }

        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(WidgetStreamingURLProtocolStub.observation().deliveredChunks, 0)
    }

    func testCoverPipelineDeadlineReturnsPartialResultsAndCancelsSlowLoads() async throws {
        let articles = try (1...4).map {
            try article(id: "deadline-\($0)", credibility: .media, isOfficial: false, offset: TimeInterval($0))
        }
        let tracker = WidgetCancellationTracker()
        let pipeline = WidgetCoverPipeline(
            maximumConcurrentLoads: 4,
            deadlineNanoseconds: 60_000_000
        ) { article in
            if article.id == "deadline-1" { return Data([1]) }
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return Data([2])
            } catch {
                await tracker.recordCancellation()
                return nil
            }
        }
        let start = Date()

        let covers = await pipeline.load(for: articles, maximumCount: 4)
        let elapsed = Date().timeIntervalSince(start)
        let cancellationCount = await tracker.cancellationCount

        XCTAssertEqual(covers, ["deadline-1": Data([1])])
        XCTAssertLessThan(elapsed, 0.5)
        XCTAssertEqual(cancellationCount, 3)
    }

    func testCoverStoreExpiresOldDataAndRejectsCorruption() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetCoverStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try XCTUnwrap(URL(string: "https://example.com/cached.jpg"))
        let now = Date()
        let validData = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
            .image { context in
                context.cgContext.setFillColor(UIColor.systemPink.cgColor)
                context.cgContext.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
            .jpegData(compressionQuality: 0.8))
        let freshStore = WidgetCoverStore(directoryURL: directory, now: { now })
        await freshStore.save(validData, for: url)

        let freshData = await freshStore.data(for: url)
        XCTAssertNotNil(freshData)

        let staleStore = WidgetCoverStore(
            directoryURL: directory,
            now: { now.addingTimeInterval(25 * 60 * 60) }
        )
        let staleData = await staleStore.data(for: url)
        XCTAssertNil(staleData)

        await freshStore.save(Data([0, 1, 2, 3]), for: url)
        let corruptData = await freshStore.data(for: url)
        XCTAssertNil(corruptData)
    }

    func testNewsLoaderPersistsSuccessfulNetworkFallback() async throws {
        let payload = try payload(articles: [
            article(id: "network", credibility: .media, isOfficial: false, offset: 0)
        ])
        var persisted: NewsPayload?
        let loader = WidgetNewsLoader(
            readCache: { .miss },
            fetchNetwork: { payload },
            persistNetworkPayload: { persisted = $0 }
        )

        let result = await loader.load()

        XCTAssertEqual(result, .network(payload))
        XCTAssertEqual(persisted, payload)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int,
        minute: Int = 0,
        calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )))
    }

    private func article(
        id: String,
        topic: String? = nil,
        credibility: Credibility,
        isOfficial: Bool,
        offset: TimeInterval
    ) throws -> NewsArticle {
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id,
            "title": "标题 \(id)",
            "summary": "摘要",
            "sourceName": isOfficial ? "Rockstar Games" : "中文媒体",
            "sourceURL": "https://example.com/\(id)",
            "publishedAt": APIDateCoding.string(from: Date(timeIntervalSince1970: 2_000 + offset)),
            "credibility": credibility.rawValue,
            "isOfficial": isOfficial,
            "isPinned": isOfficial,
            "relatedSourceCount": 1,
            "canonicalTopicKey": topic ?? id
        ])
        return try JSONDecoder().decode(NewsArticle.self, from: data)
    }

    private func payload(articles: [NewsArticle]) throws -> NewsPayload {
        let encodedArticles = try JSONSerialization.jsonObject(with: JSONEncoder().encode(articles))
        let data = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "updatedAt": "2026-07-20T00:00:00Z",
            "remoteConfig": [
                "releaseDate": "2026-11-19",
                "releaseTimeMode": "localMidnight",
                "milestoneMessages": [:],
                "lastUpdatedAt": "2026-07-20T00:00:00Z",
                "schemaVersion": 1
            ],
            "articles": encodedArticles
        ])
        return try JSONDecoder().decode(NewsPayload.self, from: data)
    }
}

private actor WidgetImageConcurrencyTracker {
    private var active = 0
    private var firstInBatch: CheckedContinuation<Void, Never>?
    private(set) var maximumObserved = 0
    private(set) var startedCount = 0

    func started() async {
        active += 1
        startedCount += 1
        maximumObserved = max(maximumObserved, active)
        if active == 2 {
            firstInBatch?.resume()
            firstInBatch = nil
        } else {
            await withCheckedContinuation { continuation in
                firstInBatch = continuation
            }
        }
    }

    func finished() {
        active -= 1
    }
}

private actor WidgetCancellationTracker {
    private(set) var cancellationCount = 0
    func recordCancellation() { cancellationCount += 1 }
}

private final class WidgetStreamingURLProtocolStub: URLProtocol {
    struct Observation {
        let deliveredChunks: Int
        let didStop: Bool
    }

    private static let lock = NSLock()
    private static var response: HTTPURLResponse?
    private static var chunks: [Data] = []
    private static var deliveredChunks = 0
    private static var didStop = false
    private var stopped = false

    static func configure(response: HTTPURLResponse, chunks: [Data]) {
        lock.lock()
        self.response = response
        self.chunks = chunks
        deliveredChunks = 0
        didStop = false
        lock.unlock()
    }

    static func observation() -> Observation {
        lock.lock()
        defer { lock.unlock() }
        return Observation(deliveredChunks: deliveredChunks, didStop: didStop)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let response = Self.response
        Self.lock.unlock()
        guard let response else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        sendChunk(at: 0)
    }

    override func stopLoading() {
        Self.lock.lock()
        stopped = true
        Self.didStop = true
        Self.lock.unlock()
    }

    private func sendChunk(at index: Int) {
        // Leave enough time for URLSession's delegate queue to process the
        // response disposition or overflow cancellation before the stub emits
        // another chunk. A 10 ms gap is shorter than a loaded CI simulator's
        // scheduling latency and makes the cancellation assertion racy.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { [self] in
            Self.lock.lock()
            guard !stopped, index < Self.chunks.count else {
                Self.lock.unlock()
                return
            }
            let chunk = Self.chunks[index]
            Self.deliveredChunks += 1
            Self.lock.unlock()
            client?.urlProtocol(self, didLoad: chunk)
            if index + 1 == Self.chunks.count {
                client?.urlProtocolDidFinishLoading(self)
            } else {
                sendChunk(at: index + 1)
            }
        }
    }
}
