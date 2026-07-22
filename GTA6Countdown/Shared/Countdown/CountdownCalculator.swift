import Foundation

protocol CountdownClock {
    var now: Date { get }
}

struct SystemCountdownClock: CountdownClock {
    var now: Date { Date() }
}

struct FixedCountdownClock: CountdownClock {
    let now: Date
}

struct CountdownCalculator {
    private static let defaultReleaseComponents = DateComponents(
        year: 2026,
        month: 11,
        day: 19,
        hour: 0,
        minute: 0,
        second: 0
    )

    private let calendar: Calendar
    private let clock: any CountdownClock
    private let releaseComponents: DateComponents

    /// Production initializer. The calendar is always Gregorian while its
    /// locale and time zone follow the user's device settings.
    init(
        clock: any CountdownClock = SystemCountdownClock(),
        deviceCalendar: Calendar = .autoupdatingCurrent,
        releaseDateComponents: DateComponents? = nil
    ) {
        self.init(
            calendar: Self.gregorianCalendar(following: deviceCalendar),
            clock: clock,
            releaseDateComponents: releaseDateComponents
        )
    }

    /// Explicit calendar injection for deterministic tests and specialized
    /// calendar calculations.
    init(
        calendar: Calendar,
        clock: any CountdownClock = SystemCountdownClock(),
        releaseDateComponents: DateComponents? = nil
    ) {
        self.calendar = calendar
        self.clock = clock
        self.releaseComponents = releaseDateComponents ?? Self.defaultReleaseComponents
    }

    var releaseDate: Date {
        guard let date = calendar.date(from: releaseComponents) else {
            preconditionFailure("Release date components must form a valid date")
        }
        return date
    }

    func state() -> CountdownState {
        state(at: clock.now)
    }

    func state(at now: Date) -> CountdownState {
        let releaseDate = releaseDate
        guard now < releaseDate else {
            return .released
        }

        let components = calendar.dateComponents(
            [.day, .hour, .minute, .second],
            from: now,
            to: releaseDate
        )
        let calendarDaysRemaining = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: releaseDate)
        ).day ?? 0

        return CountdownState(
            preciseDays: components.day ?? 0,
            hours: components.hour ?? 0,
            minutes: components.minute ?? 0,
            seconds: components.second ?? 0,
            calendarDaysRemaining: max(0, calendarDaysRemaining),
            isReleased: false
        )
    }

    private static func gregorianCalendar(following deviceCalendar: Calendar) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = deviceCalendar.locale
        calendar.timeZone = deviceCalendar.timeZone
        return calendar
    }
}
