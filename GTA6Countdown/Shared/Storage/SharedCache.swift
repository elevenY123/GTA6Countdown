import Foundation

enum SharedCacheError: Error, Equatable {
    case invalidFilename
    case unreadable
    case decodingFailed
    case encodingFailed
    case writeFailed
}

enum CacheLoadResult<Value> {
    case hit(Value)
    case miss
    case failure(SharedCacheError)
}

struct SharedCache {
    typealias ContainerURLProvider = (String) -> URL?
    typealias SandboxURLProvider = () -> URL
    typealias DataWriter = (Data, URL) throws -> Void

    private let appGroupIdentifier: String
    private let filename: String
    private let fileManager: FileManager
    private let appGroupContainerURL: ContainerURLProvider
    private let sandboxDirectoryURL: SandboxURLProvider
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dataWriter: DataWriter

    init(
        appGroupIdentifier: String,
        filename: String,
        fileManager: FileManager = .default,
        appGroupContainerURL: ContainerURLProvider? = nil,
        sandboxDirectoryURL: SandboxURLProvider? = nil,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        dataWriter: DataWriter? = nil
    ) throws {
        guard Self.isSafeFilename(filename) else {
            throw SharedCacheError.invalidFilename
        }
        self.appGroupIdentifier = appGroupIdentifier
        self.filename = filename
        self.fileManager = fileManager
        self.appGroupContainerURL = appGroupContainerURL ?? { identifier in
            fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        }
        self.sandboxDirectoryURL = sandboxDirectoryURL ?? {
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
        }
        self.encoder = encoder
        self.decoder = decoder
        self.dataWriter = dataWriter ?? { data, url in
            try data.write(to: url)
        }
    }

    func load<Value: Decodable>(_ type: Value.Type) -> CacheLoadResult<Value> {
        let fileURL = resolvedDirectoryURL().appendingPathComponent(filename, isDirectory: false)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .miss
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return .failure(.unreadable)
        }

        do {
            return .hit(try decoder.decode(type, from: data))
        } catch {
            return .failure(.decodingFailed)
        }
    }

    func save<Value: Encodable>(_ value: Value) throws {
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw SharedCacheError.encodingFailed
        }

        let directoryURL = resolvedDirectoryURL()
        let destinationURL = directoryURL.appendingPathComponent(filename, isDirectory: false)
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(filename).\(UUID().uuidString).tmp",
            isDirectory: false
        )

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
            defer { try? fileManager.removeItem(at: temporaryURL) }
            try dataWriter(data, temporaryURL)

            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(
                    destinationURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
        } catch {
            throw SharedCacheError.writeFailed
        }
    }

    private func resolvedDirectoryURL() -> URL {
        appGroupContainerURL(appGroupIdentifier) ?? sandboxDirectoryURL()
    }

    private static func isSafeFilename(_ filename: String) -> Bool {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
            && filename != "."
            && filename != ".."
            && !filename.contains("/")
            && !filename.contains("\\")
            && !filename.contains("\0")
    }
}
