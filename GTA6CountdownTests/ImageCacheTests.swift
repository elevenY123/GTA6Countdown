import Foundation
import XCTest
@testable import GTA6Countdown

final class ImageCacheTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageCacheTests-\(UUID().uuidString)", isDirectory: true)
        URLProtocolStub.reset()
    }

    override func tearDownWithError() throws {
        URLProtocolStub.reset()
        if let rootURL { try? FileManager.default.removeItem(at: rootURL) }
    }

    func testRejectsSuccessfulHTMLResponseAndDoesNotCacheIt() async throws {
        URLProtocolStub.install { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/html"]
            ))
            return (response, Data("<html>error</html>".utf8))
        }
        let cache = try ImageCache(session: makeSession(), directoryURL: rootURL, maximumDiskSize: 1_024)

        let result = await cache.data(for: URL(string: "https://images.example.com/cover.jpg")!)

        XCTAssertNil(result)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: ownedDirectory.path), [])
    }

    func testHTTPFailureReturnsNil() async throws {
        URLProtocolStub.install { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 500,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, Self.pngBytes(suffix: [9]))
        }
        let cache = try ImageCache(session: makeSession(), directoryURL: rootURL, maximumDiskSize: 1_024)

        let result = await cache.data(for: URL(string: "https://images.example.com/error.png")!)

        XCTAssertNil(result)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: ownedDirectory.path), [])
    }

    func testConcurrentDownloadsAreCoalescedAndThenReadFromDisk() async throws {
        let image = Self.pngBytes(suffix: [1, 2, 3])
        URLProtocolStub.install(delay: 0.1) { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, image)
        }
        let cache = try ImageCache(session: makeSession(), directoryURL: rootURL, maximumDiskSize: 1_024)
        let url = URL(string: "https://images.example.com/cover.png?size=2x")!

        async let first = cache.data(for: url)
        async let second = cache.data(for: url)
        let firstResult = await first
        let secondResult = await second
        let diskResult = await cache.data(for: url)
        XCTAssertEqual(firstResult, image)
        XCTAssertEqual(secondResult, image)
        XCTAssertEqual(diskResult, image)
        XCTAssertEqual(URLProtocolStub.requestCount, 1)
        let filenames = try FileManager.default.contentsOfDirectory(atPath: ownedDirectory.path)
        XCTAssertEqual(filenames.count, 1)
        XCTAssertFalse(filenames[0].contains("cover"))
        XCTAssertFalse(filenames[0].contains("?"))
    }

    func testEvictsLeastRecentlyUsedFilesToStayWithinDiskBound() async throws {
        let first = Self.pngBytes(suffix: Array(repeating: 1, count: 30))
        let second = Self.pngBytes(suffix: Array(repeating: 2, count: 30))
        URLProtocolStub.install { request in
            let data = request.url?.lastPathComponent == "one.png" ? first : second
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, data)
        }
        let cache = try ImageCache(
            session: makeSession(),
            directoryURL: rootURL,
            maximumDiskSize: first.count + 5
        )

        _ = await cache.data(for: URL(string: "https://images.example.com/one.png")!)
        _ = await cache.data(for: URL(string: "https://images.example.com/two.png")!)

        let files = try FileManager.default.contentsOfDirectory(
            at: ownedDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )
        let size = try files.reduce(0) { partial, url in
            partial + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        XCTAssertLessThanOrEqual(size, first.count + 5)
        XCTAssertEqual(files.count, 1)
    }

    func testOwnsSubdirectoryAndNeverEvictsUnrelatedFiles() async throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let sentinel = rootURL.appendingPathComponent("keep-me.txt")
        try Data("unrelated".utf8).write(to: sentinel)
        let image = Self.pngBytes(suffix: Array(repeating: 1, count: 30))
        URLProtocolStub.install { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, image)
        }
        let cache = try ImageCache(
            session: makeSession(),
            directoryURL: rootURL,
            maximumDiskSize: image.count
        )
        let internalSentinel = ownedDirectory.appendingPathComponent("unrelated.data")
        try Data(repeating: 3, count: image.count * 2).write(to: internalSentinel)

        _ = await cache.data(for: URL(string: "https://images.example.com/owned.png")!)

        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: internalSentinel.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownedDirectory.path))
    }

    func testStartupRemovesOversizedOwnedHitAndStaleTempWithoutReadingIt() async throws {
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: true)
        let oversizedURL = ownedDirectory.appendingPathComponent(String(repeating: "a", count: 64) + ".image")
        let staleTemp = ownedDirectory.appendingPathComponent(".download-stale.tmp")
        try Data(repeating: 7, count: 200).write(to: oversizedURL)
        try Data("temp".utf8).write(to: staleTemp)
        URLProtocolStub.install { _ in throw URLError(.notConnectedToInternet) }
        let cache = try ImageCache(
            session: makeSession(),
            directoryURL: rootURL,
            maximumDiskSize: 100,
            maximumResponseSize: 80
        )

        await cache.waitForMaintenance()

        _ = await cache.data(for: URL(string: "https://images.example.com/missing.png")!)

        XCTAssertFalse(FileManager.default.fileExists(atPath: oversizedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleTemp.path))
    }

    func testResponseLargerThanMemoryBoundIsRejected() async throws {
        let oversized = Self.pngBytes(suffix: Array(repeating: 8, count: 100))
        URLProtocolStub.install { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, oversized)
        }
        let cache = try ImageCache(
            session: makeSession(),
            directoryURL: rootURL,
            maximumDiskSize: 1_024,
            maximumResponseSize: 50
        )

        let result = await cache.data(for: URL(string: "https://images.example.com/huge.png")!)

        XCTAssertNil(result)
    }

    func testDistinctDownloadsRespectMaximumConcurrency() async throws {
        let image = Self.pngBytes(suffix: [1])
        URLProtocolStub.install(delay: 0.15) { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, image)
        }
        let cache = try ImageCache(
            session: makeSession(),
            directoryURL: rootURL,
            maximumDiskSize: 1_024,
            maximumResponseSize: 100,
            maximumConcurrentDownloads: 2
        )

        await withTaskGroup(of: Data?.self) { group in
            for index in 0..<5 {
                group.addTask {
                    await cache.data(for: URL(string: "https://images.example.com/\(index).png")!)
                }
            }
            for await _ in group {}
        }

        XCTAssertLessThanOrEqual(URLProtocolStub.maximumActiveRequestCount, 2)
    }

    func testCancelledOnlyWaiterReturnsPromptlyAndCancelsSharedDownload() async throws {
        let image = Self.pngBytes(suffix: [1])
        URLProtocolStub.install(delay: 2) { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, image)
        }
        let cache = try ImageCache(
            session: makeSession(),
            directoryURL: rootURL,
            maximumDiskSize: 1_024,
            maximumResponseSize: 100,
            maximumConcurrentDownloads: 1
        )
        let task = Task {
            await cache.data(for: URL(string: "https://images.example.com/slow.png")!)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        task.cancel()
        let started = Date()
        let result = await task.value

        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
    }

    func testStartupMaintenanceRunsOnceAndHitsDoNotRescanDirectory() async throws {
        let counter = LockedCounter()
        let image = Self.pngBytes(suffix: [1, 2, 3])
        URLProtocolStub.install { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, image)
        }
        let cache = try ImageCache(
            session: makeSession(),
            directoryURL: rootURL,
            maximumDiskSize: 1_024,
            startupMaintenanceObserver: { counter.increment() }
        )
        await cache.waitForMaintenance()
        let url = URL(string: "https://images.example.com/hit.png")!

        _ = await cache.data(for: url)
        _ = await cache.data(for: url)
        _ = await cache.data(for: url)

        XCTAssertEqual(counter.value, 1)
        XCTAssertEqual(URLProtocolStub.requestCount, 1)
    }

    func testMetadataFailurePreventsPersistentWrites() async throws {
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: true)
        let unknownFile = ownedDirectory.appendingPathComponent(String(repeating: "b", count: 64) + ".image")
        try Self.pngBytes(suffix: [9]).write(to: unknownFile)
        let image = Self.pngBytes(suffix: [1, 2, 3])
        URLProtocolStub.install { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, image)
        }
        let operations = FailingMaintenanceOperations(failure: .metadata)
        let cache = try ImageCache(
            session: makeSession(),
            directoryURL: rootURL,
            maximumDiskSize: 1_024,
            maintenanceOperations: operations
        )
        await cache.waitForMaintenance()

        let result = await cache.data(for: URL(string: "https://images.example.com/new.png")!)

        XCTAssertEqual(result, image)
        XCTAssertEqual(try ownedImageFiles(), [unknownFile.lastPathComponent])
        XCTAssertEqual(operations.filesCallCount, 2)
    }

    func testDeletionFailureKeepsSurvivingBytesAndPreventsNewCacheWrite() async throws {
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: true)
        let oversizedFile = ownedDirectory.appendingPathComponent(String(repeating: "c", count: 64) + ".image")
        try Data(repeating: 7, count: 200).write(to: oversizedFile)
        let image = Self.pngBytes(suffix: [1, 2, 3])
        URLProtocolStub.install { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, image)
        }
        let operations = FailingMaintenanceOperations(failure: .deletion)
        let cache = try ImageCache(
            session: makeSession(),
            directoryURL: rootURL,
            maximumDiskSize: 100,
            maximumResponseSize: 80,
            maintenanceOperations: operations
        )
        await cache.waitForMaintenance()

        let result = await cache.data(for: URL(string: "https://images.example.com/new.png")!)

        XCTAssertEqual(result, image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: oversizedFile.path))
        XCTAssertEqual(try ownedImageFiles(), [oversizedFile.lastPathComponent])
        XCTAssertEqual(operations.filesCallCount, 2)
    }

    func testResponseOverDiskItemLimitReturnsUncachedWithoutTouchingExistingFiles() async throws {
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: true)
        let existingFile = ownedDirectory.appendingPathComponent(String(repeating: "d", count: 64) + ".image")
        let existing = Self.pngBytes(suffix: Array(repeating: 4, count: 20))
        try existing.write(to: existingFile)
        let tooLargeForDisk = Self.pngBytes(suffix: Array(repeating: 8, count: 80))
        URLProtocolStub.install { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, tooLargeForDisk)
        }
        let cache = try ImageCache(
            session: makeSession(),
            directoryURL: rootURL,
            maximumDiskSize: existing.count + 5,
            maximumResponseSize: 200
        )
        await cache.waitForMaintenance()

        let result = await cache.data(for: URL(string: "https://images.example.com/too-large.png")!)

        XCTAssertEqual(result, tooLargeForDisk)
        XCTAssertEqual(try ownedImageFiles(), [existingFile.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: existingFile), existing)
    }

    func testIncrementalEvictionFailureDoesNotCommitNewFileOrExceedBound() async throws {
        try FileManager.default.createDirectory(at: ownedDirectory, withIntermediateDirectories: true)
        let existingFile = ownedDirectory.appendingPathComponent(String(repeating: "e", count: 64) + ".image")
        let existing = Self.pngBytes(suffix: Array(repeating: 4, count: 20))
        try existing.write(to: existingFile)
        let replacement = Self.pngBytes(suffix: Array(repeating: 5, count: 20))
        URLProtocolStub.install { request in
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            ))
            return (response, replacement)
        }
        let operations = FailingMaintenanceOperations(failure: .deletion)
        let diskBound = existing.count + 5
        let cache = try ImageCache(
            session: makeSession(),
            directoryURL: rootURL,
            maximumDiskSize: diskBound,
            maximumResponseSize: 200,
            maintenanceOperations: operations
        )
        await cache.waitForMaintenance()

        let result = await cache.data(for: URL(string: "https://images.example.com/new-item.png")!)

        XCTAssertEqual(result, replacement)
        XCTAssertEqual(try ownedImageFiles(), [existingFile.lastPathComponent])
        XCTAssertEqual(try Data(contentsOf: existingFile), existing)
        XCTAssertLessThanOrEqual(try ownedImageDiskUsage(), diskBound)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private var ownedDirectory: URL {
        rootURL.appendingPathComponent(ImageCache.cacheDirectoryName, isDirectory: true)
    }

    private func ownedImageFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: ownedDirectory.path)
            .filter { $0.hasSuffix(".image") }
            .sorted()
    }

    private func ownedImageDiskUsage() throws -> Int {
        try FileManager.default.contentsOfDirectory(
            at: ownedDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.pathExtension == "image" }.reduce(0) { total, url in
            total + (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
    }

    private static func pngBytes(suffix: [UInt8]) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + suffix)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private final class FailingMaintenanceOperations: ImageCacheMaintenanceOperations, @unchecked Sendable {
    enum Failure: Equatable {
        case metadata
        case deletion
    }

    private let failure: Failure
    private let base = DefaultImageCacheMaintenanceOperations(fileManager: .default)
    private let lock = NSLock()
    private var _filesCallCount = 0

    var filesCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _filesCallCount
    }

    init(failure: Failure) {
        self.failure = failure
    }

    func files(at directoryURL: URL) throws -> [URL] {
        lock.lock()
        _filesCallCount += 1
        lock.unlock()
        return try base.files(at: directoryURL)
    }

    func metadata(for url: URL) throws -> ImageCacheFileMetadata {
        if failure == .metadata { throw StubMaintenanceError.failed }
        return try base.metadata(for: url)
    }

    func removeItem(at url: URL) throws {
        if failure == .deletion { throw StubMaintenanceError.failed }
        try base.removeItem(at: url)
    }

    func fileExists(at url: URL) -> Bool {
        base.fileExists(at: url)
    }

    private enum StubMaintenanceError: Error {
        case failed
    }
}
