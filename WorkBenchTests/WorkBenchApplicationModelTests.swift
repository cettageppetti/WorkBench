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

    func testChromeResourceUsesDistinctTypeAndDefaultName() throws {
        let workflow = try makeWorkflow(projects: [Project(name: "Project", resources: [])])
        let model = WorkBenchApplicationModel(workflow: workflow)

        model.addResource(.chromeWindow(BrowserWindow(tabs: ["https://google.com"])))

        XCTAssertEqual(workflow.draft?.resources.first?.name, "Chrome Window")
        XCTAssertEqual(workflow.draft?.resources.first?.type, "chrome-window")
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

    func testOpenInvalidDraftPresentsConsolidatedLaunchReport() async throws {
        let invalid = Project(
            name: "Invalid",
            resources: [Resource(name: "Empty Browser", payload: .browserWindow(BrowserWindow(tabs: [])))]
        )
        let workflow = try makeWorkflow(projects: [invalid])
        let model = WorkBenchApplicationModel(workflow: workflow, launcher: ProjectLauncher())

        await model.openSelectedProject()

        XCTAssertEqual(model.launchReport?.projectID, invalid.id)
        XCTAssertFalse(model.launchReport?.validationIssues.isEmpty ?? true)
        XCTAssertTrue(model.launchReport?.results.isEmpty == true)
    }

    func testProjectWithoutDestinationLaunchesWithoutAeroSpace() async throws {
        let recorder = LaunchPreflightRecorder()
        let project = Project(
            name: "No Placement",
            resources: [Resource(name: "Browser", payload: .browserWindow(BrowserWindow(tabs: ["https://example.com"])))]
        )
        let model = try makeModel(project: project, recorder: recorder, integrationEnabled: false)

        await model.openSelectedProject()

        XCTAssertEqual(recorder.events, ["resource"])
        XCTAssertNil(model.pendingLaunchPlacementFailure)
    }

    func testEnabledDestinationActivatesBeforeResourcesLaunch() async throws {
        let recorder = LaunchPreflightRecorder()
        var project = Project(
            name: "Placed",
            resources: [Resource(name: "Browser", payload: .browserWindow(BrowserWindow(tabs: ["https://example.com"])))]
        )
        project.launchDestination = .aeroSpaceWorkspace("2")
        let model = try makeModel(project: project, recorder: recorder, integrationEnabled: true)

        await model.openSelectedProject()

        XCTAssertEqual(recorder.events, ["workspace:2", "resource"])
        XCTAssertNil(model.pendingLaunchPlacementFailure)
    }

    func testDisabledIntegrationRequiresExplicitRecoveryBeforeLaunching() async throws {
        let recorder = LaunchPreflightRecorder()
        var project = Project(name: "Placed", resources: [browserResource()])
        project.launchDestination = .aeroSpaceWorkspace("2")
        let model = try makeModel(project: project, recorder: recorder, integrationEnabled: false)

        await model.openSelectedProject()

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(model.pendingLaunchPlacementFailure?.reason, .integrationDisabled)

        model.openPendingProjectWithoutPlacement()

        XCTAssertEqual(recorder.events, ["resource"])
        XCTAssertNil(model.pendingLaunchPlacementFailure)
    }

    func testActivationFailureCanBeCancelledWithoutLaunching() async throws {
        let recorder = LaunchPreflightRecorder(activationError: .timedOut)
        var project = Project(name: "Placed", resources: [browserResource()])
        project.launchDestination = .aeroSpaceWorkspace("work")
        let model = try makeModel(project: project, recorder: recorder, integrationEnabled: true)

        await model.openSelectedProject()

        XCTAssertEqual(recorder.events, ["workspace:work"])
        XCTAssertEqual(model.pendingLaunchPlacementFailure?.reason, .aeroSpace(.timedOut))

        model.cancelPendingProjectLaunch()

        XCTAssertNil(model.pendingLaunchPlacementFailure)
        XCTAssertEqual(recorder.events, ["workspace:work"])
    }

    func testUnsupportedDestinationUsesPlacementRecovery() async throws {
        let recorder = LaunchPreflightRecorder()
        var project = Project(name: "Future", resources: [browserResource()])
        project.launchDestination = .unsupported(
            type: "future-space",
            rawObject: ["type": .string("future-space")]
        )
        let model = try makeModel(project: project, recorder: recorder, integrationEnabled: true)

        await model.openSelectedProject()

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(
            model.pendingLaunchPlacementFailure?.reason,
            .unsupportedDestination("future-space")
        )
    }

    private func makeModel(
        project: Project,
        recorder: LaunchPreflightRecorder,
        integrationEnabled: Bool
    ) throws -> WorkBenchApplicationModel {
        WorkBenchApplicationModel(
            workflow: try makeWorkflow(projects: [project]),
            launcher: ProjectLauncher(browserLauncher: RecordingBrowserLauncher(recorder: recorder)),
            aeroSpaceController: RecordingAeroSpaceController(recorder: recorder),
            aeroSpaceSettingsStore: AeroSpaceSettingsStoreStub(isEnabled: integrationEnabled)
        )
    }

    private func browserResource() -> Resource {
        Resource(name: "Browser", payload: .browserWindow(BrowserWindow(tabs: ["https://example.com"])))
    }

    private func makeWorkflow(projects: [Project]) throws -> ProjectWorkflow {
        let workflow = ProjectWorkflow(repository: ApplicationModelRepositoryStub(projects: projects))
        try workflow.load()
        return workflow
    }
}

@MainActor
private final class LaunchPreflightRecorder {
    var events: [String] = []
    let activationError: AeroSpaceClientError?

    init(activationError: AeroSpaceClientError? = nil) {
        self.activationError = activationError
    }
}

@MainActor
private struct RecordingAeroSpaceController: AeroSpaceControlling {
    let recorder: LaunchPreflightRecorder

    func listWorkspaces() async -> Result<[String], AeroSpaceClientError> {
        .success([])
    }

    func activateWorkspace(named workspace: String) async -> Result<Void, AeroSpaceClientError> {
        recorder.events.append("workspace:\(workspace)")
        return recorder.activationError.map(Result.failure) ?? .success(())
    }
}

@MainActor
private struct RecordingBrowserLauncher: BrowserLaunching {
    let recorder: LaunchPreflightRecorder

    func open(_ browser: BrowserWindow) -> String? {
        recorder.events.append("resource")
        return nil
    }
}

@MainActor
private struct AeroSpaceSettingsStoreStub: AeroSpaceIntegrationSettingsStoring {
    let isEnabled: Bool

    func load() -> AeroSpaceIntegrationSettings {
        AeroSpaceIntegrationSettings(isEnabled: isEnabled)
    }

    func save(_ settings: AeroSpaceIntegrationSettings) {}
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
