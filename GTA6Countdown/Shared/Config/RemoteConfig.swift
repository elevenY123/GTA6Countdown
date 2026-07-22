import Foundation

enum ReleaseTimeMode: String, Codable, Sendable {
    case localMidnight
}

struct RemoteConfig: Codable, Equatable, Sendable {
    static let defaultReleaseDate = "2026-11-19"
    static let defaultReleaseDateComponents = DateComponents(
        year: 2026,
        month: 11,
        day: 19,
        hour: 0,
        minute: 0,
        second: 0
    )

    let releaseDate: String
    let releaseTimeMode: ReleaseTimeMode
    let milestoneMessages: [String: String]
    let pinnedOfficialArticleID: String?
    let lastUpdatedAt: Date
    let schemaVersion: Int

    var releaseDateComponents: DateComponents {
        Self.components(for: releaseDate) ?? Self.defaultReleaseDateComponents
    }

    private enum CodingKeys: String, CodingKey {
        case releaseDate
        case releaseTimeMode
        case milestoneMessages
        case pinnedOfficialArticleID
        case lastUpdatedAt
        case schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let proposedDate = try? container.decode(String.self, forKey: .releaseDate)
        releaseDate = proposedDate.flatMap(Self.validatedReleaseDate) ?? Self.defaultReleaseDate
        releaseTimeMode = (try? container.decode(ReleaseTimeMode.self, forKey: .releaseTimeMode)) ?? .localMidnight
        milestoneMessages = (try? container.decode([String: String].self, forKey: .milestoneMessages)) ?? [:]
        pinnedOfficialArticleID = try container.decodeIfPresent(String.self, forKey: .pinnedOfficialArticleID)
        lastUpdatedAt = try APIDateCoding.decodeDate(from: container, forKey: .lastUpdatedAt)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(releaseDate, forKey: .releaseDate)
        try container.encode(releaseTimeMode, forKey: .releaseTimeMode)
        try container.encode(milestoneMessages, forKey: .milestoneMessages)
        try container.encodeIfPresent(pinnedOfficialArticleID, forKey: .pinnedOfficialArticleID)
        try container.encode(APIDateCoding.string(from: lastUpdatedAt), forKey: .lastUpdatedAt)
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }

    private static func validatedReleaseDate(_ value: String) -> String? {
        components(for: value) == nil ? nil : value
    }

    private static func components(for value: String) -> DateComponents? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            parts[0].count == 4,
            parts[1].count == 2,
            parts[2].count == 2,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let proposed = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: proposed) else {
            return nil
        }
        let verified = calendar.dateComponents([.year, .month, .day], from: date)
        guard verified.year == year, verified.month == month, verified.day == day else {
            return nil
        }
        return DateComponents(
            year: year,
            month: month,
            day: day,
            hour: 0,
            minute: 0,
            second: 0
        )
    }
}
