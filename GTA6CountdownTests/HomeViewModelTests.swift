import Foundation
import XCTest
@testable import GTA6Countdown

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testStartCalibratesImmediatelyAndEveryTickUsesCurrentClock() throws {
        let calendar = testCalendar()
        let release = try date(2026, 11, 19, in: calendar)
        let clock = MutableHomeClock(now: try XCTUnwrap(calendar.date(byAdding: .second, value: -2, to: release)))
        let ticker = ManualCountdownTicker()
        let lifecycle = ManualHomeLifecycle(phase: .active)
        let viewModel = HomeViewModel(clock: clock, ticker: ticker, lifecycle: lifecycle, deviceCalendar: calendar)

        viewModel.start()
        XCTAssertEqual(viewModel.countdown.seconds, 2)
        XCTAssertEqual(ticker.startCount, 1)

        clock.now = try XCTUnwrap(calendar.date(byAdding: .second, value: -1, to: release))
        ticker.tick()
        XCTAssertEqual(viewModel.countdown.seconds, 1)
        XCTAssertEqual(viewModel.currentDate, clock.now)
    }

    func testEnteringBackgroundStopsTickerAndDoesNotAdvanceFromTicks() throws {
        let calendar = testCalendar()
        let clock = MutableHomeClock(now: try date(2026, 11, 18, in: calendar))
        let ticker = ManualCountdownTicker()
        let lifecycle = ManualHomeLifecycle(phase: .active)
        let viewModel = HomeViewModel(clock: clock, ticker: ticker, lifecycle: lifecycle, deviceCalendar: calendar)
        viewModel.start()
        let beforeBackground = viewModel.countdown

        lifecycle.send(.background)
        clock.now = try date(2026, 11, 19, in: calendar)
        ticker.tick()

        XCTAssertEqual(ticker.stopCount, 1)
        XCTAssertEqual(viewModel.countdown, beforeBackground)
    }

    func testReturningToForegroundImmediatelyRebuildsGregorianCalculatorAndRestartsTicker() throws {
        var buddhistDeviceCalendar = Calendar(identifier: .buddhist)
        buddhistDeviceCalendar.locale = Locale(identifier: "th_TH")
        buddhistDeviceCalendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let gregorian = testCalendar(timeZone: "Asia/Bangkok")
        let clock = MutableHomeClock(now: try date(2026, 11, 18, in: gregorian))
        let ticker = ManualCountdownTicker()
        let lifecycle = ManualHomeLifecycle(phase: .active)
        let viewModel = HomeViewModel(
            clock: clock,
            ticker: ticker,
            lifecycle: lifecycle,
            deviceCalendar: buddhistDeviceCalendar
        )
        viewModel.start()
        lifecycle.send(.background)

        clock.now = try date(2026, 11, 19, in: gregorian)
        lifecycle.send(.active)

        XCTAssertTrue(viewModel.countdown.isReleased)
        XCTAssertEqual(ticker.startCount, 2)
        XCTAssertEqual(viewModel.firstConfirmationDate, try date(2022, 2, 4, in: gregorian))
    }

    func testRemoteReleaseDateUpdateRecalculatesWithoutWaitingForTick() throws {
        let calendar = testCalendar()
        let clock = MutableHomeClock(now: try date(2026, 11, 18, in: calendar))
        let viewModel = HomeViewModel(
            clock: clock,
            ticker: ManualCountdownTicker(),
            lifecycle: ManualHomeLifecycle(phase: .active),
            deviceCalendar: calendar
        )
        viewModel.start()
        XCTAssertEqual(viewModel.countdown.calendarDaysRemaining, 1)

        viewModel.updateReleaseDate(DateComponents(year: 2026, month: 11, day: 20))

        XCTAssertEqual(viewModel.countdown.calendarDaysRemaining, 2)
        XCTAssertEqual(viewModel.releaseDate, try date(2026, 11, 20, in: calendar))
    }

    func testReleaseStateUsesApprovedCopyAndZeroValues() throws {
        let calendar = testCalendar()
        let release = try date(2026, 11, 19, in: calendar)
        let viewModel = HomeViewModel(
            clock: MutableHomeClock(now: release),
            ticker: ManualCountdownTicker(),
            lifecycle: ManualHomeLifecycle(phase: .active),
            deviceCalendar: calendar
        )

        viewModel.start()

        XCTAssertEqual(viewModel.countdown, .released)
        XCTAssertEqual(viewModel.milestoneMessage, "等待结束。欢迎来到莱昂尼达。")
    }

    func testStopIsIdempotentAndViewModelCanRestart() throws {
        let calendar = testCalendar()
        let ticker = ManualCountdownTicker()
        let lifecycle = ManualHomeLifecycle(phase: .active)
        let viewModel = HomeViewModel(
            clock: MutableHomeClock(now: try date(2026, 11, 18, in: calendar)),
            ticker: ticker,
            lifecycle: lifecycle,
            deviceCalendar: calendar
        )

        viewModel.start()
        viewModel.stop()
        viewModel.stop()
        viewModel.start()

        XCTAssertEqual(ticker.startCount, 2)
        XCTAssertEqual(ticker.stopCount, 1)
        XCTAssertEqual(lifecycle.startCount, 2)
        XCTAssertEqual(lifecycle.stopCount, 1)
    }

    func testApplyingRemoteConfigUpdatesReleaseDateAndMilestoneCopyImmediately() throws {
        let calendar = testCalendar()
        let viewModel = HomeViewModel(
            clock: MutableHomeClock(now: try date(2026, 11, 18, in: calendar)),
            ticker: ManualCountdownTicker(),
            lifecycle: ManualHomeLifecycle(phase: .active),
            deviceCalendar: calendar
        )
        viewModel.start()
        let config = try JSONDecoder().decode(RemoteConfig.self, from: Data(#"""
        {
          "releaseDate": "2026-11-20",
          "releaseTimeMode": "localMidnight",
          "milestoneMessages": { "2": "两天后，新的莱昂尼达见。" },
          "pinnedOfficialArticleID": null,
          "lastUpdatedAt": "2026-07-20T00:00:00Z",
          "schemaVersion": 1
        }
        """#.utf8))

        viewModel.apply(remoteConfig: config)

        XCTAssertEqual(viewModel.releaseDate, try date(2026, 11, 20, in: calendar))
        XCTAssertEqual(viewModel.countdown.calendarDaysRemaining, 2)
        XCTAssertEqual(viewModel.milestoneMessage, "两天后，新的莱昂尼达见。")
    }

    func testWaitingProgressClampsAndHandlesDegenerateRange() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)

        XCTAssertEqual(ReleaseWaitingProgress.value(from: start, to: end, at: start.addingTimeInterval(-1)), 0)
        XCTAssertEqual(ReleaseWaitingProgress.value(from: start, to: end, at: Date(timeIntervalSince1970: 1_500)), 0.5)
        XCTAssertEqual(ReleaseWaitingProgress.value(from: start, to: end, at: end.addingTimeInterval(1)), 1)
        XCTAssertEqual(ReleaseWaitingProgress.value(from: start, to: start, at: start.addingTimeInterval(-1)), 0)
        XCTAssertEqual(ReleaseWaitingProgress.value(from: start, to: start, at: start), 1)
    }

    private func testCalendar(timeZone: String = "Asia/Shanghai") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZone)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }
}

private final class MutableHomeClock: CountdownClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class ManualCountdownTicker: CountdownTicking {
    private var action: (() -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(_ action: @escaping () -> Void) {
        startCount += 1
        self.action = action
    }

    func stop() {
        stopCount += 1
        action = nil
    }

    func tick() {
        action?()
    }
}

@MainActor
private final class ManualHomeLifecycle: HomeLifecycleObserving {
    private var action: ((HomeLifecyclePhase) -> Void)?
    private(set) var phase: HomeLifecyclePhase
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(phase: HomeLifecyclePhase) {
        self.phase = phase
    }

    func start(_ action: @escaping (HomeLifecyclePhase) -> Void) {
        startCount += 1
        self.action = action
    }

    func stop() {
        stopCount += 1
        action = nil
    }

    func send(_ phase: HomeLifecyclePhase) {
        self.phase = phase
        action?(phase)
    }
}
