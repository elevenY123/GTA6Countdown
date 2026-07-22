import Foundation
import WidgetKit

enum WidgetNewsStatus: Equatable, Sendable {
    case available(WidgetNewsDisplay, isCached: Bool)
    case empty
    case unavailable
}

struct WidgetNewsDisplay: Equatable, Sendable {
    let selection: WidgetNewsSelection
    let coverDataByArticleID: [String: Data]
}

struct CountdownWidgetEntry: TimelineEntry, Equatable, Sendable {
    let date: Date
    let content: WidgetCountdownContent
}

struct NewsWidgetEntry: TimelineEntry, Equatable, Sendable {
    let date: Date
    let status: WidgetNewsStatus
}

struct WidgetDataProvider {
    static let appGroupIdentifier = "group.com.jaysuen.gta6countdown"
    static let payloadFilename = "news-payload.json"

    private let loader: WidgetNewsLoader
    private let coverPipeline: WidgetCoverPipeline

    init(bundle: Bundle = .main) {
        let endpointString = bundle.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        let endpoint = endpointString.flatMap(URL.init(string:))
            ?? URL(string: "https://example.invalid/v1/news.json")!
        let cache = try? SharedCache(
            appGroupIdentifier: Self.appGroupIdentifier,
            filename: Self.payloadFilename
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        let client = NewsAPIClient(session: session, endpoint: endpoint)
        let coverTransport = WidgetBoundedImageTransport(configuration: configuration)
        let coverDownloader = WidgetCoverDownloader(transport: coverTransport)
        coverPipeline = WidgetCoverPipeline(maximumConcurrentLoads: 2) { article in
            await coverDownloader.data(for: article)
        }
        loader = WidgetNewsLoader(
            readCache: {
                guard let cache else { return .failure }
                switch cache.load(NewsPayload.self) {
                case let .hit(payload): return .hit(payload)
                case .miss: return .miss
                case .failure: return .failure
                }
            },
            fetchNetwork: { try await client.fetch() },
            persistNetworkPayload: { payload in
                guard let cache else { return }
                try? cache.save(payload)
            }
        )
    }

    init(
        loader: WidgetNewsLoader,
        coverPipeline: WidgetCoverPipeline = WidgetCoverPipeline { _ in nil }
    ) {
        self.loader = loader
        self.coverPipeline = coverPipeline
    }

    func loadPayload() async -> WidgetNewsLoadResult {
        await loader.load()
    }

    func loadNewsStatus() async -> WidgetNewsStatus {
        switch await loadPayload() {
        case let .cache(payload):
            return .available(await display(from: payload), isCached: true)
        case let .network(payload):
            return .available(await display(from: payload), isCached: false)
        case .empty:
            return .empty
        case .unavailable:
            return .unavailable
        }
    }

    private func display(from payload: NewsPayload) async -> WidgetNewsDisplay {
        let selection = WidgetNewsSelection.make(
            articles: payload.articles,
            pinnedOfficialArticleID: payload.remoteConfig.pinnedOfficialArticleID
        )
        let candidates = ([selection.largeLead].compactMap { $0 }
            + selection.largeRows
            + selection.medium).reduce(into: [NewsArticle]()) { result, article in
                if !result.contains(where: { $0.id == article.id }) { result.append(article) }
            }
        let covers = await coverPipeline.load(for: candidates, maximumCount: 4)
        return WidgetNewsDisplay(selection: selection, coverDataByArticleID: covers)
    }
}

struct CountdownTimelineProvider: TimelineProvider {
    typealias Entry = CountdownWidgetEntry

    private let dataProvider: WidgetDataProvider
    private let calendar: Calendar
    private let now: () -> Date

    init(
        dataProvider: WidgetDataProvider = WidgetDataProvider(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.dataProvider = dataProvider
        self.calendar = calendar
        self.now = now
    }

    func placeholder(in context: Context) -> Entry {
        Entry(
            date: now(),
            content: WidgetCountdownContent(
                daysRemaining: 487,
                message: "快了，快了。罪恶城正在靠近。",
                isReleased: false,
                releaseDate: CountdownCalculator().releaseDate
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let date = now()
        guard !context.isPreview else {
            completion(Entry(date: date, content: .make(at: date, calendar: calendar)))
            return
        }
        Task {
            let config = remoteConfig(from: await dataProvider.loadPayload())
            completion(Entry(
                date: date,
                content: .make(
                    at: date,
                    calendar: calendar,
                    releaseDateComponents: config?.releaseDateComponents
                        ?? RemoteConfig.defaultReleaseDateComponents,
                    remoteMilestoneMessages: config?.milestoneMessages ?? [:]
                )
            ))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let currentDate = now()
        Task {
            let result = await dataProvider.loadPayload()
            let config = remoteConfig(from: result)
            let plan = WidgetTimelinePlanner.countdownPlan(from: currentDate, calendar: calendar)
            let entries = plan.entryDates.map { date in
                Entry(
                    date: date,
                    content: .make(
                        at: date,
                        calendar: calendar,
                        releaseDateComponents: config?.releaseDateComponents ?? RemoteConfig.defaultReleaseDateComponents,
                        remoteMilestoneMessages: config?.milestoneMessages ?? [:]
                    )
                )
            }
            completion(Timeline(entries: entries, policy: .after(plan.nextRefresh)))
        }
    }

    private func remoteConfig(from result: WidgetNewsLoadResult) -> RemoteConfig? {
        switch result {
        case let .cache(payload), let .network(payload), let .empty(payload):
            return payload.remoteConfig
        case .unavailable:
            return nil
        }
    }
}

struct NewsTimelineProvider: TimelineProvider {
    typealias Entry = NewsWidgetEntry

    private let dataProvider: WidgetDataProvider
    private let now: () -> Date

    init(
        dataProvider: WidgetDataProvider = WidgetDataProvider(),
        now: @escaping () -> Date = Date.init
    ) {
        self.dataProvider = dataProvider
        self.now = now
    }

    func placeholder(in context: Context) -> Entry {
        Entry(date: now(), status: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let date = now()
        guard !context.isPreview else {
            completion(Entry(date: date, status: .empty))
            return
        }
        Task {
            completion(Entry(date: date, status: await dataProvider.loadNewsStatus()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let date = now()
        Task {
            let status = await dataProvider.loadNewsStatus()
            completion(Timeline(
                entries: [Entry(date: date, status: status)],
                policy: .after(date.addingTimeInterval(60 * 60))
            ))
        }
    }
}
