import Foundation

struct CountdownState: Equatable, Sendable {
    /// Day component of the precise countdown duration. This may be lower than
    /// `calendarDaysRemaining` after local midnight on a milestone date.
    let preciseDays: Int
    let hours: Int
    let minutes: Int
    let seconds: Int

    /// Difference between the current local date and the local release date.
    /// Use this value for the day headline and milestone copy.
    let calendarDaysRemaining: Int
    let isReleased: Bool

    static let released = CountdownState(
        preciseDays: 0,
        hours: 0,
        minutes: 0,
        seconds: 0,
        calendarDaysRemaining: 0,
        isReleased: true
    )
}
