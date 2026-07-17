import Foundation
import XCTest
@testable import WorkBench

@MainActor
final class ProjectWorkflowTests: XCTestCase {
    func testDraftDirtyStateDerivesFromPersistedValue() throws {
        let original = Project(name: "Original", resources: [])
        let workflow = try makeLoadedWorkflow(projects: [original])

        XCTAssertFalse(workflow.isDirty)
        try workflow.updateDraft { $0.name = "Edited" }
        XCTAssertTrue(workflow.isDirty)
        try workflow.updateDraft { $0.name = "Original" }
        XCTAssertFalse(workflow.isDirty)
    }

    func testSavePersistsDraftAndClearsDirtyState() throws {
        let original = Project(name: "Original", resources: [])
        let repository = RepositoryStub(projects: [original])
        let workflow = try makeLoadedWorkflow(repository: repository)
        try workflow.updateDraft { $0.name = "Saved" }

        try workflow.saveDraft()

        XCTAssertEqual(repository.savedProjects.map(\.name), ["Saved"])
        XCTAssertEqual(workflow.projects.map(\.name), ["Saved"])
        XCTAssertFalse(workflow.isDirty)
    }

    func testCancelLeavesDraftSelectionAndPendingActionUnchanged() throws {
        let first = Project(name: "First", resources: [])
        let second = Project(name: "Second", resources: [])
        let workflow = try makeLoadedWorkflow(projects: [first, second])
        try workflow.updateDraft { $0.name = "Edited" }

        XCTAssertEqual(try workflow.request(.select(second.id)), .needsUnsavedChangesDecision)
        XCTAssertEqual(try workflow.resolveUnsavedChanges(.cancel), .cancelled)

        XCTAssertEqual(workflow.selectedProjectID, first.id)
        XCTAssertEqual(workflow.draft?.name, "Edited")
        XCTAssertTrue(workflow.isDirty)
        XCTAssertNil(workflow.pendingAction)
    }

    func testDiscardRestoresPersistedValueBeforeSwitching() throws {
        let first = Project(name: "First", resources: [])
        let second = Project(name: "Second", resources: [])
        let workflow = try makeLoadedWorkflow(projects: [first, second])
        try workflow.updateDraft { $0.name = "Edited" }

        _ = try workflow.request(.select(second.id))
        let result = try workflow.resolveUnsavedChanges(.discard)

        XCTAssertEqual(result, .completed(.stayOpen))
        XCTAssertEqual(workflow.selectedProjectID, second.id)
        XCTAssertEqual(workflow.projects.first(where: { $0.id == first.id })?.name, "First")
        XCTAssertFalse(workflow.isDirty)
    }

    func testSuccessfulPromptSaveContinuesPendingQuit() throws {
        let original = Project(name: "Original", resources: [])
        let repository = RepositoryStub(projects: [original])
        let workflow = try makeLoadedWorkflow(repository: repository)
        try workflow.updateDraft { $0.name = "Saved" }

        XCTAssertEqual(try workflow.request(.quit), .needsUnsavedChangesDecision)
        XCTAssertEqual(try workflow.resolveUnsavedChanges(.save), .completed(.quit))

        XCTAssertEqual(repository.savedProjects.map(\.name), ["Saved"])
        XCTAssertFalse(workflow.isDirty)
        XCTAssertNil(workflow.pendingAction)
    }

    func testFailedPromptSaveKeepsDraftSelectionAndPendingAction() throws {
        let original = Project(name: "Original", resources: [])
        let repository = RepositoryStub(projects: [original])
        repository.saveError = RepositoryStub.ExpectedError()
        let workflow = try makeLoadedWorkflow(repository: repository)
        try workflow.updateDraft { $0.name = "Unsaved" }
        _ = try workflow.request(.closeWindow)

        XCTAssertThrowsError(try workflow.resolveUnsavedChanges(.save))

        XCTAssertEqual(workflow.selectedProjectID, original.id)
        XCTAssertEqual(workflow.draft?.name, "Unsaved")
        XCTAssertTrue(workflow.isDirty)
        XCTAssertEqual(workflow.pendingAction, .closeWindow)
    }

    func testReloadAfterDiscardReflectsExternalChanges() throws {
        let original = Project(name: "Original", resources: [])
        let repository = RepositoryStub(projects: [original])
        let workflow = try makeLoadedWorkflow(repository: repository)
        try workflow.updateDraft { $0.name = "GUI Edit" }
        repository.projects = [Project(id: original.id, name: "External Edit", resources: [])]

        _ = try workflow.request(.reload)
        _ = try workflow.resolveUnsavedChanges(.discard)

        XCTAssertEqual(workflow.draft?.name, "External Edit")
        XCTAssertFalse(workflow.isDirty)
    }

    func testDiscardingNewProjectReturnsToPriorSelection() throws {
        let original = Project(name: "Original", resources: [])
        let workflow = try makeLoadedWorkflow(projects: [original])

        XCTAssertEqual(try workflow.request(.create(name: "New")), .completed(.stayOpen))
        XCTAssertTrue(workflow.isDirty)
        XCTAssertEqual(workflow.draft?.name, "New")
        XCTAssertEqual(try workflow.request(.select(original.id)), .needsUnsavedChangesDecision)
        _ = try workflow.resolveUnsavedChanges(.discard)

        XCTAssertEqual(workflow.selectedProjectID, original.id)
        XCTAssertFalse(workflow.isDirty)
    }

    func testDuplicateUsesUniqueNameAndNewIdentifiers() throws {
        let original = Project.starter()
        let existingCopy = original.duplicated(named: "Starter Project Copy")
        let workflow = try makeLoadedWorkflow(projects: [original, existingCopy])

        _ = try workflow.request(.duplicate(original.id))
        let duplicate = try XCTUnwrap(workflow.draft)

        XCTAssertEqual(duplicate.name, "Starter Project Copy 2")
        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertTrue(Set(duplicate.resources.map(\.id)).isDisjoint(with: original.resources.map(\.id)))
        XCTAssertTrue(workflow.isDirty)
    }

    func testResourceMutationAndReorderingEnterDirtyStateAndPersist() throws {
        let original = Project.starter()
        let repository = RepositoryStub(projects: [original])
        let workflow = try makeLoadedWorkflow(repository: repository)

        try workflow.updateDraft { project in
            project.resources.swapAt(0, 2)
            project.resources[0].name = "Renamed Folder"
            project.resources.remove(at: 1)
            project.resources.append(
                Resource(
                    name: "Added Terminal",
                    payload: .terminalSession(TerminalSession(workingDirectory: "/tmp"))
                )
            )
        }

        XCTAssertTrue(workflow.isDirty)
        try workflow.saveDraft()
        XCTAssertEqual(repository.savedProjects.last?.resources.map(\.name), [
            "Renamed Folder", "Web", "Added Terminal"
        ])
    }

    func testDeleteFailureLeavesWorkflowStateUnchanged() throws {
        let original = Project(name: "Original", resources: [])
        let repository = RepositoryStub(projects: [original])
        repository.deleteError = RepositoryStub.ExpectedError()
        let workflow = try makeLoadedWorkflow(repository: repository)

        XCTAssertThrowsError(try workflow.request(.delete(original.id)))

        XCTAssertEqual(workflow.projects, [original])
        XCTAssertEqual(workflow.draft, original)
        XCTAssertFalse(workflow.isDirty)
    }

    func testCreateRejectsCaseInsensitiveDuplicateName() throws {
        let original = Project(name: "Original", resources: [])
        let workflow = try makeLoadedWorkflow(projects: [original])

        XCTAssertThrowsError(try workflow.request(.create(name: " original "))) { error in
            XCTAssertTrue(error is ProjectWorkflowError)
        }
    }

    private func makeLoadedWorkflow(projects: [Project]) throws -> ProjectWorkflow {
        try makeLoadedWorkflow(repository: RepositoryStub(projects: projects))
    }

    private func makeLoadedWorkflow(repository: RepositoryStub) throws -> ProjectWorkflow {
        let workflow = ProjectWorkflow(repository: repository)
        try workflow.load()
        return workflow
    }
}

@MainActor
private final class RepositoryStub: ProjectRepositorying {
    struct ExpectedError: Error {}

    var projects: [Project]
    var issues: [ProjectFileIssue] = []
    var saveError: Error?
    var deleteError: Error?
    private(set) var savedProjects: [Project] = []

    init(projects: [Project]) {
        self.projects = projects
    }

    func load() throws -> ProjectRepositorySnapshot {
        ProjectRepositorySnapshot(projects: projects, issues: issues)
    }

    func save(_ project: Project) throws {
        if let saveError { throw saveError }
        savedProjects.append(project)
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
    }

    func delete(_ project: Project) throws {
        if let deleteError { throw deleteError }
        projects.removeAll { $0.id == project.id }
    }
}
