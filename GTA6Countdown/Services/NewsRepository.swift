import Foundation
import WidgetKit

protocol WidgetReloading: AnyObject {
    func reloadNewsWidgets()
}

final class NoopWidgetReloader: WidgetReloading {
    func reloadNewsWidgets() {}
}

final class SystemWidgetReloader: WidgetReloading {
    private let reloadNewsTimelines: (String) -> Void

    init(reloadTimelines: @escaping (String) -> Void = { kind in
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }) {
        self.reloadNewsTimelines = reloadTimelines
    }

    /// Compatibility injection for existing tests and previews that only need
    /// to observe that a reload happened. Production always uses the kind-aware
    /// initializer above.
    init(reloadAllTimelines: @escaping () -> Void) {
        reloadNewsTimelines = { _ in reloadAllTimelines() }
    }

    func reloadNewsWidgets() {
        reloadNewsTimelines(WidgetKinds.news)
    }
}

enum NewsRepositorySource: Equatable, Sendable {
    case network
    case cache
    case unavailable
}

enum NewsRepositoryIssue: Error, Equatable, Sendable {
    case transport
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload
    case unsupportedSchema(Int)
    case cacheRead
    case cacheWrite
}

struct NewsRepositoryState: Equatable, Sendable {
    let source: NewsRepositorySource
    let payload: NewsPayload?
    let lastUpdatedAt: Date?
    let nonblockingIssue: NewsRepositoryIssue?

    static func network(_ payload: NewsPayload, issue: NewsRepositoryIssue? = nil) -> Self {
        Self(
            source: .network,
            payload: payload,
            lastUpdatedAt: payload.updatedAt,
            nonblockingIssue: issue
        )
    }

    static func cache(_ payload: NewsPayload, issue: NewsRepositoryIssue) -> Self {
        Self(
            source: .cache,
            payload: payload,
            lastUpdatedAt: payload.updatedAt,
            nonblockingIssue: issue
        )
    }

    static func unavailable(issue: NewsRepositoryIssue) -> Self {
        Self(
            source: .unavailable,
            payload: nil,
            lastUpdatedAt: nil,
            nonblockingIssue: issue
        )
    }
}

enum NewsCacheLoadResult: Sendable {
    case hit(NewsPayload)
    case miss
    case failure
}

protocol NewsPayloadCaching: Sendable {
    func loadNewsPayload() async -> NewsCacheLoadResult
    func saveNewsPayload(_ payload: NewsPayload) async throws
}

actor NewsPayloadCacheActor: NewsPayloadCaching {
    private let cache: SharedCache

    init(cache: SharedCache) {
        self.cache = cache
    }

    func loadNewsPayload() -> NewsCacheLoadResult {
        switch cache.load(NewsPayload.self) {
        case let .hit(payload):
            do {
                return .hit(try NewsPayloadValidator.validate(payload))
            } catch {
                return .failure
            }
        case .miss:
            return .miss
        case .failure:
            return .failure
        }
    }

    func saveNewsPayload(_ payload: NewsPayload) throws {
        _ = try NewsPayloadValidator.validate(payload)
        try cache.save(payload)
    }
}

@MainActor
final class NewsRepository {
    private let client: NewsFetching
    private let cache: NewsPayloadCaching
    private let widgetReloader: WidgetReloading
    private var inFlight: Task<NewsRepositoryState, Never>?
    private var hydrationTask: Task<NewsCacheLoadResult, Never>?
    private var hydrationGeneration: Int?
    private var didHydrate = false
    private var stateGeneration = 0
    private var lastGoodPayload: NewsPayload?

    private(set) var state: NewsRepositoryState

    init(
        client: NewsFetching,
        cache: NewsPayloadCaching,
        widgetReloader: WidgetReloading = SystemWidgetReloader()
    ) {
        self.client = client
        self.cache = cache
        self.widgetReloader = widgetReloader
        lastGoodPayload = nil
        state = NewsRepositoryState(
            source: .unavailable,
            payload: nil,
            lastUpdatedAt: nil,
            nonblockingIssue: nil
        )
    }

    func hydrate() async -> NewsRepositoryState {
        if didHydrate { return state }
        if let hydrationTask {
            let expectedGeneration = hydrationGeneration ?? stateGeneration
            let result = await hydrationTask.value
            return applyHydration(result, expectedGeneration: expectedGeneration)
        }

        let expectedGeneration = stateGeneration
        let cache = self.cache
        let task = Task { await cache.loadNewsPayload() }
        hydrationTask = task
        hydrationGeneration = expectedGeneration
        let result = await task.value
        hydrationTask = nil
        hydrationGeneration = nil
        return applyHydration(result, expectedGeneration: expectedGeneration)
    }

    func refresh() async -> NewsRepositoryState {
        if let inFlight {
            return await inFlight.value
        }

        let task = Task {
            let result = await performRefresh()
            state = result
            stateGeneration += 1
            return result
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func performRefresh() async -> NewsRepositoryState {
        do {
            let payload = try NewsPayloadValidator.validate(await client.fetch())
            lastGoodPayload = payload
            do {
                try await cache.saveNewsPayload(payload)
                widgetReloader.reloadNewsWidgets()
                return .network(payload)
            } catch {
                return .network(payload, issue: .cacheWrite)
            }
        } catch {
            let issue = Self.issue(for: error)
            switch Self.validatedCacheResult(await cache.loadNewsPayload()) {
            case let .hit(payload):
                let selectedPayload = Self.freshestPayload(lastGoodPayload, payload)
                lastGoodPayload = selectedPayload
                return .cache(selectedPayload, issue: issue)
            case .miss:
                if let lastGoodPayload {
                    return .cache(lastGoodPayload, issue: issue)
                }
                return .unavailable(issue: issue)
            case .failure:
                if let lastGoodPayload {
                    return .cache(lastGoodPayload, issue: issue)
                }
                return .unavailable(issue: issue)
            }
        }
    }

    private func applyHydration(
        _ result: NewsCacheLoadResult,
        expectedGeneration: Int
    ) -> NewsRepositoryState {
        defer { didHydrate = true }

        // Any completed refresh, successful or not, is newer than the hydration snapshot.
        guard expectedGeneration == stateGeneration else { return state }
        defer { stateGeneration += 1 }

        switch Self.validatedCacheResult(result) {
        case let .hit(payload):
            lastGoodPayload = Self.freshestPayload(lastGoodPayload, payload)
            state = NewsRepositoryState(
                source: .cache,
                payload: lastGoodPayload,
                lastUpdatedAt: lastGoodPayload?.updatedAt,
                nonblockingIssue: nil
            )
        case .miss:
            if let lastGoodPayload {
                state = NewsRepositoryState(
                    source: .cache,
                    payload: lastGoodPayload,
                    lastUpdatedAt: lastGoodPayload.updatedAt,
                    nonblockingIssue: nil
                )
            }
        case .failure:
            if lastGoodPayload == nil {
                state = .unavailable(issue: .cacheRead)
            }
        }
        return state
    }

    private static func validatedCacheResult(
        _ result: NewsCacheLoadResult
    ) -> NewsCacheLoadResult {
        guard case let .hit(payload) = result else { return result }
        do {
            return .hit(try NewsPayloadValidator.validate(payload))
        } catch {
            return .failure
        }
    }

    private static func freshestPayload(
        _ memoryPayload: NewsPayload?,
        _ diskPayload: NewsPayload
    ) -> NewsPayload {
        guard let memoryPayload else { return diskPayload }
        return memoryPayload.updatedAt >= diskPayload.updatedAt ? memoryPayload : diskPayload
    }

    private static func issue(for error: Error) -> NewsRepositoryIssue {
        switch error {
        case let NewsPayloadValidationError.unsupportedSchema(version):
            return .unsupportedSchema(version)
        case NewsPayloadValidationError.invalidPayload:
            return .invalidPayload
        case NewsAPIClientError.invalidResponse:
            return .invalidResponse
        case let NewsAPIClientError.httpStatus(code):
            return .httpStatus(code)
        case NewsAPIClientError.invalidPayload:
            return .invalidPayload
        case let NewsAPIClientError.unsupportedSchema(version):
            return .unsupportedSchema(version)
        default:
            return .transport
        }
    }
}

@MainActor
protocol NewsRepositoryServing: AnyObject {
    var currentState: NewsRepositoryState { get }
    func hydrate() async -> NewsRepositoryState
    func refresh() async -> NewsRepositoryState
}

extension NewsRepository: NewsRepositoryServing {
    var currentState: NewsRepositoryState { state }
}
