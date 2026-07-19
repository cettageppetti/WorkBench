import Foundation
import Observation

enum ConfigurationDirectoryAccessError: LocalizedError, Equatable {
    case unresolved
    case notDirectory
    case legacyBookmarkIsStale
    case migrationDestinationNotEmpty
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .unresolved:
            "WorkBench has not finished preparing its Project library."
        case .notDirectory:
            "The WorkBench Project library location is not a folder."
        case .legacyBookmarkIsStale:
            "The previous WorkBench configuration folder is no longer available."
        case .migrationDestinationNotEmpty:
            "The new WorkBench Project library already contains files, so migration was not attempted."
        case .accessDenied:
            "WorkBench could not read or write its Project library."
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

    func load() -> Data? { defaults.data(forKey: key) }
    func save(_ data: Data) { defaults.set(data, forKey: key) }
    func remove() { defaults.removeObject(forKey: key) }
}

protocol DirectoryBookmarking {
    func createBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool)
}

struct FoundationDirectoryBookmarker: DirectoryBookmarking {
    func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
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

protocol ProjectLibraryLocating {
    func projectLibraryURL() throws -> URL
}

struct ApplicationSupportProjectLibraryLocator: ProjectLibraryLocating {
    func projectLibraryURL() throws -> URL {
        URL.applicationSupportDirectory
            .appending(path: "WorkBench", directoryHint: .isDirectory)
            .appending(path: "Projects", directoryHint: .isDirectory)
    }
}

protocol MigrationCompletionStoring {
    var isComplete: Bool { get }
    func markComplete()
}

struct UserDefaultsMigrationCompletionStore: MigrationCompletionStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "applicationSupportMigrationCompleted") {
        self.defaults = defaults
        self.key = key
    }

    var isComplete: Bool { defaults.bool(forKey: key) }
    func markComplete() { defaults.set(true, forKey: key) }
}

@MainActor
@Observable
final class ConfigurationDirectoryAccess {
    enum Status: Equatable {
        case unresolved
        case migrationAvailable(legacyDirectory: URL)
        case failed(message: String)
        case ready(URL)
    }

    private(set) var status: Status = .unresolved

    private let locator: any ProjectLibraryLocating
    private let legacyBookmarkStore: any BookmarkDataStoring
    private let bookmarker: any DirectoryBookmarking
    private let migrationStore: any MigrationCompletionStoring
    private let fileManager: FileManager

    init(
        locator: any ProjectLibraryLocating = ApplicationSupportProjectLibraryLocator(),
        legacyBookmarkStore: any BookmarkDataStoring = UserDefaultsBookmarkDataStore(),
        bookmarker: any DirectoryBookmarking = FoundationDirectoryBookmarker(),
        migrationStore: any MigrationCompletionStoring = UserDefaultsMigrationCompletionStore(),
        fileManager: FileManager = .default,
        initialStatus: Status = .unresolved
    ) {
        self.locator = locator
        self.legacyBookmarkStore = legacyBookmarkStore
        self.bookmarker = bookmarker
        self.migrationStore = migrationStore
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

    func prepare() {
        do {
            let destination = try locator.projectLibraryURL()
            try createParentDirectory(for: destination)

            if try directoryExists(destination) {
                try verifyReadWriteAccess(to: destination)
                let containsProjects = try containsProjectFiles(destination)
                if migrationStore.isComplete || containsProjects {
                    status = .ready(destination)
                    return
                }
            }

            if !migrationStore.isComplete,
               let legacyDirectory = try resolveLegacyDirectory() {
                status = .migrationAvailable(legacyDirectory: legacyDirectory)
                return
            }

            try createAndVerifyDirectory(destination)
            status = .ready(destination)
        } catch {
            status = .failed(message: Self.message(for: error))
        }
    }

    func migrateLegacyProjects() {
        guard case let .migrationAvailable(legacyDirectory) = status else { return }
        do {
            let destination = try locator.projectLibraryURL()
            if try directoryExists(destination) {
                guard try fileManager.contentsOfDirectory(atPath: destination.path).isEmpty else {
                    throw ConfigurationDirectoryAccessError.migrationDestinationNotEmpty
                }
                try fileManager.removeItem(at: destination)
            }

            let staging = destination.deletingLastPathComponent().appending(
                path: "Projects.migration-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
            do {
                for source in try legacyProjectFiles(in: legacyDirectory) {
                    try fileManager.copyItem(
                        at: source,
                        to: staging.appending(path: source.lastPathComponent)
                    )
                }
                try fileManager.moveItem(at: staging, to: destination)
            } catch {
                try? fileManager.removeItem(at: staging)
                throw error
            }

            try verifyReadWriteAccess(to: destination)
            migrationStore.markComplete()
            status = .ready(destination)
        } catch {
            status = .failed(message: "WorkBench could not import the previous Project library. \(Self.message(for: error))")
        }
    }

    func startWithEmptyLibrary() {
        do {
            let destination = try locator.projectLibraryURL()
            try createParentDirectory(for: destination)
            try createAndVerifyDirectory(destination)
            migrationStore.markComplete()
            status = .ready(destination)
        } catch {
            status = .failed(message: Self.message(for: error))
        }
    }

    private func resolveLegacyDirectory() throws -> URL? {
        guard let bookmarkData = legacyBookmarkStore.load() else { return nil }
        do {
            let resolved = try bookmarker.resolveBookmark(bookmarkData)
            guard !resolved.isStale else {
                throw ConfigurationDirectoryAccessError.legacyBookmarkIsStale
            }
            guard try directoryExists(resolved.url) else {
                throw ConfigurationDirectoryAccessError.notDirectory
            }
            return resolved.url
        } catch {
            legacyBookmarkStore.remove()
            if error as? ConfigurationDirectoryAccessError == .legacyBookmarkIsStale {
                return nil
            }
            throw error
        }
    }

    private func legacyProjectFiles(in directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func containsProjectFiles(_ directory: URL) throws -> Bool {
        try !legacyProjectFiles(in: directory).isEmpty
    }

    private func createParentDirectory(for destination: URL) throws {
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private func createAndVerifyDirectory(_ directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try directoryExists(directory) else {
            throw ConfigurationDirectoryAccessError.notDirectory
        }
        try verifyReadWriteAccess(to: directory)
    }

    private func directoryExists(_ url: URL) throws -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        guard isDirectory.boolValue else { throw ConfigurationDirectoryAccessError.notDirectory }
        return true
    }

    private func verifyReadWriteAccess(to directory: URL) throws {
        let probeURL = directory.appending(path: ".workbench-access-probe-\(UUID().uuidString)")
        let expectedData = Data("WorkBench access probe".utf8)
        defer { try? fileManager.removeItem(at: probeURL) }
        do {
            try expectedData.write(to: probeURL, options: .atomic)
            guard try Data(contentsOf: probeURL) == expectedData else {
                throw ConfigurationDirectoryAccessError.accessDenied
            }
            try fileManager.removeItem(at: probeURL)
        } catch {
            throw ConfigurationDirectoryAccessError.accessDenied
        }
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? "WorkBench could not prepare its Project library. \(error.localizedDescription)"
    }
}
