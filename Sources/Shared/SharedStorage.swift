import Darwin
import Foundation

enum SharedStorageError: LocalizedError, Sendable {
    case appGroupUnavailable
    case developmentDirectoryUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "无法访问 SitRight App Group，共享统计已暂停"
        case .developmentDirectoryUnavailable(let message):
            return "无法访问 SitRight 本地存储：\(message)"
        }
    }
}

enum SharedStorage {
    static let appGroupIdentifiers = [
        "973KFG9CL9.com.leon.SitRight"
    ]
    static let lockFileName = ".SitRightStorage.lock"
    private static let processLock = NSLock()

    private static let cachedRuntimeStorageDirectory: Result<URL, SharedStorageError> = {
        if let appGroupDirectory = resolveAppGroupDirectory() {
            return .success(appGroupDirectory)
        }

        guard !isPackagedBundle else {
            return .failure(.appGroupUnavailable)
        }

        do {
            return .success(try developmentStorageDirectory())
        } catch let error as SharedStorageError {
            return .failure(error)
        } catch {
            return .failure(.developmentDirectoryUnavailable(error.localizedDescription))
        }
    }()

    static func storageDirectory() throws -> URL {
        try cachedRuntimeStorageDirectory.get()
    }

    static func readableFileURL(named fileName: String) -> URL? {
        guard let directory = try? storageDirectory() else { return nil }
        let url = directory.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func migrateDevelopmentFilesToAppGroupIfNeeded(named fileNames: [String]) throws {
        guard Bundle.main.bundleURL.pathExtension.lowercased() == "app" else { return }
        guard let appGroupDirectory = resolveAppGroupDirectory() else {
            throw SharedStorageError.appGroupUnavailable
        }

        let developmentDirectory = try developmentStorageDirectory()
        try migrateFiles(from: developmentDirectory, to: appGroupDirectory, named: fileNames)
    }

    static func migrateDevelopmentHistoryDatasetToAppGroupIfNeeded(
        primaryFileName: String,
        backupFileName: String,
        validate: (Data) throws -> Void
    ) throws {
        guard Bundle.main.bundleURL.pathExtension.lowercased() == "app" else { return }
        guard let appGroupDirectory = resolveAppGroupDirectory() else {
            throw SharedStorageError.appGroupUnavailable
        }

        let developmentDirectory = try developmentStorageDirectory()
        try migrateHistoryDataset(
            from: developmentDirectory,
            to: appGroupDirectory,
            primaryFileName: primaryFileName,
            backupFileName: backupFileName,
            validate: validate
        )
    }

    static func migrateFiles(from sourceDirectory: URL, to targetDirectory: URL, named fileNames: [String]) throws {
        guard sourceDirectory.standardizedFileURL != targetDirectory.standardizedFileURL else { return }

        try withExclusiveLock(storageDirectory: targetDirectory) { directory in
            for fileName in fileNames {
                let sourceURL = sourceDirectory.appendingPathComponent(fileName)
                let targetURL = directory.appendingPathComponent(fileName)

                guard FileManager.default.fileExists(atPath: sourceURL.path),
                      !FileManager.default.fileExists(atPath: targetURL.path) else {
                    continue
                }

                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            }
        }
    }

    static func migrateHistoryDataset(
        from sourceDirectory: URL,
        to targetDirectory: URL,
        primaryFileName: String,
        backupFileName: String,
        validate: (Data) throws -> Void
    ) throws {
        guard sourceDirectory.standardizedFileURL != targetDirectory.standardizedFileURL else { return }

        try withExclusiveLock(storageDirectory: targetDirectory) { directory in
            let targetPrimaryURL = directory.appendingPathComponent(primaryFileName)
            let targetBackupURL = directory.appendingPathComponent(backupFileName)
            let targetHasPrimary = FileManager.default.fileExists(atPath: targetPrimaryURL.path)
            let targetHasBackup = FileManager.default.fileExists(atPath: targetBackupURL.path)

            // A partial target dataset still belongs to the target. Its normal
            // recovery path must decide how to handle it; migration must never
            // combine it with an unrelated source file.
            guard !targetHasPrimary, !targetHasBackup else { return }

            let sourceURLs = [
                sourceDirectory.appendingPathComponent(primaryFileName),
                sourceDirectory.appendingPathComponent(backupFileName)
            ]
            var selectedPayload: Data?
            var lastValidationError: Error?

            for sourceURL in sourceURLs where FileManager.default.fileExists(atPath: sourceURL.path) {
                do {
                    let payload = try Data(contentsOf: sourceURL)
                    try validate(payload)
                    selectedPayload = payload
                    break
                } catch {
                    lastValidationError = error
                }
            }

            guard let selectedPayload else {
                if let lastValidationError {
                    throw lastValidationError
                }
                return
            }

            // Write the backup first. If the second atomic write fails, the
            // regular missing-primary recovery path can still restore it.
            try selectedPayload.write(to: targetBackupURL, options: [.atomic])
            try selectedPayload.write(to: targetPrimaryURL, options: [.atomic])
        }
    }

    static func withExclusiveLock<T>(
        storageDirectory: URL? = nil,
        _ operation: (URL) throws -> T
    ) throws -> T {
        processLock.lock()
        defer { processLock.unlock() }

        let directory = try storageDirectory ?? Self.storageDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let lockURL = directory.appendingPathComponent(lockFileName)
        let fileDescriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        guard Darwin.lockf(fileDescriptor, F_LOCK, 0) == 0 else {
            let lockError = errno
            _ = Darwin.close(fileDescriptor)
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(lockError))
        }
        defer {
            _ = Darwin.lockf(fileDescriptor, F_ULOCK, 0)
            _ = Darwin.close(fileDescriptor)
        }

        return try operation(directory)
    }

    private static func isWritableDirectory(_ directory: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let probeURL = directory.appendingPathComponent(".sitright-write-test-\(UUID().uuidString)")
            try Data().write(to: probeURL, options: [.atomic])
            try? FileManager.default.removeItem(at: probeURL)
            return true
        } catch {
            return false
        }
    }

    private static var isPackagedBundle: Bool {
        let pathExtension = Bundle.main.bundleURL.pathExtension.lowercased()
        return pathExtension == "app" || pathExtension == "appex"
    }

    private static func resolveAppGroupDirectory() -> URL? {
        for identifier in appGroupIdentifiers {
            guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier),
                  isWritableDirectory(directory) else {
                continue
            }

            return directory
        }

        return nil
    }

    private static func developmentStorageDirectory() throws -> URL {
        do {
            let supportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = supportURL.appendingPathComponent("SitRight", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            throw SharedStorageError.developmentDirectoryUnavailable(error.localizedDescription)
        }
    }
}
