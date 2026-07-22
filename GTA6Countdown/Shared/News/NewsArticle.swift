import Foundation

struct NewsArticle: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let sourceName: String
    let sourceURL: URL
    let publishedAt: Date
    let imageURL: URL?
    let credibility: Credibility
    let isOfficial: Bool
    let isPinned: Bool
    let relatedSourceCount: Int
    let canonicalTopicKey: String

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case summary
        case sourceName
        case sourceURL
        case publishedAt
        case imageURL
        case credibility
        case isOfficial
        case isPinned
        case relatedSourceCount
        case canonicalTopicKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        sourceName = try container.decode(String.self, forKey: .sourceName)

        let sourceURLString = try container.decode(String.self, forKey: .sourceURL)
        guard let validSourceURL = WebURLValidator.url(from: sourceURLString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .sourceURL,
                in: container,
                debugDescription: "sourceURL must be an absolute HTTP or HTTPS URL"
            )
        }
        sourceURL = validSourceURL

        publishedAt = try APIDateCoding.decodeDate(from: container, forKey: .publishedAt)

        if let imageURLString = try container.decodeIfPresent(String.self, forKey: .imageURL) {
            imageURL = WebURLValidator.url(from: imageURLString)
        } else {
            imageURL = nil
        }

        credibility = try container.decode(Credibility.self, forKey: .credibility)
        isOfficial = try container.decode(Bool.self, forKey: .isOfficial)
        isPinned = try container.decode(Bool.self, forKey: .isPinned)
        relatedSourceCount = try container.decode(Int.self, forKey: .relatedSourceCount)
        canonicalTopicKey = try container.decode(String.self, forKey: .canonicalTopicKey)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(summary, forKey: .summary)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(sourceURL.absoluteString, forKey: .sourceURL)
        try container.encode(APIDateCoding.string(from: publishedAt), forKey: .publishedAt)
        try container.encodeIfPresent(imageURL?.absoluteString, forKey: .imageURL)
        try container.encode(credibility, forKey: .credibility)
        try container.encode(isOfficial, forKey: .isOfficial)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(relatedSourceCount, forKey: .relatedSourceCount)
        try container.encode(canonicalTopicKey, forKey: .canonicalTopicKey)
    }
}

private enum WebURLValidator {
    static func url(from value: String) -> URL? {
        guard
            let components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host?.isEmpty == false,
            let url = components.url
        else {
            return nil
        }
        return url
    }
}
