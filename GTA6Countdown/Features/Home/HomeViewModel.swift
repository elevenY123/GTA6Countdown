import Combine
import Foundation
import UIKit

@MainActor
protocol CountdownTicking: AnyObject {
    func start(_ action: @escaping () -> Void)
    func stop()
}

@MainActor
final class SystemCountdownTicker: CountdownTicking {
    private var timer: Timer?

    func start(_ action: @escaping () -> Void) {
        stop()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

enum HomeLifecyclePhase: Equatable {
    case active
    case inactive
    case background
}

@MainActor
protocol HomeLifecycleObserving: AnyObject {
    var phase: HomeLifecyclePhase { get }
    func start(_ action: @escaping (HomeLifecyclePhase) -> Void)
    func stop()
}

@MainActor
final class ApplicationHomeLifecycle: HomeLifecycleObserving {
    private var observers: [NSObjectProtocol] = []
    private var action: ((HomeLifecyclePhase) -> Void)?

    var phase: HomeLifecyclePhase {
        switch UIApplication.shared.applicationState {
        case .active: return .active
        case .background: return .background
        case .inactive: return .inactive
        @unknown default: return .inactive
        }
    }

    func start(_ action: @escaping (HomeLifecyclePhase) -> Void) {
        stop()
        self.action = action
        observe(UIApplication.didBecomeActiveNotification, phase: .active)
        observe(UIApplication.willResignActiveNotification, phase: .inactive)
        observe(UIApplication.didEnterBackgroundNotification, phase: .background)
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        action = nil
    }

    private func observe(_ name: Notification.Name, phase: HomeLifecyclePhase) {
        observers.append(NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.action?(phase)
            }
        })
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    /// Rockstar first confirmed active development of the next GTA entry on
    /// 4 February 2022. This anchors waiting time, not development progress.
    static let firstConfirmationComponents = DateComponents(year: 2022, month: 2, day: 4)

    @Published private(set) var countdown: CountdownState
    @Published private(set) var releaseDate: Date
    @Published private(set) var currentDate: Date
    @Published private(set) var firstConfirmationDate: Date

    var milestoneMessage: String {
        let key = countdown.isReleased ? "0" : String(countdown.calendarDaysRemaining)
        return milestoneMessages[key] ?? MilestoneMessage.text(for: countdown)
    }

    private let clock: any CountdownClock
    private let ticker: any CountdownTicking
    private let lifecycle: any HomeLifecycleObserving
    private let deviceCalendar: Calendar
    private var releaseDateComponents: DateComponents
    private var milestoneMessages: [String: String] = [:]
    private var isStarted = false
    private var isTicking = false

    convenience init() {
        self.init(
            clock: SystemCountdownClock(),
            ticker: SystemCountdownTicker(),
            lifecycle: ApplicationHomeLifecycle()
        )
    }

    init(
        clock: any CountdownClock,
        ticker: any CountdownTicking,
        lifecycle: any HomeLifecycleObserving,
        deviceCalendar: Calendar = .autoupdatingCurrent,
        releaseDateComponents: DateComponents = RemoteConfig.defaultReleaseDateComponents
    ) {
        self.clock = clock
        self.ticker = ticker
        self.lifecycle = lifecycle
        self.deviceCalendar = deviceCalendar
        self.releaseDateComponents = releaseDateComponents

        let calculator = CountdownCalculator(
            clock: clock,
            deviceCalendar: deviceCalendar,
            releaseDateComponents: releaseDateComponents
        )
        countdown = calculator.state()
        releaseDate = calculator.releaseDate
        currentDate = clock.now
        firstConfirmationDate = Self.gregorianCalendar(following: deviceCalendar)
            .date(from: Self.firstConfirmationComponents) ?? calculator.releaseDate
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        lifecycle.start { [weak self] phase in
            self?.handleLifecycle(phase)
        }
        handleLifecycle(lifecycle.phase)
    }

    func stop() {
        guard isStarted else { return }
        ticker.stop()
        lifecycle.stop()
        isTicking = false
        isStarted = false
    }

    func updateReleaseDate(_ components: DateComponents) {
        releaseDateComponents = components
        recalibrate()
    }

    func apply(remoteConfig: RemoteConfig) {
        milestoneMessages = remoteConfig.milestoneMessages
        updateReleaseDate(remoteConfig.releaseDateComponents)
    }

    private func handleLifecycle(_ phase: HomeLifecyclePhase) {
        switch phase {
        case .active:
            // Rebuild from the current clock immediately. Timer ticks are not
            // a reliable measure of elapsed time after suspension.
            recalibrate()
            if !isTicking {
                ticker.start { [weak self] in self?.recalibrate() }
                isTicking = true
            }
        case .inactive, .background:
            if isTicking {
                ticker.stop()
                isTicking = false
            }
        }
    }

    private func recalibrate() {
        let now = clock.now
        let currentDeviceCalendar = deviceCalendar
        let calculator = CountdownCalculator(
            clock: FixedCountdownClock(now: now),
            deviceCalendar: currentDeviceCalendar,
            releaseDateComponents: releaseDateComponents
        )
        releaseDate = calculator.releaseDate
        countdown = calculator.state()
        currentDate = now
        firstConfirmationDate = Self.gregorianCalendar(following: currentDeviceCalendar)
            .date(from: Self.firstConfirmationComponents) ?? calculator.releaseDate
    }

    /// Uses the same current device calendar snapshot as the countdown rebuild.
    private static func gregorianCalendar(following deviceCalendar: Calendar) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = deviceCalendar.locale
        calendar.timeZone = deviceCalendar.timeZone
        return calendar
    }
}
