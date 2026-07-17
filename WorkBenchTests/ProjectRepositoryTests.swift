import Foundation
import XCTest
@testable import WorkBench

@MainActor
final class ProjectRepositoryTests: XCTestCase {
    // XCTest invokes lifecycle overrides outside the test class's MainActor context.
    nonisolated(unsafe) private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
        temporaryRoot = nil
    }

    func testFirstLoadCreatesExactlyOneStarterProject() throws {
        let state = InitializationStoreStub()
        let repository = makeRepository(initializationStore: state)

        let snapshot = try repository.load()
        let secondSnapshot = try repository.load()

        XCTAssertEqual(snapshot.projects.count, 1)
        XCTAssertEqual(snapshot.projects[0].name, "Starter Project")
        XCTAssertEqual(secondSnapshot.projects, snapshot.projects)
        XCTAssertTrue(state.isInitialized)
        XCTAssertEqual(try jsonFiles().count, 1)
    }

    func testInitializedEmptyRepositoryDoesNotRecreateStarterProject() throws {
        let repository = makeRepository(initializationStore: InitializationStoreStub(isInitialized: true))

        let snapshot = try repository.load()

        XCTAssertTrue(snapshot.projects.isEmpty)
        XCTAssertTrue(snapshot.issues.isEmpty)
        XCTAssertTrue(try jsonFiles().isEmpty)
    }

    func testFailedStarterSaveDoesNotMarkRepositoryInitialized() throws {
        let state = InitializationStoreStub()
        let repository = makeRepository(initializationStore: state, writer: FailingWriter())

        XCTAssertThrowsError(try repository.load())
        XCTAssertFalse(state.isInitialized)
        XCTAssertTrue(try jsonFiles().isEmpty)
    }

    func testMalformedAndInvalidFilesRemainVisibleAsIssues() throws {
        try Data("{not json".utf8).write(to: temporaryRoot.appending(path: "malformed.json"))
        let invalid = Project(name: " ", resources: [])
        try encode(invalid).write(to: temporaryRoot.appending(path: invalid.filename))
        let repository = makeRepository(initializationStore: InitializationStoreStub(isInitialized: true))

        let snapshot = try repository.load()

        XCTAssertTrue(snapshot.projects.isEmpty)
        XCTAssertEqual(snapshot.issues.count, 2)
        XCTAssertEqual(Set(snapshot.issues.map { $0.fileURL.lastPathComponent }), [
            "malformed.json", invalid.filename
        ])
    }

    func testLoadReportsBothFilesWithDuplicateNames() throws {
        let first = Project(name: "Example", resources: [])
        let second = Project(name: " example ", resources: [])
        try encode(first).write(to: temporaryRoot.appending(path: first.filename))
        try encode(second).write(to: temporaryRoot.appending(path: second.filename))

        let snapshot = try makeRepository(
            initializationStore: InitializationStoreStub(isInitialized: true)
        ).load()

        XCTAssertTrue(snapshot.projects.isEmpty)
        XCTAssertEqual(snapshot.issues.count, 2)
    }

    func testMisnamedProjectFileRemainsVisibleAsIssue() throws {
        let project = Project(name: "Misnamed", resources: [])
        try encode(project).write(to: temporaryRoot.appending(path: "friendly-name.json"))

        let snapshot = try makeRepository(
            initializationStore: InitializationStoreStub(isInitialized: true)
        ).load()

        XCTAssertTrue(snapshot.projects.isEmpty)
        XCTAssertEqual(snapshot.issues.count, 1)
        XCTAssertTrue(snapshot.issues[0].message.contains(project.filename))
    }

    func testSaveUsesStableFilenameAndReloadReflectsExternalEdit() throws {
        let state = InitializationStoreStub(isInitialized: true)
        let repository = makeRepository(initializationStore: state)
        var project = Project(name: "Original", resources: [])
        try repository.save(project)
        let filename = project.filename

        project.name = "Externally Edited"
        try encode(project).write(to: temporaryRoot.appending(path: filename), options: .atomic)
        let snapshot = try repository.load()

        XCTAssertEqual(snapshot.projects.map(\.name), ["Externally Edited"])
        XCTAssertEqual(try jsonFiles().map(\.lastPathComponent), [filename])
    }

    func testUnknownResourceSurvivesRepositoryLoadAndSave() throws {
        let projectID = UUID()
        let resourceID = UUID()
        let originalData = Data("""
        {
          "schemaVersion": 1,
          "id": "\(projectID)",
          "name": "Future",
          "resources": [{
            "id": "\(resourceID)",
            "type": "future-resource",
            "name": "Future Resource",
            "payload": {"large": 9007199254740993, "enabled": true}
          }]
        }
        """.utf8)
        let projectFilename = "\(projectID.uuidString.lowercased()).json"
        let fileURL = temporaryRoot.appending(path: projectFilename)
        try originalData.write(to: fileURL)
        let repository = makeRepository(initializationStore: InitializationStoreStub(isInitialized: true))
        let project = try XCTUnwrap(repository.load().projects.first)

        try repository.save(project)

        let savedData = try Data(contentsOf: temporaryRoot.appending(path: project.filename))
        XCTAssertEqual(
            try JSONDecoder().decode(JSONValue.self, from: savedData),
            try JSONDecoder().decode(JSONValue.self, from: originalData)
        )
    }

    func testFailedSaveLeavesPreviousFileUsable() throws {
        let state = InitializationStoreStub(isInitialized: true)
        let workingRepository = makeRepository(initializationStore: state)
        var project = Project(name: "Saved", resources: [])
        try workingRepository.save(project)
        let originalData = try Data(contentsOf: temporaryRoot.appending(path: project.filename))

        project.name = "Failed Update"
        let failingRepository = makeRepository(
            initializationStore: state,
            writer: FailingWriter()
        )

        XCTAssertThrowsError(try failingRepository.save(project))
        XCTAssertEqual(
            try Data(contentsOf: temporaryRoot.appending(path: project.filename)),
            originalData
        )
        XCTAssertEqual(try workingRepository.load().projects.map(\.name), ["Saved"])
    }

    func testDeleteRemovesOnlySelectedProject() throws {
        let repository = makeRepository(initializationStore: InitializationStoreStub(isInitialized: true))
        let first = Project(name: "First", resources: [])
        let second = Project(name: "Second", resources: [])
        try repository.save(first)
        try repository.save(second)

        try repository.delete(first)

        XCTAssertEqual(try repository.load().projects.map(\.name), ["Second"])
        XCTAssertEqual(try jsonFiles().map(\.lastPathComponent), [second.filename])
    }

    func testDeleteFailureDoesNotChangeRemainingRepositoryState() throws {
        let repository = makeRepository(initializationStore: InitializationStoreStub(isInitialized: true))
        let existing = Project(name: "Existing", resources: [])
        let missing = Project(name: "Missing", resources: [])
        try repository.save(existing)

        XCTAssertThrowsError(try repository.delete(missing))

        XCTAssertEqual(try repository.load().projects, [existing])
        XCTAssertEqual(try jsonFiles().map(\.lastPathComponent), [existing.filename])
    }

    func testDuplicateCreatesNewProjectAndResourceIdentifiers() {
        let original = Project.starter()

        let duplicate = original.duplicated(named: "Starter Project Copy")

        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertEqual(duplicate.name, "Starter Project Copy")
        XCTAssertEqual(duplicate.resources.map(\.payload), original.resources.map(\.payload))
        XCTAssertTrue(Set(duplicate.resources.map(\.id)).isDisjoint(with: original.resources.map(\.id)))
    }

    private func makeRepository(
        initializationStore: any RepositoryInitializationStoring,
        writer: any ProjectDataWriting = AtomicProjectDataWriter()
    ) -> ProjectRepository {
        ProjectRepository(
            directoryProvider: FixedConfigurationDirectory(url: temporaryRoot),
            initializationStore: initializationStore,
            writer: writer
        )
    }

    private func encode(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    private func jsonFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: temporaryRoot,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

private final class InitializationStoreStub: RepositoryInitializationStoring {
    private(set) var isInitialized: Bool

    init(isInitialized: Bool = false) {
        self.isInitialized = isInitialized
    }

    func markInitialized() {
        isInitialized = true
    }
}

private struct FailingWriter: ProjectDataWriting {
    struct ExpectedError: Error {}

    func write(_ data: Data, to url: URL) throws {
        throw ExpectedError()
    }
}
