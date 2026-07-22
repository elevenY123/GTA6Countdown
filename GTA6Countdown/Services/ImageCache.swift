import CryptoKit
import Foundation

struct ImageCacheFileMetadata: Sendable {
    let isRegularFile: Bool
    let size: Int
    let lastModified: Date
}

protocol ImageCacheMaintenanceOperations: Sendable {
    func files(at directoryURL: URL) throws -> [URL]
    func metadata(for url: URL) throws -> ImageCacheFileMetadata
    func removeItem(at url: URL) throws
    func fileExists(at url: URL) -> Bool
}

final class DefaultImageCacheMaintenanceOperations: ImageCacheMaintenanceOperations, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    func files(at directoryURL: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: []
        )
    }

    func metadata(for url: URL) throws -> ImageCacheFileMetadata {
        let values = try url.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        )
        return ImageCacheFileMetadata(
            isRegularFile: values.isRegularFile == true,
            size: values.fileSize ?? 0,
            lastModified: values.contentModificationDate ?? .distantPast
        )
    }

    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    func fileExists(at url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }
}

enum ImageCacheError: Error, Equatable {
    case invalidMaximumDiskSize
    case invalidMaximumResponseSize
    case invalidMaximumConcurrentDownloads
    case cannotCreateDirectory
}

actor ImageCache {
    static let cacheDirectoryName = "GTA6NewsImages"

    private struct InFlightDownload {
        let task: Task<Data?, Never>
        var waiters: [UUID: DownloadWaiter]
    }

    private struct DownloadWaiter {
        var continuation: CheckedContinuation<Data?, Never>?
    }

    private struct DiskEntry: Sendable {
        let url: URL
        let size: Int
        let lastAccess: Date
    }

    private enum StartupMaintenanceResult: Sendable {
        case success([DiskEntry])
        case failure
    }

    private enum MaintenanceWriteError: Error {
        case inaccurateInventory
        case deletionFailed
    }

    private enum PersistResult {
        case committed
        case notCacheable
        case failure
    }

    private let session: URLSession
    private let directoryURL: URL
    private let maximumDiskSize: Int
    private let maximumResponseSize: Int
    private let fileManager: FileManager
    private let limiter: DownloadLimiter
    private let maintenanceOperations: ImageCacheMaintenanceOperations
    private let startupMaintenanceObserver: (@Sendable () -> Void)?
    private var inFlight: [URL: InFlightDownload] = [:]
    private var startupMaintenanceTask: Task<StartupMaintenanceResult, Never>?
    private var diskEntries: [URL: DiskEntry] = [:]
    private var trackedDiskSize = 0
    private var inventoryEstablished = false

    init(
        session: URLSession = .shared,
        directoryURL parentDirectoryURL: URL,
        maximumDiskSize: Int,
        maximumResponseSize: Int = 20 * 1_024 * 1_024,
        maximumConcurrentDownloads: Int = 4,
        fileManager: FileManager = .default,
        maintenanceOperations: ImageCacheMaintenanceOperations? = nil,
        startupMaintenanceObserver: (@Sendable () -> Void)? = nil
    ) throws {
        guard maximumDiskSize > 0 else {
            throw ImageCacheError.invalidMaximumDiskSize
        }
        guard maximumResponseSize > 0 else {
            throw ImageCacheError.invalidMaximumResponseSize
        }
        guard maximumConcurrentDownloads > 0 else {
            throw ImageCacheError.invalidMaximumConcurrentDownloads
        }

        let ownedDirectory = parentDirectoryURL.appendingPathComponent(
            Self.cacheDirectoryName,
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: ownedDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw ImageCacheError.cannotCreateDirectory
        }

        self.session = session
        self.directoryURL = ownedDirectory
        self.maximumDiskSize = maximumDiskSize
        self.maximumResponseSize = maximumResponseSize
        self.fileManager = fileManager
        self.limiter = DownloadLimiter(maximumConcurrentDownloads: maximumConcurrentDownloads)
        let operations = maintenanceOperations
            ?? DefaultImageCacheMaintenanceOperations(fileManager: fileManager)
        self.maintenanceOperations = operations
        self.startupMaintenanceObserver = startupMaintenanceObserver
        self.startupMaintenanceTask = Task.detached {
            startupMaintenanceObserver?()
            return Self.performStartupMaintenance(
                at: ownedDirectory,
                maximumDiskSize: maximumDiskSize,
                maximumResponseSize: maximumResponseSize,
                operations: operations
            )
        }
    }

    func data(for url: URL) async -> Data? {
        let fileURL = diskURL(for: url)
        if let cached = validDiskData(at: fileURL) {
            try? fileManager.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: fileURL.path
            )
            updateTrackedAccessDate(for: fileURL)
            return cached
        }

        let waiterID = UUID()
        reserveDownload(for: url, waiterID: waiterID)
        return await withTaskCancellationHandler(operation: {
            await waitForDownload(for: url, waiterID: waiterID)
        }, onCancel: {
            Task { await self.cancelWaiter(for: url, waiterID: waiterID) }
        })
    }

    func waitForMaintenance() async {
        await synchronizeStartupMaintenance()
    }

    private func reserveDownload(for url: URL, waiterID: UUID) {
        if var download = inFlight[url] {
            download.waiters[waiterID] = DownloadWaiter(continuation: nil)
            inFlight[url] = download
            return
        }

        let session = self.session
        let limiter = self.limiter
        let maximumResponseSize = self.maximumResponseSize
        let task = Task {
            guard await limiter.acquire() else { return nil }
            let data = await Self.download(
                url: url,
                using: session,
                maximumResponseSize: maximumResponseSize
            )
            await limiter.release()
            return data
        }
        inFlight[url] = InFlightDownload(
            task: task,
            waiters: [waiterID: DownloadWaiter(continuation: nil)]
        )

        Task { [weak self] in
            let data = await task.value
            await self?.completeDownload(for: url, data: data)
        }
    }

    private func waitForDownload(for url: URL, waiterID: UUID) async -> Data? {
        await withCheckedContinuation { continuation in
            guard !Task.isCancelled else {
                continuation.resume(returning: nil)
                cancelWaiter(for: url, waiterID: waiterID)
                return
            }
            guard var download = inFlight[url], download.waiters[waiterID] != nil else {
                continuation.resume(returning: validDiskData(at: diskURL(for: url)))
                return
            }
            download.waiters[waiterID] = DownloadWaiter(continuation: continuation)
            inFlight[url] = download
        }
    }

    private func cancelWaiter(for url: URL, waiterID: UUID) {
        guard var download = inFlight[url] else { return }
        if let continuation = download.waiters.removeValue(forKey: waiterID)?.continuation {
            continuation.resume(returning: nil)
        }
        if download.waiters.isEmpty {
            download.task.cancel()
            inFlight[url] = nil
        } else {
            inFlight[url] = download
        }
    }

    private func completeDownload(for url: URL, data: Data?) async {
        guard let download = inFlight.removeValue(forKey: url) else { return }
        var deliveredData = data
        if let data {
            if await prepareInventoryForWrite() {
                switch persist(data, at: diskURL(for: url)) {
                case .committed, .notCacheable, .failure:
                    deliveredData = data
                }
            }
        }
        for waiter in download.waiters.values {
            waiter.continuation?.resume(returning: deliveredData)
        }
    }

    private func diskURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent("\(key).image", isDirectory: false)
    }

    private func validDiskData(at url: URL) -> Data? {
        guard
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true,
            let fileSize = values.fileSize,
            fileSize > 0,
            fileSize <= maximumResponseSize,
            fileSize <= maximumDiskSize
        else {
            removeCacheFileConservatively(at: url)
            return nil
        }
        guard let data = try? Data(contentsOf: url), Self.hasRecognizedImageSignature(data) else {
            removeCacheFileConservatively(at: url)
            return nil
        }
        return data
    }

    private func persist(_ data: Data, at destinationURL: URL) -> PersistResult {
        guard data.count <= maximumResponseSize, data.count <= maximumDiskSize else {
            return .notCacheable
        }
        do {
            try prepareCapacityForWrite(size: data.count)
            try commit(data, at: destinationURL)
            recordCommittedWrite(at: destinationURL, size: data.count)
            return .committed
        } catch {
            inventoryEstablished = false
            return .failure
        }
    }

    private func commit(_ data: Data, at destinationURL: URL) throws {
        let temporaryURL = directoryURL.appendingPathComponent(
            ".download-\(UUID().uuidString).tmp",
            isDirectory: false
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try data.write(to: temporaryURL)
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
    }

    private func synchronizeStartupMaintenance() async {
        guard let startupMaintenanceTask else { return }
        let result = await startupMaintenanceTask.value
        guard self.startupMaintenanceTask != nil else { return }
        self.startupMaintenanceTask = nil
        guard case let .success(startupEntries) = result else {
            inventoryEstablished = false
            return
        }
        diskEntries.removeAll(keepingCapacity: true)
        trackedDiskSize = 0
        for entry in startupEntries {
            let metadata: ImageCacheFileMetadata
            do {
                metadata = try maintenanceOperations.metadata(for: entry.url)
            } catch {
                if !maintenanceOperations.fileExists(at: entry.url) {
                    continue
                }
                diskEntries.removeAll(keepingCapacity: true)
                trackedDiskSize = 0
                inventoryEstablished = false
                return
            }
            guard metadata.isRegularFile else {
                continue
            }
            guard
                metadata.size > 0,
                metadata.size <= maximumResponseSize,
                metadata.size <= maximumDiskSize
            else {
                diskEntries.removeAll(keepingCapacity: true)
                trackedDiskSize = 0
                inventoryEstablished = false
                return
            }
            let refreshed = DiskEntry(
                url: entry.url,
                size: metadata.size,
                lastAccess: metadata.lastModified
            )
            diskEntries[entry.url] = refreshed
            trackedDiskSize += metadata.size
        }
        inventoryEstablished = true
    }

    private func prepareInventoryForWrite() async -> Bool {
        if startupMaintenanceTask != nil {
            await synchronizeStartupMaintenance()
            return inventoryEstablished
        }
        guard !inventoryEstablished else { return true }
        scheduleMaintenanceRetry()
        await synchronizeStartupMaintenance()
        return inventoryEstablished
    }

    private func scheduleMaintenanceRetry() {
        guard startupMaintenanceTask == nil else { return }
        let directoryURL = self.directoryURL
        let maximumDiskSize = self.maximumDiskSize
        let maximumResponseSize = self.maximumResponseSize
        let operations = self.maintenanceOperations
        let observer = self.startupMaintenanceObserver
        startupMaintenanceTask = Task.detached {
            observer?()
            return Self.performStartupMaintenance(
                at: directoryURL,
                maximumDiskSize: maximumDiskSize,
                maximumResponseSize: maximumResponseSize,
                operations: operations
            )
        }
    }

    private func updateTrackedAccessDate(for url: URL) {
        guard let entry = diskEntries[url] else { return }
        diskEntries[url] = DiskEntry(url: url, size: entry.size, lastAccess: Date())
    }

    private func removeTrackedEntry(at url: URL) {
        if let removed = diskEntries.removeValue(forKey: url) {
            trackedDiskSize -= removed.size
        }
    }

    private func removeCacheFileConservatively(at url: URL) {
        guard maintenanceOperations.fileExists(at: url) else {
            removeTrackedEntry(at: url)
            return
        }
        if Self.confirmedRemoval(of: url, using: maintenanceOperations) {
            removeTrackedEntry(at: url)
        } else {
            inventoryEstablished = false
        }
    }

    private func prepareCapacityForWrite(size: Int) throws {
        guard inventoryEstablished else { throw MaintenanceWriteError.inaccurateInventory }
        // Reserve for the temporary/new bytes while every existing file still exists.
        // This keeps the bound valid even if an atomic replacement fails before commit.
        var projectedSize = trackedDiskSize + size
        var candidates = diskEntries.values
            .sorted { $0.lastAccess < $1.lastAccess }

        while projectedSize > maximumDiskSize {
            guard !candidates.isEmpty else {
                inventoryEstablished = false
                throw MaintenanceWriteError.inaccurateInventory
            }
            let oldest = candidates.removeFirst()
            do {
                try maintenanceOperations.removeItem(at: oldest.url)
                guard !maintenanceOperations.fileExists(at: oldest.url) else {
                    throw MaintenanceWriteError.deletionFailed
                }
            } catch {
                inventoryEstablished = false
                throw MaintenanceWriteError.deletionFailed
            }
            removeTrackedEntry(at: oldest.url)
            projectedSize -= oldest.size
        }
    }

    private func recordCommittedWrite(at url: URL, size: Int) {
        removeTrackedEntry(at: url)
        diskEntries[url] = DiskEntry(url: url, size: size, lastAccess: Date())
        trackedDiskSize += size
    }

    private static func performStartupMaintenance(
        at directoryURL: URL,
        maximumDiskSize: Int,
        maximumResponseSize: Int,
        operations: ImageCacheMaintenanceOperations
    ) -> StartupMaintenanceResult {
        let files: [URL]
        do {
            files = try operations.files(at: directoryURL)
        } catch {
            return .failure
        }
        var entries: [(url: URL, size: Int, date: Date)] = []

        for url in files {
            let name = url.lastPathComponent
            if name.hasPrefix(".download-") && name.hasSuffix(".tmp") {
                guard confirmedRemoval(of: url, using: operations) else { return .failure }
                continue
            }
            guard isOwnedCacheFile(name) else { continue }
            let metadata: ImageCacheFileMetadata
            do {
                metadata = try operations.metadata(for: url)
            } catch {
                return .failure
            }
            guard metadata.isRegularFile else { continue }
            if metadata.size <= 0
                || metadata.size > maximumResponseSize
                || metadata.size > maximumDiskSize {
                guard confirmedRemoval(of: url, using: operations) else { return .failure }
                continue
            }
            entries.append((url, metadata.size, metadata.lastModified))
        }

        var total = entries.reduce(0) { $0 + $1.size }
        entries.sort { $0.date < $1.date }
        while total > maximumDiskSize, !entries.isEmpty {
            let entry = entries[0]
            guard confirmedRemoval(of: entry.url, using: operations) else { return .failure }
            entries.removeFirst()
            total -= entry.size
        }
        return .success(entries.map {
            DiskEntry(url: $0.url, size: $0.size, lastAccess: $0.date)
        })
    }

    private static func confirmedRemoval(
        of url: URL,
        using operations: ImageCacheMaintenanceOperations
    ) -> Bool {
        do {
            try operations.removeItem(at: url)
            return !operations.fileExists(at: url)
        } catch {
            return false
        }
    }

    private static func isOwnedCacheFile(_ filename: String) -> Bool {
        guard filename.hasSuffix(".image") else { return false }
        let key = filename.dropLast(".image".count)
        guard key.count == 64 else { return false }
        return key.allSatisfy { character in
            character.isNumber || "abcdef".contains(character)
        }
    }

    private static func download(
        url: URL,
        using session: URLSession,
        maximumResponseSize: Int
    ) async -> Data? {
        do {
            let (temporaryURL, response) = try await session.download(from: url)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode),
                http.value(forHTTPHeaderField: "Content-Type")?
                    .lowercased()
                    .hasPrefix("image/") == true,
                let fileSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                fileSize > 0,
                fileSize <= maximumResponseSize
            else {
                return nil
            }
            let data = try Data(contentsOf: temporaryURL)
            return hasRecognizedImageSignature(data) ? data : nil
        } catch {
            return nil
        }
    }

    private static func hasRecognizedImageSignature(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(16))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return true
        }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return true
        }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
            return true
        }
        if bytes.count >= 12,
           String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
           String(bytes: bytes[8..<12], encoding: .ascii) == "WEBP" {
            return true
        }
        if bytes.count >= 12,
           String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp" {
            let brand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
            return ["heic", "heix", "hevc", "hevx", "mif1", "avif"].contains(brand)
        }
        return false
    }
}

private actor DownloadLimiter {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var availablePermits: Int
    private var waiters: [Waiter] = []

    init(maximumConcurrentDownloads: Int) {
        availablePermits = maximumConcurrentDownloads
    }

    func acquire() async -> Bool {
        if Task.isCancelled { return false }
        let waiterID = UUID()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else if availablePermits > 0 {
                    availablePermits -= 1
                    continuation.resume(returning: true)
                } else {
                    waiters.append(Waiter(id: waiterID, continuation: continuation))
                }
            }
        }, onCancel: {
            Task { await self.cancel(waiterID: waiterID) }
        })
    }

    func release() {
        if waiters.isEmpty {
            availablePermits += 1
        } else {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume(returning: true)
        }
    }

    private func cancel(waiterID: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }
}
