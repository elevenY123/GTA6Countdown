import Foundation

final class URLProtocolStub: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    private static var _handler: Handler?
    private static var _requestCount = 0
    private static var _activeRequestCount = 0
    private static var _maximumActiveRequestCount = 0
    private static var _generation = 0
    private static var _delay: TimeInterval = 0

    static var requestCount: Int {
        lock.withLock { _requestCount }
    }

    static var maximumActiveRequestCount: Int {
        lock.withLock { _maximumActiveRequestCount }
    }

    static func install(delay: TimeInterval = 0, handler: @escaping Handler) {
        lock.withLock {
            _generation += 1
            _handler = handler
            _requestCount = 0
            _activeRequestCount = 0
            _maximumActiveRequestCount = 0
            _delay = delay
        }
    }

    static func reset() {
        lock.withLock {
            _generation += 1
            _handler = nil
            _requestCount = 0
            _activeRequestCount = 0
            _maximumActiveRequestCount = 0
            _delay = 0
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let settings: (Handler?, TimeInterval, Int) = Self.lock.withLock {
            Self._requestCount += 1
            Self._activeRequestCount += 1
            Self._maximumActiveRequestCount = max(
                Self._maximumActiveRequestCount,
                Self._activeRequestCount
            )
            return (Self._handler, Self._delay, Self._generation)
        }

        let deliver = { [weak self] in
            guard let self else { return }
            defer {
                Self.lock.withLock {
                    if Self._generation == settings.2 {
                        Self._activeRequestCount -= 1
                    }
                }
            }
            do {
                guard let handler = settings.0 else { throw URLError(.badServerResponse) }
                let (response, data) = try handler(self.request)
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
                self.client?.urlProtocolDidFinishLoading(self)
            } catch {
                self.client?.urlProtocol(self, didFailWithError: error)
            }
        }

        if settings.1 > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + settings.1, execute: deliver)
        } else {
            deliver()
        }
    }

    override func stopLoading() {}
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
