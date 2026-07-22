import Combine
import Foundation
import UIKit

enum MapNavigationDecision: Equatable {
    case allow
    case openExternally(URL)
    case cancel
}

protocol MapNavigationDeciding {
    func decision(for url: URL) -> MapNavigationDecision
}

struct MapNavigationPolicy: MapNavigationDeciding {
    static let initialURL = URL(string: "https://map.mygta.online/gta6-map")!

    func decision(for url: URL) -> MapNavigationDecision {
        guard url.scheme?.lowercased() == "https" else { return .cancel }
        guard url.host?.lowercased() == Self.initialURL.host else {
            return .openExternally(url)
        }
        guard url.port == nil || url.port == 443 else {
            return .openExternally(url)
        }
        return .allow
    }
}

@MainActor
protocol MapExternalOpening: AnyObject {
    func open(_ url: URL)
}

@MainActor
final class SystemMapExternalOpener: MapExternalOpening {
    func open(_ url: URL) {
        UIApplication.shared.open(url, options: [:])
    }
}

@MainActor
protocol MapWebControlling: AnyObject {
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }
    func load(_ url: URL)
    func navigateBack()
    func navigateForward()
    func reloadContent()
}

@MainActor
final class MapViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    private(set) var currentURL: URL?

    let initialURL: URL

    private let policy: MapNavigationDeciding
    private let opener: MapExternalOpening
    private weak var controller: MapWebControlling?

    convenience init() {
        self.init(opener: SystemMapExternalOpener())
    }

    init(
        policy: MapNavigationDeciding = MapNavigationPolicy(),
        opener: MapExternalOpening
    ) {
        self.policy = policy
        self.opener = opener
        initialURL = MapNavigationPolicy.initialURL
    }

    func attach(controller: MapWebControlling) {
        self.controller = controller
        updateNavigationAvailability()
    }

    func handleNavigation(to url: URL) -> MapNavigationDecision {
        switch policy.decision(for: url) {
        case .allow:
            return .allow
        case let .openExternally(externalURL):
            opener.open(externalURL)
            return .cancel
        case .cancel:
            return .cancel
        }
    }

    func didStartLoading() {
        isLoading = true
        errorMessage = nil
    }

    func didFinishLoading() {
        isLoading = false
        errorMessage = nil
        updateNavigationAvailability()
    }

    func didCommitNavigation(to url: URL) {
        guard policy.decision(for: url) == .allow else { return }
        currentURL = url
    }

    func didObserveNavigationState(canGoBack: Bool, canGoForward: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }

    func webContentProcessDidTerminate() {
        didFailLoading(description: "地图页面意外停止运行，请重新加载。")
    }

    func didFailLoading(description: String) {
        isLoading = false
        errorMessage = description
        updateNavigationAvailability()
    }

    func updateNavigationAvailability() {
        canGoBack = controller?.canGoBack ?? false
        canGoForward = controller?.canGoForward ?? false
    }

    func goBack() {
        guard canGoBack else { return }
        controller?.navigateBack()
    }

    func goForward() {
        guard canGoForward else { return }
        controller?.navigateForward()
    }

    func refresh() {
        errorMessage = nil
        isLoading = true
        controller?.reloadContent()
    }

    func retry() {
        errorMessage = nil
        isLoading = true
        controller?.load(initialURL)
    }

    func openInSafari() {
        opener.open(currentURL ?? initialURL)
    }
}
