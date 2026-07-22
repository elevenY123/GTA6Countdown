import Foundation
import XCTest
@testable import GTA6Countdown

final class NewsDecodingTests: XCTestCase {
    func testDecodesApprovedFixtureAndIgnoresUnknownFields() throws {
        let payload = try NewsPayload.decode(from: fixtureData())

        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.articles.count, 2)
        XCTAssertEqual(payload.articles[0].credibility, .official)
        XCTAssertEqual(payload.articles[1].credibility, .media)
        XCTAssertEqual(payload.remoteConfig.releaseDate, RemoteConfig.defaultReleaseDate)
        XCTAssertEqual(payload.remoteConfig.releaseTimeMode, .localMidnight)
    }

    func testCredibilityOnlyAcceptsApprovedValues() throws {
        XCTAssertEqual(try decodeCredibility("official"), .official)
        XCTAssertEqual(try decodeCredibility("media"), .media)
        XCTAssertEqual(try decodeCredibility("unverified"), .unverified)
        XCTAssertThrowsError(try decodeCredibility("rumor"))
    }

    func testRejectsArticleWithInvalidRequiredSourceURL() throws {
        let data = try replacing(in: fixtureData(), key: "sourceURL", with: "not a web URL")

        XCTAssertThrowsError(try NewsPayload.decode(from: data))
    }

    func testInvalidOptionalImageURLBecomesNil() throws {
        let data = try replacing(in: fixtureData(), key: "imageURL", with: "broken image URL")

        let payload = try NewsPayload.decode(from: data)

        XCTAssertNil(payload.articles[0].imageURL)
    }

    func testMalformedRemoteReleaseDateFallsBackToApprovedLocalDefault() throws {
        let data = try replacing(in: fixtureData(), key: "releaseDate", with: "2026-99-99")

        let payload = try NewsPayload.decode(from: data)

        XCTAssertEqual(payload.remoteConfig.releaseDate, "2026-11-19")
        XCTAssertEqual(payload.remoteConfig.releaseDateComponents.year, 2026)
        XCTAssertEqual(payload.remoteConfig.releaseDateComponents.month, 11)
        XCTAssertEqual(payload.remoteConfig.releaseDateComponents.day, 19)
    }

    func testValidNonDefaultRemoteReleaseDateIsPreserved() throws {
        let data = try replacing(in: fixtureData(), key: "releaseDate", with: "2026-12-01")

        let payload = try NewsPayload.decode(from: data)

        XCTAssertEqual(payload.remoteConfig.releaseDate, "2026-12-01")
        XCTAssertEqual(payload.remoteConfig.releaseDateComponents.year, 2026)
        XCTAssertEqual(payload.remoteConfig.releaseDateComponents.month, 12)
        XCTAssertEqual(payload.remoteConfig.releaseDateComponents.day, 1)
    }

    func testNonStringRemoteReleaseDateAlsoFallsBackWithoutRejectingPayload() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData()) as? [String: Any])
        var config = try XCTUnwrap(object["remoteConfig"] as? [String: Any])
        config["releaseDate"] = ["malformed": true]
        object["remoteConfig"] = config
        let data = try JSONSerialization.data(withJSONObject: object)

        let payload = try NewsPayload.decode(from: data)

        XCTAssertEqual(payload.remoteConfig.releaseDate, RemoteConfig.defaultReleaseDate)
    }

    private func decodeCredibility(_ value: String) throws -> Credibility {
        try JSONDecoder().decode(Credibility.self, from: Data("\"\(value)\"".utf8))
    }

    private func fixtureData() throws -> Data {
        let testFile = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/news-payload.json")
        return try Data(contentsOf: fixtureURL)
    }

    private func replacing(in data: Data, key: String, with replacement: String) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        if key == "releaseDate" {
            var config = try XCTUnwrap(object["remoteConfig"] as? [String: Any])
            config[key] = replacement
            object["remoteConfig"] = config
        } else {
            var articles = try XCTUnwrap(object["articles"] as? [[String: Any]])
            articles[0][key] = replacement
            object["articles"] = articles
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
