import Foundation

enum Credibility: String, Codable, CaseIterable, Sendable {
    case official
    case media
    case unverified
}

extension Credibility {
    var displayName: String {
        switch self {
        case .official: return "官方"
        case .media: return "媒体报道"
        case .unverified: return "未经证实"
        }
    }

    var explanation: String {
        switch self {
        case .official:
            return "信息由 Rockstar Games 或 Take-Two 官方渠道直接发布。"
        case .media:
            return "信息来自具名媒体报道，请以 Rockstar Games 后续公告为准。"
        case .unverified:
            return "该消息尚未获得 Rockstar Games 或 Take-Two 官方证实。"
        }
    }
}
