import Foundation
import Observation

enum ConfigurationDirectoryAccessError: LocalizedError, Equatable {
    case unresolved
    case notWorkBenchFolder
    case notDirectory
    case bookmarkIsStale
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .unresolved:
            "Choose the WorkBench configuration folder first."
        case .notWorkBenchFolder:
            "Select a folder named WorkBench."
        case .notDirectory:
            "The selected location is not a folder."
        case .bookmarkIsStale:
            "Access to the WorkBench folder has expired. Select it again."
        case .accessDenied:
            "WorkBench could not access the selected folder."
        }
    }

}

protocol BookmarkDataStoring {
    func load() -> Data?
    func save(_ data: Data)
    func remove()
}

struct UserDefaultsBookmarkDataStore: BookmarkDataStoring {
    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "configurationDirectoryBookmark"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> Data? {
        defaults.data(forKey: key)
    }

    func save(_ data: Data) {
        defaults.set(data, forKey: key)
    }

    func remove() {
        defaults.removeObject(forKey: key)
    }
}

protocol DirectoryBookmarking {
    func createBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool)
}

struct FoundationDirectoryBookmarker: DirectoryBookmarking {
    func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }
}

@MainActor
@Observable
final class ConfigurationDirectoryAccess {
    enum Status: Equatable {
        case unresolved
        case needsSelection(message: String?)
        case ready(URL)
    }

    private(set) var status: Status = .unresolved

    private let bookmarkStore: any BookmarkDataStoring
    private let bookmarker: any DirectoryBookmarking
    private let fileManager: FileManager

    init(
        bookmarkStore: any BookmarkDataStoring = UserDefaultsBookmarkDataStore(),
        bookmarker: any DirectoryBookmarking = FoundationDirectoryBookmarker(),
        fileManager: FileManager = .default,
        initialStatus: Status = .unresolved
    ) {
        self.bookmarkStore = bookmarkStore
        self.bookmarker = bookmarker
        self.fileManager = fileManager
        status = initialStatus
    }

    func withConfigurationDirectoryAccess<Result>(
        _ operation: (URL) throws -> Result
    ) throws -> Result {
        guard case let .ready(url) = status else {
            throw ConfigurationDirectoryAccessError.unresolved
        }
        return try operation(url)
    }

    func restoreAccess() {
        guard let bookmarkData = bookmarkStore.load() else {
            status = .needsSelection(message: nil)
            return
        }

        do {
            let resolved = try bookmarker.resolveBookmark(bookmarkData)
            guard !resolved.isStale else {
                throw ConfigurationDirectoryAccessError.bookmarkIsStale
            }
            try Self.validateDirectory(resolved.url, fileManager: fileManager)
            try verifyReadWriteAccess(to: resolved.url)
            status = .ready(resolved.url)
        } catch {
            bookmarkStore.remove()
            status = .needsSelection(message: Self.message(for: error))
        }
    }

    func selectDirectory(_ url: URL) {
        do {
            try Self.validateDirectory(url, fileManager: fileManager)
            let bookmarkData = try bookmarker.createBookmark(for: url)
            try verifyReadWriteAccess(to: url)
            bookmarkStore.save(bookmarkData)
            status = .ready(url)
        } catch {
            status = .needsSelection(message: Self.message(for: error))
        }
    }

    static func validateDirectory(_ url: URL, fileManager: FileManager = .default) throws {
        guard url.lastPathComponent == "WorkBench" else {
            throw ConfigurationDirectoryAccessError.notWorkBenchFolder
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ConfigurationDirectoryAccessError.notDirectory
        }
    }

    private func verifyReadWriteAccess(to directory: URL) throws {
        let probeURL = directory.appending(
            path: ".workbench-access-probe-\(UUID().uuidString)",
            directoryHint: .notDirectory
        )
        let expectedData = Data("WorkBench access probe".utf8)

        defer { try? fileManager.removeItem(at: probeURL) }
        try expectedData.write(to: probeURL, options: .atomic)
        let actualData = try Data(contentsOf: probeURL)
        guard actualData == expectedData else {
            throw ConfigurationDirectoryAccessError.accessDenied
        }
        try fileManager.removeItem(at: probeURL)
    }

    private static func message(for error: Error) -> String {
        if let description = (error as? LocalizedError)?.errorDescription {
            return description
        }
        return "WorkBench could not access the selected folder. \(error.localizedDescription)"
    }
}
