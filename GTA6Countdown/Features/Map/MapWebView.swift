import SwiftUI
import WebKit

struct MapWebView: UIViewRepresentable {
    @ObservedObject var viewModel: MapViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        viewModel.attach(controller: webView)
        context.coordinator.startObservingNavigationState(of: webView)
        webView.load(viewModel.initialURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObservingNavigationState()
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let viewModel: MapViewModel
        private var navigationObservations: [NSKeyValueObservation] = []

        init(viewModel: MapViewModel) {
            self.viewModel = viewModel
        }

        func startObservingNavigationState(of webView: WKWebView) {
            stopObservingNavigationState()
            navigationObservations = [
                webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                    Task { @MainActor [weak self, weak webView] in
                        guard let self, let webView else { return }
                        self.publishNavigationState(from: webView)
                    }
                },
                webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                    Task { @MainActor [weak self, weak webView] in
                        guard let self, let webView else { return }
                        self.publishNavigationState(from: webView)
                    }
                }
            ]
        }

        func stopObservingNavigationState() {
            navigationObservations.forEach { $0.invalidate() }
            navigationObservations.removeAll()
        }

        deinit {
            navigationObservations.forEach { $0.invalidate() }
        }

        private func publishNavigationState(from webView: WKWebView) {
            viewModel.didObserveNavigationState(
                canGoBack: webView.canGoBack,
                canGoForward: webView.canGoForward
            )
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            switch viewModel.handleNavigation(to: url) {
            case .allow:
                if navigationAction.targetFrame == nil {
                    webView.load(navigationAction.request)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
            case .openExternally, .cancel:
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            viewModel.didStartLoading()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            viewModel.didFinishLoading()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
            guard let url = webView.url else { return }
            viewModel.didCommitNavigation(to: url)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            viewModel.webContentProcessDidTerminate()
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: Error
        ) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: Error
        ) {
            report(error)
        }

        private func report(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            viewModel.didFailLoading(description: "地图加载失败，请检查网络后重试。")
        }
    }
}

@MainActor
extension WKWebView: MapWebControlling {
    func load(_ url: URL) {
        load(URLRequest(url: url))
    }

    func navigateBack() {
        goBack()
    }

    func navigateForward() {
        goForward()
    }

    func reloadContent() {
        reload()
    }
}
