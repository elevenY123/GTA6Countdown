import Foundation
import XCTest
@testable import GTA6Countdown

@MainActor
final class MapNavigationTests: XCTestCase {
    func testInitialURLIsExactSecureMyGTACommunityMap() {
        XCTAssertEqual(
            MapNavigationPolicy.initialURL.absoluteString,
            "https://map.mygta.online/gta6-map"
        )
        XCTAssertEqual(MapNavigationPolicy.initialURL.scheme, "https")
    }

    func testSecureSameSiteNavigationStaysInsideWebView() {
        let policy = MapNavigationPolicy()

        XCTAssertEqual(policy.decision(for: MapNavigationPolicy.initialURL), .allow)
        XCTAssertEqual(
            policy.decision(for: URL(string: "https://map.mygta.online/gta6-map?layer=roads#vice-city")!),
            .allow
        )
        XCTAssertEqual(
            policy.decision(for: URL(string: "https://map.mygta.online:443/gta6-map")!),
            .allow
        )
    }

    func testExternalHTTPSOpensOutsideAndInsecureOrCustomSchemesAreCancelled() {
        let policy = MapNavigationPolicy()
        let external = URL(string: "https://mygta.online/about")!

        XCTAssertEqual(policy.decision(for: external), .openExternally(external))
        XCTAssertEqual(
            policy.decision(for: URL(string: "http://map.mygta.online/gta6-map")!),
            .cancel
        )
        XCTAssertEqual(policy.decision(for: URL(string: "javascript:alert(1)")!), .cancel)
        XCTAssertEqual(policy.decision(for: URL(string: "mygta://map")!), .cancel)
    }

    func testSubdomainsAndNonDefaultPortsNeverLoadInsideWebView() {
        let policy = MapNavigationPolicy()
        let subdomain = URL(string: "https://cdn.map.mygta.online/gta6-map")!
        let alternatePort = URL(string: "https://map.mygta.online:8443/gta6-map")!

        XCTAssertEqual(policy.decision(for: subdomain), .openExternally(subdomain))
        XCTAssertEqual(policy.decision(for: alternatePort), .openExternally(alternatePort))
    }

    func testLoadingAndFailureStateCanRetryExactInitialURL() {
        let opener = MapExternalOpenerSpy()
        let controller = MapWebControllerSpy()
        let viewModel = MapViewModel(opener: opener)
        viewModel.attach(controller: controller)

        viewModel.didStartLoading()
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)

        viewModel.didFailLoading(description: "网络连接已中断")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, "网络连接已中断")

        viewModel.retry()
        XCTAssertEqual(controller.loadedURLs, [MapNavigationPolicy.initialURL])
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testBackForwardRefreshAndBrowserFallbackUseInjectedDependencies() {
        let opener = MapExternalOpenerSpy()
        let controller = MapWebControllerSpy()
        controller.canGoBackValue = true
        controller.canGoForwardValue = true
        let viewModel = MapViewModel(opener: opener)
        viewModel.attach(controller: controller)
        viewModel.updateNavigationAvailability()

        XCTAssertTrue(viewModel.canGoBack)
        XCTAssertTrue(viewModel.canGoForward)
        viewModel.goBack()
        viewModel.goForward()
        viewModel.refresh()
        viewModel.openInSafari()

        XCTAssertEqual(controller.goBackCount, 1)
        XCTAssertEqual(controller.goForwardCount, 1)
        XCTAssertEqual(controller.reloadCount, 1)
        XCTAssertEqual(opener.openedURLs, [MapNavigationPolicy.initialURL])
    }

    func testBrowserFallbackUsesCurrentCommittedInternalURL() {
        let opener = MapExternalOpenerSpy()
        let viewModel = MapViewModel(opener: opener)
        let current = URL(string: "https://map.mygta.online/gta6-map?layer=landmarks#port-gellhorn")!

        viewModel.didCommitNavigation(to: current)
        viewModel.didCommitNavigation(to: URL(string: "https://example.com/not-internal")!)
        viewModel.openInSafari()

        XCTAssertEqual(opener.openedURLs, [current])
    }

    func testExternalNavigationUsesInjectedOpenerAndNeverLoadsInWebView() {
        let opener = MapExternalOpenerSpy()
        let viewModel = MapViewModel(opener: opener)
        let external = URL(string: "https://example.com/story")!

        XCTAssertEqual(viewModel.handleNavigation(to: external), .cancel)
        XCTAssertEqual(opener.openedURLs, [external])
    }

    func testObservedWebHistoryStateIsPublishedWithoutWaitingForPageFinish() {
        let viewModel = MapViewModel(opener: MapExternalOpenerSpy())

        viewModel.didObserveNavigationState(canGoBack: true, canGoForward: false)
        XCTAssertTrue(viewModel.canGoBack)
        XCTAssertFalse(viewModel.canGoForward)

        viewModel.didObserveNavigationState(canGoBack: false, canGoForward: true)
        XCTAssertFalse(viewModel.canGoBack)
        XCTAssertTrue(viewModel.canGoForward)
    }

    func testWebContentProcessTerminationShowsRecoverableRetryState() {
        let controller = MapWebControllerSpy()
        let viewModel = MapViewModel(opener: MapExternalOpenerSpy())
        viewModel.attach(controller: controller)

        viewModel.webContentProcessDidTerminate()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
        viewModel.retry()
        XCTAssertEqual(controller.loadedURLs, [MapNavigationPolicy.initialURL])
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testViewModelUsesInjectedNavigationPolicy() {
        let opener = MapExternalOpenerSpy()
        let policy = MapNavigationPolicyStub(decision: .cancel)
        let viewModel = MapViewModel(policy: policy, opener: opener)

        XCTAssertEqual(viewModel.handleNavigation(to: MapNavigationPolicy.initialURL), .cancel)
        XCTAssertTrue(opener.openedURLs.isEmpty)
        XCTAssertEqual(policy.receivedURLs, [MapNavigationPolicy.initialURL])
    }
}

private final class MapNavigationPolicyStub: MapNavigationDeciding {
    let decision: MapNavigationDecision
    private(set) var receivedURLs: [URL] = []

    init(decision: MapNavigationDecision) {
        self.decision = decision
    }

    func decision(for url: URL) -> MapNavigationDecision {
        receivedURLs.append(url)
        return decision
    }
}

@MainActor
private final class MapExternalOpenerSpy: MapExternalOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) {
        openedURLs.append(url)
    }
}

@MainActor
private final class MapWebControllerSpy: MapWebControlling {
    var canGoBackValue = false
    var canGoForwardValue = false
    private(set) var loadedURLs: [URL] = []
    private(set) var goBackCount = 0
    private(set) var goForwardCount = 0
    private(set) var reloadCount = 0

    var canGoBack: Bool { canGoBackValue }
    var canGoForward: Bool { canGoForwardValue }

    func load(_ url: URL) { loadedURLs.append(url) }
    func goBack() { goBackCount += 1 }
    func goForward() { goForwardCount += 1 }
    func reload() { reloadCount += 1 }
}
