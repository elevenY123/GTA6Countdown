import Foundation

enum NewsPayloadValidationError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case invalidPayload
}

enum NewsPayloadValidator {
    static let supportedSchemaVersion = 1

    @discardableResult
    static func validate(_ payload: NewsPayload) throws -> NewsPayload {
        guard payload.schemaVersion == supportedSchemaVersion else {
            throw NewsPayloadValidationError.unsupportedSchema(payload.schemaVersion)
        }
        guard payload.remoteConfig.schemaVersion == supportedSchemaVersion else {
            throw NewsPayloadValidationError.unsupportedSchema(payload.remoteConfig.schemaVersion)
        }

        var identifiers = Set<String>()
        for article in payload.articles {
            guard
                !article.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !article.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !article.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !article.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !article.canonicalTopicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                article.relatedSourceCount >= 0,
                article.isOfficial == (article.credibility == .official),
                !article.isPinned || article.isOfficial,
                identifiers.insert(article.id).inserted
            else {
                throw NewsPayloadValidationError.invalidPayload
            }
        }

        let pinnedID = payload.remoteConfig.pinnedOfficialArticleID
        let pinnedArticles = payload.articles.filter(\.isPinned)
        if let pinnedID {
            guard
                pinnedArticles.count == 1,
                let pinned = pinnedArticles.first,
                pinned.id == pinnedID,
                pinned.isOfficial,
                pinned.credibility == .official
            else {
                throw NewsPayloadValidationError.invalidPayload
            }
        } else if !pinnedArticles.isEmpty {
            throw NewsPayloadValidationError.invalidPayload
        }

        for (key, message) in payload.remoteConfig.milestoneMessages {
            guard
                !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw NewsPayloadValidationError.invalidPayload
            }
        }
        return payload
    }
}
