import Foundation

enum SharedStorage {
    static let appGroupIdentifiers = [
        "973KFG9CL9.com.leon.SitRight"
    ]

    static func storageDirectory() throws -> URL {
        for identifier in appGroupIdentifiers {
            guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
                continue
            }

            guard isWritableDirectory(directory) else {
                continue
            }

            return directory
        }

        let supportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = supportURL.appendingPathComponent("SitRight", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func readableFileURL(named fileName: String) -> URL? {
        for identifier in appGroupIdentifiers {
            guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
                continue
            }

            let url = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        if let directory = try? storageDirectory() {
            let url = directory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
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
}
