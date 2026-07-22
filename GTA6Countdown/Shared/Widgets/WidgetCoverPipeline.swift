import CryptoKit
import Foundation
import ImageIO

enum WidgetCoverLimits {
    static let maximumSourceResponseSize = 4 * 1_024 * 1_024
    static let maximumEntryImageSize = 512 * 1_024
    static let maximumPixelSize = 640
}

enum WidgetImageResponseError: Error, Equatable, Sendable {
    case invalidResponse
    case invalidStatus
    case invalidMIMEType
    case responseTooLarge
    case transport
}

enum WidgetImageResponseValidator {
    private static let allowedMIMETypes: Set<String> = [
        "image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"
    ]

    static func validate(
        _ response: HTTPURLResponse,
        fileSize: Int,
        maximumSize: Int
    ) throws {
        try validateHeaders(response, maximumSize: maximumSize)
        guard fileSize > 0, fileSize <= maximumSize else {
            throw WidgetImageResponseError.responseTooLarge
        }
    }

    static func validateHeaders(
        _ response: HTTPURLResponse,
        maximumSize: Int
    ) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw WidgetImageResponseError.invalidStatus
        }
        guard
            let mimeType = response.mimeType?.lowercased(),
            allowedMIMETypes.contains(mimeType)
        else {
            throw WidgetImageResponseError.invalidMIMEType
        }
        let declaredLength = response.expectedContentLength
        guard declaredLength <= 0 || declaredLength <= Int64(maximumSize) else {
            throw WidgetImageResponseError.responseTooLarge
        }
    }
}

struct WidgetCoverPipeline: Sendable {
    typealias Fetch = @Sendable (NewsArticle) async -> Data?
    typealias Sleep = @Sendable (UInt64) async -> Void

    private enum LoadEvent: Sendable {
        case loaded(String, Data?)
        case deadline
    }

    private let maximumConcurrentLoads: Int
    private let maximumItemSize: Int
    private let deadlineNanoseconds: UInt64
    private let fetch: Fetch
    private let sleep: Sleep

    init(
        maximumConcurrentLoads: Int = 2,
        maximumItemSize: Int = WidgetCoverLimits.maximumEntryImageSize,
        deadlineNanoseconds: UInt64 = 4_000_000_000,
        sleep: @escaping Sleep = { nanoseconds in
            try? await Task.sleep(nanoseconds: nanoseconds)
        },
        fetch: @escaping Fetch
    ) {
        self.maximumConcurrentLoads = max(1, maximumConcurrentLoads)
        self.maximumItemSize = max(1, maximumItemSize)
        self.deadlineNanoseconds = deadlineNanoseconds
        self.fetch = fetch
        self.sleep = sleep
    }

    func load(for articles: [NewsArticle], maximumCount: Int) async -> [String: Data] {
        let candidates = Array(articles.prefix(max(0, maximumCount)))
        guard !candidates.isEmpty, !Task.isCancelled else { return [:] }

        return await withTaskGroup(of: LoadEvent.self) { group in
            var result: [String: Data] = [:]
            var nextIndex = 0
            var completedLoads = 0
            let initialCount = min(maximumConcurrentLoads, candidates.count)

            for _ in 0..<initialCount {
                let article = candidates[nextIndex]
                nextIndex += 1
                group.addTask { .loaded(article.id, await fetch(article)) }
            }

            group.addTask {
                await sleep(deadlineNanoseconds)
                return .deadline
            }

            eventLoop: while let event = await group.next() {
                switch event {
                case let .loaded(identifier, data):
                    completedLoads += 1
                    if let data, data.count <= maximumItemSize {
                        result[identifier] = data
                    }
                    if nextIndex < candidates.count {
                        let article = candidates[nextIndex]
                        nextIndex += 1
                        group.addTask { .loaded(article.id, await fetch(article)) }
                    } else if completedLoads == candidates.count {
                        group.cancelAll()
                        break eventLoop
                    }
                case .deadline:
                    group.cancelAll()
                    break eventLoop
                }
            }
            return result
        }
    }
}

actor WidgetCoverStore {
    private let directoryURL: URL
    private let maximumItemSize: Int
    private let maximumDiskSize: Int
    private let fileManager: FileManager
    private let maximumAge: TimeInterval
    private let now: @Sendable () -> Date

    init(
        directoryURL: URL? = nil,
        maximumItemSize: Int = WidgetCoverLimits.maximumEntryImageSize,
        maximumDiskSize: Int = 8 * 1_024 * 1_024,
        maximumAge: TimeInterval = 24 * 60 * 60,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        self.directoryURL = directoryURL
            ?? applicationSupport.appendingPathComponent("GTA6WidgetCovers", isDirectory: true)
        self.maximumItemSize = maximumItemSize
        self.maximumDiskSize = maximumDiskSize
        self.fileManager = fileManager
        self.maximumAge = maximumAge
        self.now = now
    }

    func data(for url: URL) -> Data? {
        let fileURL = cachedFileURL(for: url)
        let currentDate = now()
        guard
            let values = try? fileURL.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey
            ]),
            let size = values.fileSize,
            size > 0,
            size <= maximumItemSize,
            let modificationDate = values.contentModificationDate,
            currentDate.timeIntervalSince(modificationDate) >= -5 * 60,
            currentDate.timeIntervalSince(modificationDate) <= maximumAge,
            let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
            WidgetImageDownsampler.isDecodable(data)
        else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        return data
    }

    func save(_ data: Data, for url: URL) {
        guard data.count <= maximumItemSize else { return }
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(to: cachedFileURL(for: url), options: .atomic)
            trimIfNeeded()
        } catch {
            // Cover failures must never prevent a text-only widget timeline.
        }
    }

    private func cachedFileURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appendingPathComponent(digest).appendingPathExtension("cover")
    }

    private func trimIfNeeded() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).filter({ $0.pathExtension == "cover" }) else { return }

        var entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        while total > maximumDiskSize, !entries.isEmpty {
            let oldest = entries.removeFirst()
            try? fileManager.removeItem(at: oldest.0)
            total -= oldest.1
        }
    }
}

protocol WidgetImageTransporting: Sendable {
    func data(from url: URL, maximumSize: Int) async throws -> (Data, HTTPURLResponse)
}

struct WidgetBoundedImageTransport: WidgetImageTransporting, @unchecked Sendable {
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration) {
        self.configuration = configuration
    }

    func data(from url: URL, maximumSize: Int) async throws -> (Data, HTTPURLResponse) {
        guard maximumSize > 0 else { throw WidgetImageResponseError.responseTooLarge }
        let request = WidgetBoundedRequestDelegate(
            configuration: configuration,
            url: url,
            maximumSize: maximumSize
        )
        return try await request.load()
    }
}

private final class WidgetBoundedRequestDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private let url: URL
    private let maximumSize: Int
    private let lock = NSLock()
    private var buffer = Data()
    private var response: HTTPURLResponse?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var isFinished = false
    private var cancellationRequested = false

    init(configuration: URLSessionConfiguration, url: URL, maximumSize: Int) {
        self.configuration = configuration
        self.url = url
        self.maximumSize = maximumSize
    }

    func load() async throws -> (Data, HTTPURLResponse) {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                start(continuation: continuation)
            }
        }, onCancel: {
            cancel()
        })
    }

    private func start(
        continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>
    ) {
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        let task = session.dataTask(with: url)

        lock.lock()
        self.continuation = continuation
        self.session = session
        self.task = task
        let shouldCancel = cancellationRequested
        lock.unlock()
        if shouldCancel {
            finish(.failure(CancellationError()), cancelTask: true)
        } else {
            task.resume()
        }
    }

    private func cancel() {
        lock.lock()
        cancellationRequested = true
        let hasStarted = continuation != nil
        lock.unlock()
        if hasStarted {
            finish(.failure(CancellationError()), cancelTask: true)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let httpResponse = response as? HTTPURLResponse else {
            finish(.failure(WidgetImageResponseError.invalidResponse), cancelTask: true)
            completionHandler(.cancel)
            return
        }
        do {
            try WidgetImageResponseValidator.validateHeaders(
                httpResponse,
                maximumSize: maximumSize
            )
            lock.lock()
            guard !isFinished else {
                lock.unlock()
                completionHandler(.cancel)
                return
            }
            self.response = httpResponse
            lock.unlock()
            completionHandler(.allow)
        } catch {
            finish(.failure(error), cancelTask: true)
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        let wouldOverflow = data.count > maximumSize - buffer.count
        if !wouldOverflow { buffer.append(data) }
        lock.unlock()

        if wouldOverflow {
            finish(.failure(WidgetImageResponseError.responseTooLarge), cancelTask: true)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if error != nil {
            finish(.failure(WidgetImageResponseError.transport), cancelTask: false)
            return
        }
        lock.lock()
        let response = self.response
        let data = buffer
        lock.unlock()
        guard let response else {
            finish(.failure(WidgetImageResponseError.invalidResponse), cancelTask: false)
            return
        }
        finish(.success((data, response)), cancelTask: false)
    }

    private func finish(
        _ result: Result<(Data, HTTPURLResponse), Error>,
        cancelTask: Bool
    ) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = self.continuation
        self.continuation = nil
        let task = self.task
        self.task = nil
        let session = self.session
        self.session = nil
        lock.unlock()

        if cancelTask { task?.cancel() }
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
}

struct WidgetCoverDownloader: Sendable {
    private let transport: any WidgetImageTransporting
    private let store: WidgetCoverStore

    init(
        transport: any WidgetImageTransporting,
        store: WidgetCoverStore = WidgetCoverStore()
    ) {
        self.transport = transport
        self.store = store
    }

    func data(for article: NewsArticle) async -> Data? {
        guard let url = article.imageURL, !Task.isCancelled else { return nil }
        if let cached = await store.data(for: url) {
            return Task.isCancelled ? nil : cached
        }

        do {
            let (sourceData, _) = try await transport.data(
                from: url,
                maximumSize: WidgetCoverLimits.maximumSourceResponseSize
            )
            try Task.checkCancellation()
            guard
                let displayData = WidgetImageDownsampler.displayData(from: sourceData),
                displayData.count <= WidgetCoverLimits.maximumEntryImageSize,
                !Task.isCancelled
            else { return nil }
            await store.save(displayData, for: url)
            return displayData
        } catch {
            return nil
        }
    }
}

enum WidgetImageDownsampler {
    static func isDecodable(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 8,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil
    }

    static func displayData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: WidgetCoverLimits.maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
