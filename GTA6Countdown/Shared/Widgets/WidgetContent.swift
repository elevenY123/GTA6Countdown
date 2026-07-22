import Foundation

enum WidgetKinds {
    static let countdown = "com.jaysuen.gta6countdown.widget.countdown"
    static let news = "com.jaysuen.gta6countdown.widget.news"
}

struct WidgetCountdownTimelinePlan: Equatable, Sendable {
    let entryDates: [Date]
    let nextRefresh: Date
}

enum WidgetTimelinePlanner {
    /// Keep only the current and next-midnight entries, then ask WidgetKit for
    /// a fresh timeline. This lets device-time-zone and remote-config changes
    /// take effect daily instead of being archived into a month-long timeline.
    static func countdownPlan(from now: Date, calendar: Calendar) -> WidgetCountdownTimelinePlan {
        guard let firstMidnight = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: now)
        ) else {
            let fallback = now.addingTimeInterval(60 * 60)
            return WidgetCountdownTimelinePlan(entryDates: [now], nextRefresh: fallback)
        }
        return WidgetCountdownTimelinePlan(
            entryDates: [now, firstMidnight],
            nextRefresh: firstMidnight
        )
    }
}

struct WidgetCountdownContent: Equatable, Sendable {
    let daysRemaining: Int
    let message: String
    let isReleased: Bool
    let releaseDate: Date

    static func make(
        at date: Date,
        calendar: Calendar = .autoupdatingCurrent,
        releaseDateComponents: DateComponents = RemoteConfig.defaultReleaseDateComponents,
        remoteMilestoneMessages: [String: String] = [:]
    ) -> Self {
        let calculator = CountdownCalculator(
            calendar: gregorianCalendar(following: calendar),
            clock: FixedCountdownClock(now: date),
            releaseDateComponents: releaseDateComponents
        )
        let state = calculator.state()
        let milestoneKey = state.isReleased ? "0" : String(state.calendarDaysRemaining)
        let override = remoteMilestoneMessages[milestoneKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message: String
        if let override, !override.isEmpty {
            message = override
        } else {
            message = MilestoneMessage.text(for: state)
        }
        return Self(
            daysRemaining: state.calendarDaysRemaining,
            message: message,
            isReleased: state.isReleased,
            releaseDate: calculator.releaseDate
        )
    }

    private static func gregorianCalendar(following deviceCalendar: Calendar) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = deviceCalendar.locale
        calendar.timeZone = deviceCalendar.timeZone
        return calendar
    }
}

struct WidgetNewsSelection: Equatable, Sendable {
    let medium: [NewsArticle]
    let largeLead: NewsArticle?
    let largeRows: [NewsArticle]

    static func make(
        articles: [NewsArticle],
        pinnedOfficialArticleID: String?
    ) -> Self {
        let deduplicated = deduplicate(articles)
        let official = deduplicated.first {
            $0.id == pinnedOfficialArticleID
                && $0.isOfficial
                && $0.credibility == .official
        } ?? deduplicated.first {
            $0.isOfficial && $0.credibility == .official
        }
        let ordered = ([official].compactMap { $0 } + deduplicated.filter { $0.id != official?.id })
        let lead = official ?? ordered.first
        let leadTopic = lead.map { normalizedTopic($0.canonicalTopicKey) }
        let rows = ordered.filter {
            $0.id != lead?.id && normalizedTopic($0.canonicalTopicKey) != leadTopic
        }
        return Self(
            medium: Array(ordered.prefix(2)),
            largeLead: lead,
            largeRows: Array(rows.prefix(3))
        )
    }

    private static func deduplicate(_ articles: [NewsArticle]) -> [NewsArticle] {
        Dictionary(grouping: articles, by: { normalizedTopic($0.canonicalTopicKey) })
            .compactMap { _, candidates in candidates.min(by: preferred(_:over:)) }
            .sorted {
                if $0.publishedAt == $1.publishedAt { return $0.id < $1.id }
                return $0.publishedAt > $1.publishedAt
            }
    }

    private static func preferred(_ lhs: NewsArticle, over rhs: NewsArticle) -> Bool {
        let lhsRank = rank(lhs)
        let rhsRank = rank(rhs)
        if lhsRank != rhsRank { return lhsRank > rhsRank }
        if lhs.publishedAt != rhs.publishedAt { return lhs.publishedAt > rhs.publishedAt }
        return lhs.id < rhs.id
    }

    private static func rank(_ article: NewsArticle) -> Int {
        if article.isOfficial && article.credibility == .official { return 3 }
        switch article.credibility {
        case .media: return 2
        case .unverified: return 1
        case .official: return 0
        }
    }

    private static func normalizedTopic(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

enum WidgetNewsRoute {
    static let homeURL = URL(string: "gta6countdown://home")!
    static let newsURL = URL(string: "gta6countdown://news")!

    static func articleURL(id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "gta6countdown"
        components.host = "news"
        components.path = "/article"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url
    }
}

enum WidgetLayoutFamily: Equatable, Sendable {
    case small
    case medium
    case large
}

struct WidgetLayoutPolicy: Equatable, Sendable {
    let newsRowLimit: Int
    let showsNewsMetadata: Bool
    let showsCountdownMessage: Bool

    static func make(
        family: WidgetLayoutFamily,
        isAccessibilitySize: Bool
    ) -> Self {
        if isAccessibilitySize {
            return Self(
                newsRowLimit: family == .small ? 0 : 1,
                showsNewsMetadata: false,
                showsCountdownMessage: false
            )
        }
        return Self(
            newsRowLimit: family == .large ? 3 : 2,
            showsNewsMetadata: true,
            showsCountdownMessage: true
        )
    }
}

enum WidgetPayloadReadResult {
    case hit(NewsPayload)
    case miss
    case failure
}

enum WidgetNewsLoadResult: Equatable {
    case cache(NewsPayload)
    case network(NewsPayload)
    case empty(NewsPayload)
    case unavailable
}

struct WidgetNewsLoader {
    private let readCache: () async -> WidgetPayloadReadResult
    private let fetchNetwork: () async throws -> NewsPayload
    private let persistNetworkPayload: (NewsPayload) async -> Void
    private let now: () -> Date
    private let freshnessInterval: TimeInterval

    init(
        readCache: @escaping () async -> WidgetPayloadReadResult,
        fetchNetwork: @escaping () async throws -> NewsPayload,
        persistNetworkPayload: @escaping (NewsPayload) async -> Void = { _ in },
        now: @escaping () -> Date = Date.init,
        freshnessInterval: TimeInterval = 2 * 60 * 60
    ) {
        self.readCache = readCache
        self.fetchNetwork = fetchNetwork
        self.persistNetworkPayload = persistNetworkPayload
        self.now = now
        self.freshnessInterval = freshnessInterval
    }

    func load() async -> WidgetNewsLoadResult {
        var stalePayload: NewsPayload?
        switch await readCache() {
        case let .hit(payload):
            if let valid = try? NewsPayloadValidator.validate(payload) {
                let age = now().timeIntervalSince(valid.updatedAt)
                if age >= -5 * 60, age <= freshnessInterval {
                    return valid.articles.isEmpty ? .empty(valid) : .cache(valid)
                }
                stalePayload = valid
            }
        case .miss, .failure:
            break
        }

        do {
            let payload = try NewsPayloadValidator.validate(await fetchNetwork())
            await persistNetworkPayload(payload)
            return payload.articles.isEmpty ? .empty(payload) : .network(payload)
        } catch {
            if let stalePayload {
                return stalePayload.articles.isEmpty ? .empty(stalePayload) : .cache(stalePayload)
            }
            return .unavailable
        }
    }
}
