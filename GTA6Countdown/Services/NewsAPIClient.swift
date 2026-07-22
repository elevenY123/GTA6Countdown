import Foundation

enum NewsAPIClientError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case invalidPayload
    case unsupportedSchema(Int)
}

protocol NewsFetching {
    func fetch() async throws -> NewsPayload
}

final class NewsAPIClient: NewsFetching {
    static let supportedSchemaVersion = NewsPayloadValidator.supportedSchemaVersion

    private let session: URLSession
    private let endpoint: URL

    init(session: URLSession = .shared, endpoint: URL) {
        self.session = session
        self.endpoint = endpoint
    }

    func fetch() async throws -> NewsPayload {
        let (data, response) = try await session.data(from: endpoint)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NewsAPIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NewsAPIClientError.httpStatus(httpResponse.statusCode)
        }

        let payload: NewsPayload
        do {
            payload = try NewsPayload.decode(from: data)
        } catch {
            throw NewsAPIClientError.invalidPayload
        }

        do {
            return try NewsPayloadValidator.validate(payload)
        } catch let error as NewsPayloadValidationError {
            switch error {
            case let .unsupportedSchema(version):
                throw NewsAPIClientError.unsupportedSchema(version)
            case .invalidPayload:
                throw NewsAPIClientError.invalidPayload
            }
        }
    }
}
