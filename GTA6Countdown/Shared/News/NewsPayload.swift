import Foundation

struct NewsPayload: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let updatedAt: Date
    let remoteConfig: RemoteConfig
    let articles: [NewsArticle]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case updatedAt
        case remoteConfig
        case articles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        updatedAt = try APIDateCoding.decodeDate(from: container, forKey: .updatedAt)
        remoteConfig = try container.decode(RemoteConfig.self, forKey: .remoteConfig)
        articles = try container.decode([NewsArticle].self, forKey: .articles)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(APIDateCoding.string(from: updatedAt), forKey: .updatedAt)
        try container.encode(remoteConfig, forKey: .remoteConfig)
        try container.encode(articles, forKey: .articles)
    }

    static func decode(from data: Data) throws -> NewsPayload {
        try JSONDecoder().decode(NewsPayload.self, from: data)
    }
}

enum APIDateCoding {
    static func decodeDate<Key: CodingKey>(
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) throws -> Date {
        let value = try container.decode(String.self, forKey: key)
        guard let date = date(from: value) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Expected an ISO 8601 timestamp"
            )
        }
        return date
    }

    static func date(from value: String) -> Date? {
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) {
            return date
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }

    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
