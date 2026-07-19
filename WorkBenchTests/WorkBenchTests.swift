import XCTest
@testable import WorkBench

@MainActor
final class WorkBenchTests: XCTestCase {
    func testApplicationTargetLoads() {
        XCTAssertTrue(true)
    }

    func testCleanPreparationCreatesApplicationSupportProjectLibrary() throws {
        let root = try makeTemporaryDirectory()
        let destination = root.appending(path: "WorkBench/Projects", directoryHint: .isDirectory)
        let access = ConfigurationDirectoryAccess(
            locator: ProjectLibraryLocatorStub(url: destination),
            legacyBookmarkStore: BookmarkStoreStub(),
            migrationStore: MigrationStoreStub()
        )

        access.prepare()

        XCTAssertEqual(access.status, .ready(destination))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: destination.path)
                .contains { $0.hasPrefix(".workbench-access-probe-") }
        )
    }

    func testLegacyProjectsAreOfferedAndCopiedWithoutChangingSource() throws {
        let root = try makeTemporaryDirectory()
        let legacy = root.appending(path: "Documents/WorkBench", directoryHint: .isDirectory)
        let destination = root.appending(path: "Library/Application Support/WorkBench/Projects")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let projectURL = legacy.appending(path: "project.json")
        let invalidURL = legacy.appending(path: "broken.json")
        try Data("project".utf8).write(to: projectURL)
        try Data("broken".utf8).write(to: invalidURL)
        try Data("ignored".utf8).write(to: legacy.appending(path: "notes.txt"))
        let migrationStore = MigrationStoreStub()
        let access = ConfigurationDirectoryAccess(
            locator: ProjectLibraryLocatorStub(url: destination),
            legacyBookmarkStore: BookmarkStoreStub(data: Data("bookmark".utf8)),
            bookmarker: BookmarkerStub(resolvedURL: legacy),
            migrationStore: migrationStore
        )

        access.prepare()
        XCTAssertEqual(access.status, .migrationAvailable(legacyDirectory: legacy))

        access.migrateLegacyProjects()

        XCTAssertEqual(access.status, .ready(destination))
        XCTAssertTrue(migrationStore.isComplete)
        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "project.json")), Data("project".utf8))
        XCTAssertEqual(try Data(contentsOf: destination.appending(path: "broken.json")), Data("broken".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appending(path: "notes.txt").path))
        XCTAssertEqual(try Data(contentsOf: projectURL), Data("project".utf8))
        XCTAssertEqual(try Data(contentsOf: invalidURL), Data("broken".utf8))
    }

    func testExistingInternalProjectsBypassLegacyMigration() throws {
        let root = try makeTemporaryDirectory()
        let destination = root.appending(path: "WorkBench/Projects", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: destination.appending(path: "existing.json"))
        let bookmarker = BookmarkerStub(resolvedURL: root.appending(path: "Legacy"))
        let access = ConfigurationDirectoryAccess(
            locator: ProjectLibraryLocatorStub(url: destination),
            legacyBookmarkStore: BookmarkStoreStub(data: Data("bookmark".utf8)),
            bookmarker: bookmarker,
            migrationStore: MigrationStoreStub()
        )

        access.prepare()

        XCTAssertEqual(access.status, .ready(destination))
        XCTAssertEqual(bookmarker.resolveCount, 0)
    }

    func testStartingEmptyLeavesLegacyFilesUntouchedAndCompletesMigration() throws {
        let root = try makeTemporaryDirectory()
        let legacy = root.appending(path: "Legacy", directoryHint: .isDirectory)
        let destination = root.appending(path: "WorkBench/Projects", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let source = legacy.appending(path: "project.json")
        try Data("legacy".utf8).write(to: source)
        let migrationStore = MigrationStoreStub()
        let access = ConfigurationDirectoryAccess(
            locator: ProjectLibraryLocatorStub(url: destination),
            legacyBookmarkStore: BookmarkStoreStub(data: Data("bookmark".utf8)),
            bookmarker: BookmarkerStub(resolvedURL: legacy),
            migrationStore: migrationStore
        )
        access.prepare()

        access.startWithEmptyLibrary()

        XCTAssertEqual(access.status, .ready(destination))
        XCTAssertTrue(migrationStore.isComplete)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: source), Data("legacy".utf8))
    }

    func testStaleLegacyBookmarkIsRemovedAndCleanLibraryIsPrepared() throws {
        let root = try makeTemporaryDirectory()
        let destination = root.appending(path: "WorkBench/Projects", directoryHint: .isDirectory)
        let bookmarkStore = BookmarkStoreStub(data: Data("bookmark".utf8))
        let access = ConfigurationDirectoryAccess(
            locator: ProjectLibraryLocatorStub(url: destination),
            legacyBookmarkStore: bookmarkStore,
            bookmarker: BookmarkerStub(resolvedURL: root, isStale: true),
            migrationStore: MigrationStoreStub()
        )

        access.prepare()

        XCTAssertEqual(access.status, .ready(destination))
        XCTAssertTrue(bookmarkStore.didRemove)
    }

    func testMigrationRefusesToOverwriteDestinationCreatedAfterOffer() throws {
        let root = try makeTemporaryDirectory()
        let legacy = root.appending(path: "Legacy", directoryHint: .isDirectory)
        let destination = root.appending(path: "WorkBench/Projects", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacy.appending(path: "project.json"))
        let access = ConfigurationDirectoryAccess(
            locator: ProjectLibraryLocatorStub(url: destination),
            legacyBookmarkStore: BookmarkStoreStub(data: Data("bookmark".utf8)),
            bookmarker: BookmarkerStub(resolvedURL: legacy),
            migrationStore: MigrationStoreStub()
        )
        access.prepare()
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: destination.appending(path: "existing.json"))

        access.migrateLegacyProjects()

        guard case let .failed(message) = access.status else {
            return XCTFail("Expected migration failure")
        }
        XCTAssertTrue(message.contains("already contains files"))
        XCTAssertEqual(
            try Data(contentsOf: destination.appending(path: "existing.json")),
            Data("existing".utf8)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private struct ProjectLibraryLocatorStub: ProjectLibraryLocating {
    let url: URL
    func projectLibraryURL() throws -> URL { url }
}

private final class MigrationStoreStub: MigrationCompletionStoring {
    var isComplete: Bool
    init(isComplete: Bool = false) { self.isComplete = isComplete }
    func markComplete() { isComplete = true }
}

private final class BookmarkStoreStub: BookmarkDataStoring {
    var data: Data?
    private(set) var didRemove = false

    init(data: Data? = nil) { self.data = data }
    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
    func remove() {
        didRemove = true
        data = nil
    }
}

private final class BookmarkerStub: DirectoryBookmarking {
    let resolvedURL: URL
    let isStale: Bool
    private(set) var resolveCount = 0

    init(resolvedURL: URL, isStale: Bool = false) {
        self.resolvedURL = resolvedURL
        self.isStale = isStale
    }

    func createBookmark(for url: URL) throws -> Data { Data() }
    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        resolveCount += 1
        return (resolvedURL, isStale)
    }
}
