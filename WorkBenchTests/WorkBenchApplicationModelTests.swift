import XCTest
@testable import WorkBench

@MainActor
final class WorkBenchApplicationModelTests: XCTestCase {
    func testCreateProjectUsesUniqueDraftName() throws {
        let workflow = try makeWorkflow(projects: [
            Project(name: "Untitled Project", resources: []),
            Project(name: "Untitled Project 2", resources: [])
        ])
        let model = WorkBenchApplicationModel(workflow: workflow)

        model.createProject()

        XCTAssertEqual(workflow.draft?.name, "Untitled Project 3")
        XCTAssertTrue(workflow.isDirty)
    }

    func testResourceCommandsMutateOnlyTheDraft() throws {
        let original = Project(name: "Project", resources: [])
        let workflow = try makeWorkflow(projects: [original])
        let model = WorkBenchApplicationModel(workflow: workflow)

        model.addResource(.terminalSession(TerminalSession(workingDirectory: "~/")))
        let addedID = try XCTUnwrap(model.selectedResourceID)

        XCTAssertEqual(workflow.draft?.resources.count, 1)
        XCTAssertTrue(workflow.isDirty)
        XCTAssertTrue(workflow.projects[0].resources.isEmpty)

        model.removeSelectedResource()
        XCTAssertNil(model.selectedResourceID)
        XCTAssertTrue(workflow.draft?.resources.isEmpty == true)
        XCTAssertEqual(workflow.draft, original)
        XCTAssertFalse(workflow.isDirty)
        XCTAssertNotNil(addedID)
    }

    func testDirtyProjectSelectionPresentsSharedUnsavedDialog() throws {
        let first = Project(name: "First", resources: [])
        let second = Project(name: "Second", resources: [])
        let workflow = try makeWorkflow(projects: [first, second])
        let model = WorkBenchApplicationModel(workflow: workflow)
        model.updateDraft { $0.name = "Edited" }

        model.selectProject(second.id)

        XCTAssertTrue(model.showsUnsavedChangesDialog)
        XCTAssertEqual(workflow.pendingAction, .select(second.id))

        model.resolveUnsavedChanges(.cancel)
        XCTAssertFalse(model.showsUnsavedChangesDialog)
        XCTAssertEqual(workflow.draft?.name, "Edited")
        XCTAssertEqual(workflow.selectedProjectID, first.id)
    }

    func testOpenInvalidDraftPresentsConsolidatedLaunchReport() throws {
        let invalid = Project(
            name: "Invalid",
            resources: [Resource(name: "Empty Browser", payload: .browserWindow(BrowserWindow(tabs: [])))]
        )
        let workflow = try makeWorkflow(projects: [invalid])
        let model = WorkBenchApplicationModel(workflow: workflow, launcher: ProjectLauncher())

        model.openSelectedProject()

        XCTAssertEqual(model.launchReport?.projectID, invalid.id)
        XCTAssertFalse(model.launchReport?.validationIssues.isEmpty ?? true)
        XCTAssertTrue(model.launchReport?.results.isEmpty == true)
    }

    private func makeWorkflow(projects: [Project]) throws -> ProjectWorkflow {
        let workflow = ProjectWorkflow(repository: ApplicationModelRepositoryStub(projects: projects))
        try workflow.load()
        return workflow
    }
}

@MainActor
private final class ApplicationModelRepositoryStub: ProjectRepositorying {
    var projects: [Project]

    init(projects: [Project]) {
        self.projects = projects
    }

    func load() throws -> ProjectRepositorySnapshot {
        ProjectRepositorySnapshot(projects: projects, issues: [])
    }

    func save(_ project: Project) throws {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
    }

    func delete(_ project: Project) throws {
        projects.removeAll { $0.id == project.id }
    }
}
