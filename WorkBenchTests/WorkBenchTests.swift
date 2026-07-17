import XCTest
@testable import WorkBench

@MainActor
final class WorkBenchTests: XCTestCase {
    func testApplicationTargetLoads() {
        XCTAssertTrue(true)
    }

    func testMissingBookmarkRequestsSelection() {
        let access = ConfigurationDirectoryAccess(
            bookmarkStore: BookmarkStoreStub(),
            bookmarker: BookmarkerStub()
        )

        access.restoreAccess()

        XCTAssertEqual(access.status, .needsSelection(message: nil))
    }

    func testValidBookmarkRestoresAccess() throws {
        let directory = try makeWorkBenchDirectory()
        let store = BookmarkStoreStub(data: Data("bookmark".utf8))
        let bookmarker = BookmarkerStub(resolvedURL: directory)
        let access = ConfigurationDirectoryAccess(
            bookmarkStore: store,
            bookmarker: bookmarker
        )

        access.restoreAccess()

        XCTAssertEqual(access.status, .ready(directory))
        XCTAssertEqual(bookmarker.startedURLs, [directory])
        XCTAssertEqual(bookmarker.stoppedURLs, [directory])
        XCTAssertFalse(store.didRemove)
    }

    func testStaleBookmarkRequestsSelectionAndRemovesStoredBookmark() throws {
        let directory = try makeWorkBenchDirectory()
        let store = BookmarkStoreStub(data: Data("bookmark".utf8))
        let access = ConfigurationDirectoryAccess(
            bookmarkStore: store,
            bookmarker: BookmarkerStub(resolvedURL: directory, isStale: true)
        )

        access.restoreAccess()

        XCTAssertEqual(
            access.status,
            .needsSelection(message: "Access to the WorkBench folder has expired. Select it again.")
        )
        XCTAssertTrue(store.didRemove)
    }

    func testSelectingDirectoryPersistsBookmark() throws {
        let directory = try makeWorkBenchDirectory()
        let store = BookmarkStoreStub()
        let bookmarker = BookmarkerStub(createdData: Data("created".utf8))
        let access = ConfigurationDirectoryAccess(
            bookmarkStore: store,
            bookmarker: bookmarker
        )

        access.selectDirectory(directory)

        XCTAssertEqual(access.status, .ready(directory))
        XCTAssertEqual(store.data, Data("created".utf8))
        XCTAssertEqual(bookmarker.stoppedURLs, [directory])
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains { $0.hasPrefix(".workbench-access-probe-") }
        )
    }

    func testRejectsFolderWithUnexpectedName() throws {
        let directory = FileManager.default.temporaryDirectory

        XCTAssertThrowsError(try ConfigurationDirectoryAccess.validateDirectory(directory)) { error in
            XCTAssertEqual(
                error as? ConfigurationDirectoryAccessError,
                .notWorkBenchFolder
            )
        }
    }

    private func makeWorkBenchDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let directory = root.appending(path: "WorkBench", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return directory
    }
}

private final class BookmarkStoreStub: BookmarkDataStoring {
    var data: Data?
    private(set) var didRemove = false

    init(data: Data? = nil) {
        self.data = data
    }

    func load() -> Data? {
        data
    }

    func save(_ data: Data) {
        self.data = data
    }

    func remove() {
        didRemove = true
        data = nil
    }
}

private final class BookmarkerStub: SecurityScopedBookmarking {
    let createdData: Data
    let resolvedURL: URL
    let isStale: Bool
    private(set) var startedURLs: [URL] = []
    private(set) var stoppedURLs: [URL] = []

    init(
        createdData: Data = Data(),
        resolvedURL: URL = FileManager.default.temporaryDirectory,
        isStale: Bool = false
    ) {
        self.createdData = createdData
        self.resolvedURL = resolvedURL
        self.isStale = isStale
    }

    func createBookmark(for url: URL) throws -> Data {
        createdData
    }

    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        (resolvedURL, isStale)
    }

    func startAccessing(_ url: URL) -> Bool {
        startedURLs.append(url)
        return true
    }

    func stopAccessing(_ url: URL) {
        stoppedURLs.append(url)
    }
}
