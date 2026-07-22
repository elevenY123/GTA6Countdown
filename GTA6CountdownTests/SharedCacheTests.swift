import Foundation
import XCTest
@testable import GTA6Countdown

final class SharedCacheTests: XCTestCase {
    private var rootURL: URL!
    private var fileManager: FileManager!

    override func setUpWithError() throws {
        fileManager = .default
        rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("SharedCacheTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? fileManager.removeItem(at: rootURL)
        }
    }

    func testPrefersAppGroupContainerWhenAvailable() throws {
        let groupURL = rootURL.appendingPathComponent("group", isDirectory: true)
        let sandboxURL = rootURL.appendingPathComponent("sandbox", isDirectory: true)
        let cache = try SharedCache(
            appGroupIdentifier: "group.test",
            filename: "feed.json",
            fileManager: fileManager,
            appGroupContainerURL: { _ in groupURL },
            sandboxDirectoryURL: { sandboxURL }
        )

        try cache.save(Sample(value: "group"))

        XCTAssertTrue(fileManager.fileExists(atPath: groupURL.appendingPathComponent("feed.json").path))
        XCTAssertFalse(fileManager.fileExists(atPath: sandboxURL.appendingPathComponent("feed.json").path))
    }

    func testFallsBackToSandboxWhenAppGroupIsUnavailable() throws {
        let sandboxURL = rootURL.appendingPathComponent("sandbox", isDirectory: true)
        let cache = try SharedCache(
            appGroupIdentifier: "group.test",
            filename: "feed.json",
            fileManager: fileManager,
            appGroupContainerURL: { _ in nil },
            sandboxDirectoryURL: { sandboxURL }
        )

        try cache.save(Sample(value: "sandbox"))

        XCTAssertTrue(fileManager.fileExists(atPath: sandboxURL.appendingPathComponent("feed.json").path))
    }

    func testSaveReplacesExistingFileAndLeavesNoTemporaryFile() throws {
        let cache = try makeSandboxCache()
        try cache.save(Sample(value: "old"))
        try cache.save(Sample(value: "new"))

        let result: CacheLoadResult<Sample> = cache.load(Sample.self)

        guard case let .hit(value) = result else {
            return XCTFail("Expected cache hit")
        }
        XCTAssertEqual(value, Sample(value: "new"))
        let files = try fileManager.contentsOfDirectory(atPath: rootURL.path)
        XCTAssertEqual(files, ["feed.json"])
    }

    func testMissingCacheIsAMiss() throws {
        let result: CacheLoadResult<Sample> = try makeSandboxCache().load(Sample.self)

        guard case .miss = result else {
            return XCTFail("Expected cache miss")
        }
    }

    func testCorruptedCacheReturnsFailureWithoutCrashing() throws {
        try Data("not json".utf8).write(to: rootURL.appendingPathComponent("feed.json"))

        let result: CacheLoadResult<Sample> = try makeSandboxCache().load(Sample.self)

        guard case .failure(.decodingFailed) = result else {
            return XCTFail("Expected a decoding failure")
        }
    }

    func testRejectsUnsafeOrEmptyFilename() {
        for filename in ["", ".", "..", "nested/feed.json", "nested\\feed.json"] {
            XCTAssertThrowsError(
                try SharedCache(
                    appGroupIdentifier: "group.test",
                    filename: filename,
                    fileManager: fileManager,
                    appGroupContainerURL: { _ in nil },
                    sandboxDirectoryURL: { self.rootURL }
                )
            ) { error in
                XCTAssertEqual(error as? SharedCacheError, .invalidFilename)
            }
        }
    }

    func testFailedPartialWriteRemovesTemporaryFile() throws {
        let cache = try SharedCache(
            appGroupIdentifier: "group.test",
            filename: "feed.json",
            fileManager: fileManager,
            appGroupContainerURL: { _ in nil },
            sandboxDirectoryURL: { self.rootURL },
            dataWriter: { _, temporaryURL in
                try Data("partial".utf8).write(to: temporaryURL)
                throw StubWriteError.failed
            }
        )

        XCTAssertThrowsError(try cache.save(Sample(value: "never committed"))) { error in
            XCTAssertEqual(error as? SharedCacheError, .writeFailed)
        }
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: rootURL.path), [])
    }

    private func makeSandboxCache() throws -> SharedCache {
        try SharedCache(
            appGroupIdentifier: "group.test",
            filename: "feed.json",
            fileManager: fileManager,
            appGroupContainerURL: { _ in nil },
            sandboxDirectoryURL: { self.rootURL }
        )
    }

    private struct Sample: Codable, Equatable {
        let value: String
    }

    private enum StubWriteError: Error {
        case failed
    }
}
