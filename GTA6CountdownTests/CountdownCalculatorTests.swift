import Foundation
import XCTest
@testable import GTA6Countdown

final class CountdownCalculatorTests: XCTestCase {
    private let releaseComponents = DateComponents(
        year: 2026,
        month: 11,
        day: 19,
        hour: 0,
        minute: 0,
        second: 0
    )

    func testDefaultReleaseIsMidnightInInjectedDeviceCalendar() throws {
        let shanghai = calendar(timeZoneIdentifier: "Asia/Shanghai")
        let losAngeles = calendar(timeZoneIdentifier: "America/Los_Angeles")

        let shanghaiRelease = try XCTUnwrap(shanghai.date(from: releaseComponents))
        let losAngelesRelease = try XCTUnwrap(losAngeles.date(from: releaseComponents))

        XCTAssertEqual(
            CountdownCalculator(calendar: shanghai, clock: FixedCountdownClock(now: shanghaiRelease))
                .releaseDate,
            shanghaiRelease
        )
        XCTAssertEqual(
            CountdownCalculator(calendar: losAngeles, clock: FixedCountdownClock(now: losAngelesRelease))
                .releaseDate,
            losAngelesRelease
        )
        XCTAssertNotEqual(shanghaiRelease, losAngelesRelease)
    }

    func testProductionCalendarIsGregorianEvenWhenDeviceCalendarIsBuddhist() throws {
        var deviceCalendar = Calendar(identifier: .buddhist)
        deviceCalendar.locale = Locale(identifier: "th_TH")
        deviceCalendar.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        let expectedCalendar = calendar(timeZoneIdentifier: "Asia/Bangkok")
        let expectedRelease = try XCTUnwrap(expectedCalendar.date(from: releaseComponents))

        let calculator = CountdownCalculator(
            clock: FixedCountdownClock(now: expectedRelease),
            deviceCalendar: deviceCalendar
        )

        XCTAssertEqual(calculator.releaseDate, expectedRelease)
        XCTAssertEqual(calculator.state(), .released)
    }

    func testCountdownUsesInjectedClockAndDecomposesRemainingTime() throws {
        let calendar = calendar(timeZoneIdentifier: "Asia/Shanghai")
        let now = try date(2026, 11, 17, 21, 56, 55, in: calendar)
        let calculator = CountdownCalculator(
            calendar: calendar,
            clock: FixedCountdownClock(now: now)
        )

        XCTAssertEqual(
            calculator.state(),
            CountdownState(
                preciseDays: 1,
                hours: 2,
                minutes: 3,
                seconds: 5,
                calendarDaysRemaining: 2,
                isReleased: false
            )
        )
    }

    func testReleaseAndPostReleaseAreClampedToZero() throws {
        let calendar = calendar(timeZoneIdentifier: "Asia/Shanghai")
        let release = try XCTUnwrap(calendar.date(from: releaseComponents))
        let afterRelease = try XCTUnwrap(calendar.date(byAdding: .second, value: 1, to: release))

        for now in [release, afterRelease] {
            let state = CountdownCalculator(
                calendar: calendar,
                clock: FixedCountdownClock(now: now)
            ).state()

            XCTAssertEqual(state, .released)
            XCTAssertTrue(state.isReleased)
        }
    }

    func testCalendarDayCalculationSurvivesDaylightSavingBoundary() throws {
        let calendar = calendar(timeZoneIdentifier: "America/Los_Angeles")
        let now = try date(2026, 10, 31, 0, 0, 0, in: calendar)
        let release = try XCTUnwrap(calendar.date(from: releaseComponents))
        let elapsedHours = release.timeIntervalSince(now) / 3_600

        XCTAssertEqual(elapsedHours, 457, accuracy: 0.001)
        XCTAssertEqual(
            CountdownCalculator(calendar: calendar, clock: FixedCountdownClock(now: now)).state(),
            CountdownState(
                preciseDays: 19,
                hours: 0,
                minutes: 0,
                seconds: 0,
                calendarDaysRemaining: 19,
                isReleased: false
            )
        )
    }

    func testMilestonesRemainActiveThroughoutTheirLocalCalendarDay() throws {
        let calendar = calendar(timeZoneIdentifier: "Asia/Shanghai")
        let release = try XCTUnwrap(calendar.date(from: releaseComponents))
        let milestoneDays = [100, 7, 1]

        for days in milestoneDays {
            let milestoneStart = try XCTUnwrap(calendar.date(byAdding: .day, value: -days, to: release))
            let midday = try XCTUnwrap(calendar.date(byAdding: .hour, value: 12, to: milestoneStart))
            let nearMidnight = try XCTUnwrap(calendar.date(byAdding: DateComponents(
                hour: 23,
                minute: 59,
                second: 59
            ), to: milestoneStart))

            let moments: [(Date, Int, Int, Int)] = [
                (midday, days - 1, 12, 0),
                (nearMidnight, days - 1, 0, 1)
            ]

            for (now, preciseDays, hours, seconds) in moments {
                let state = CountdownCalculator(
                    calendar: calendar,
                    clock: FixedCountdownClock(now: now)
                ).state()

                XCTAssertEqual(state.preciseDays, preciseDays)
                XCTAssertEqual(state.hours, hours)
                XCTAssertEqual(state.minutes, 0)
                XCTAssertEqual(state.seconds, seconds)
                XCTAssertEqual(state.calendarDaysRemaining, days)
                XCTAssertEqual(
                    MilestoneMessage.text(for: state),
                    expectedMessage(for: days)
                )
            }
        }
    }

    func testPreciseComponentsAndNaturalDayCountStayDistinctAtReleaseBoundary() throws {
        let calendar = calendar(timeZoneIdentifier: "Asia/Shanghai")
        let release = try XCTUnwrap(calendar.date(from: releaseComponents))
        let oneSecondBefore = try XCTUnwrap(calendar.date(byAdding: .second, value: -1, to: release))
        let beforeState = CountdownCalculator(
            calendar: calendar,
            clock: FixedCountdownClock(now: oneSecondBefore)
        ).state()

        XCTAssertEqual(beforeState.preciseDays, 0)
        XCTAssertEqual(beforeState.hours, 0)
        XCTAssertEqual(beforeState.minutes, 0)
        XCTAssertEqual(beforeState.seconds, 1)
        XCTAssertEqual(beforeState.calendarDaysRemaining, 1)
        XCTAssertEqual(MilestoneMessage.text(for: beforeState), "明天。今晚大概睡不着了。")

        let releaseState = CountdownCalculator(
            calendar: calendar,
            clock: FixedCountdownClock(now: release)
        ).state()
        XCTAssertEqual(releaseState, .released)
        XCTAssertEqual(releaseState.calendarDaysRemaining, 0)
        XCTAssertEqual(MilestoneMessage.text(for: releaseState), "等待结束。欢迎来到莱昂尼达。")
    }

    func testEveryApprovedMilestoneMessage() throws {
        let calendar = calendar(timeZoneIdentifier: "Asia/Shanghai")
        let release = try XCTUnwrap(calendar.date(from: releaseComponents))
        let expected: [(Int, String)] = [
            (100, "最后一百天，正式开始。"),
            (50, "五十天后，阳光之州见。"),
            (20, "漫长等待，只剩二十天。"),
            (10, "两只手，已经数得过来了。"),
            (7, "最后一周，准备前往罪恶城。"),
            (6, "数字终于对上了：VI 天。"),
            (5, "等了这么多年，只剩五天。"),
            (4, "四天后，莱昂尼达见。"),
            (3, "三天。真的快了。"),
            (2, "后天，杰森与露西亚登场。"),
            (1, "明天。今晚大概睡不着了。")
        ]

        for (days, message) in expected {
            let now = try XCTUnwrap(calendar.date(byAdding: .day, value: -days, to: release))
            let state = CountdownCalculator(
                calendar: calendar,
                clock: FixedCountdownClock(now: now)
            ).state()
            XCTAssertEqual(state.preciseDays, days)
            XCTAssertEqual(state.calendarDaysRemaining, days)
            XCTAssertEqual(MilestoneMessage.text(for: state), message)
        }

        XCTAssertEqual(MilestoneMessage.text(for: .released), "等待结束。欢迎来到莱昂尼达。")
    }

    func testNonMilestoneUsesDefaultMessage() {
        let state = CountdownState(
            preciseDays: 42,
            hours: 0,
            minutes: 0,
            seconds: 0,
            calendarDaysRemaining: 42,
            isReleased: false
        )
        XCTAssertEqual(MilestoneMessage.text(for: state), "快了，快了。罪恶城正在靠近。")
    }

    private func expectedMessage(for days: Int) -> String {
        switch days {
        case 100: return "最后一百天，正式开始。"
        case 7: return "最后一周，准备前往罪恶城。"
        case 1: return "明天。今晚大概睡不着了。"
        default: return ""
        }
    }

    private func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int,
        in calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )))
    }
}
