import Foundation
import XCTest
@testable import GTA6Countdown

final class NewsPayloadValidatorTests: XCTestCase {
    func testRejectsOldPayloadAndRemoteConfigSchemas() throws {
        let payloadSchema = try payload { $0["schemaVersion"] = 0 }
        XCTAssertThrowsError(try NewsPayloadValidator.validate(payloadSchema)) { error in
            XCTAssertEqual(error as? NewsPayloadValidationError, .unsupportedSchema(0))
        }

        let configSchema = try payload { object in
            var config = try XCTUnwrap(object["remoteConfig"] as? [String: Any])
            config["schemaVersion"] = 2
            object["remoteConfig"] = config
        }
        XCTAssertThrowsError(try NewsPayloadValidator.validate(configSchema)) { error in
            XCTAssertEqual(error as? NewsPayloadValidationError, .unsupportedSchema(2))
        }
    }

    func testRejectsContradictoryOfficialAndPinnedMetadata() throws {
        let contradictoryOfficial = try payload { object in
            var articles = try XCTUnwrap(object["articles"] as? [[String: Any]])
            articles[0]["isOfficial"] = false
            object["articles"] = articles
        }
        XCTAssertThrowsError(try NewsPayloadValidator.validate(contradictoryOfficial)) { error in
            XCTAssertEqual(error as? NewsPayloadValidationError, .invalidPayload)
        }

        let contradictoryPin = try payload { object in
            var config = try XCTUnwrap(object["remoteConfig"] as? [String: Any])
            config["pinnedOfficialArticleID"] = "media-1"
            object["remoteConfig"] = config
        }
        XCTAssertThrowsError(try NewsPayloadValidator.validate(contradictoryPin)) { error in
            XCTAssertEqual(error as? NewsPayloadValidationError, .invalidPayload)
        }
    }

    func testBundledFetcherRejectsInvalidFixtureBeforeReturningIt() async throws {
        let invalid = try payload { $0["schemaVersion"] = 99 }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundledFetcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("invalid.json")
        try JSONEncoder().encode(invalid).write(to: url)

        do {
            _ = try await BundledNewsFetcher(url: url).fetch()
            XCTFail("Expected invalid bundled payload rejection")
        } catch {
            XCTAssertEqual(error as? NewsAPIClientError, .unsupportedSchema(99))
        }
    }

    private func payload(
        mutation: (inout [String: Any]) throws -> Void
    ) throws -> NewsPayload {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/news-payload.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any]
        )
        try mutation(&object)
        return try NewsPayload.decode(from: JSONSerialization.data(withJSONObject: object))
    }
}
