import AppKit
import Observation
import SwiftUI

enum LaunchPlacementFailureReason: Equatable {
    case integrationDisabled
    case unsupportedDestination(String)
    case aeroSpace(AeroSpaceClientError)

    var message: String {
        switch self {
        case .integrationDisabled:
            "AeroSpace integration is disabled in Settings."
        case let .unsupportedDestination(type):
            "The launch destination type \"\(type)\" is not supported by this version of WorkBench."
        case let .aeroSpace(error):
            error.recoveryMessage
        }
    }
}

struct PendingLaunchPlacementFailure: Equatable, Identifiable {
    let project: Project
    let reason: LaunchPlacementFailureReason

    var id: ProjectID { project.id }
}

@MainActor
@Observable
final class WorkBenchApplicationModel: NSObject, NSWindowDelegate {
    let directoryAccess: ConfigurationDirectoryAccess
    private(set) var workflow: ProjectWorkflow?
    var selectedResourceID: ResourceID?
    var presentedError: String?
    var showsUnsavedChangesDialog = false
    var projectPendingDeletion: Project?
    var launchReport: LaunchReport?
    var pendingLaunchPlacementFailure: PendingLaunchPlacementFailure?
    private(set) var isOpeningProject = false
    private(set) var availableAeroSpaceWorkspaces: [String] = []
    private(set) var aeroSpaceWorkspaceDiscoveryError: String?
    private(set) var isDiscoveringAeroSpaceWorkspaces = false

    @ObservationIgnored private let launcher: ProjectLauncher
    @ObservationIgnored private let aeroSpaceController: any AeroSpaceControlling
    @ObservationIgnored private let aeroSpaceSettingsStore: any AeroSpaceIntegrationSettingsStoring

    init(
        directoryAccess: ConfigurationDirectoryAccess = ConfigurationDirectoryAccess(),
        workflow: ProjectWorkflow? = nil,
        launcher: ProjectLauncher = ProjectLauncher(),
        aeroSpaceController: any AeroSpaceControlling = AeroSpaceClient(),
        aeroSpaceSettingsStore: any AeroSpaceIntegrationSettingsStoring =
            UserDefaultsAeroSpaceIntegrationSettingsStore()
    ) {
        self.directoryAccess = directoryAccess
        self.workflow = workflow
        self.launcher = launcher
        self.aeroSpaceController = aeroSpaceController
        self.aeroSpaceSettingsStore = aeroSpaceSettingsStore
    }

    func start() {
        guard workflow == nil else { return }
        directoryAccess.prepare()
        if case .ready = directoryAccess.status {
            loadRepository()
        }
    }

    func migrateLegacyProjects() {
        directoryAccess.migrateLegacyProjects()
        if case .ready = directoryAccess.status {
            loadRepository()
        }
    }

    func startWithEmptyProjectLibrary() {
        directoryAccess.startWithEmptyLibrary()
        if case .ready = directoryAccess.status {
            loadRepository()
        }
    }

    func retryProjectLibraryPreparation() {
        directoryAccess.prepare()
        if case .ready = directoryAccess.status {
            loadRepository()
        }
    }

    func selectProject(_ id: ProjectID?) {
        guard let id else { return }
        request(.select(id))
    }

    func save() {
        do {
            try workflow?.saveDraft()
        } catch {
            present(error)
        }
    }

    func reload() {
        request(.reload)
    }

    func revealProjectLibrary() {
        guard case let .ready(url) = directoryAccess.status else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openSelectedProject() async {
        guard !isOpeningProject, let project = workflow?.draft else { return }
        let validationIssues = ProjectValidator.validate(project)
        guard validationIssues.isEmpty else {
            presentLaunchReport(await launcher.open(project))
            return
        }

        isOpeningProject = true
        defer { isOpeningProject = false }
        switch project.launchDestination {
        case nil:
            presentLaunchReport(await launcher.open(project))
        case let .aeroSpaceWorkspace(workspace):
            guard aeroSpaceSettingsStore.load().isEnabled else {
                pendingLaunchPlacementFailure = PendingLaunchPlacementFailure(
                    project: project,
                    reason: .integrationDisabled
                )
                return
            }
            switch await aeroSpaceController.activateWorkspace(named: workspace) {
            case .success:
                presentLaunchReport(
                    await launcher.open(project, placementWorkspace: workspace)
                )
            case let .failure(error):
                pendingLaunchPlacementFailure = PendingLaunchPlacementFailure(
                    project: project,
                    reason: .aeroSpace(error)
                )
            }
        case let .unsupported(type, _):
            pendingLaunchPlacementFailure = PendingLaunchPlacementFailure(
                project: project,
                reason: .unsupportedDestination(type)
            )
        }
    }

    func openPendingProjectWithoutPlacement() async {
        guard let failure = pendingLaunchPlacementFailure else { return }
        pendingLaunchPlacementFailure = nil
        presentLaunchReport(await launcher.open(failure.project))
    }

    func cancelPendingProjectLaunch() {
        pendingLaunchPlacementFailure = nil
    }

    func discoverAeroSpaceWorkspaces() async {
        guard !isDiscoveringAeroSpaceWorkspaces else { return }
        isDiscoveringAeroSpaceWorkspaces = true
        defer { isDiscoveringAeroSpaceWorkspaces = false }
        switch await aeroSpaceController.listWorkspaces() {
        case let .success(workspaces):
            availableAeroSpaceWorkspaces = workspaces
            aeroSpaceWorkspaceDiscoveryError = nil
        case let .failure(error):
            availableAeroSpaceWorkspaces = []
            aeroSpaceWorkspaceDiscoveryError = error.recoveryMessage
        }
    }

    func createProject() {
        guard let workflow else { return }
        let existing = Set(workflow.projects.map { normalized($0.name) })
        var name = "Untitled Project"
        var suffix = 2
        while existing.contains(normalized(name)) {
            name = "Untitled Project \(suffix)"
            suffix += 1
        }
        request(.create(name: name))
    }

    func duplicateSelectedProject() {
        guard let id = workflow?.selectedProjectID else { return }
        request(.duplicate(id))
    }

    func confirmDeleteSelectedProject() {
        guard let id = workflow?.selectedProjectID,
              let project = workflow?.projects.first(where: { $0.id == id }) else { return }
        projectPendingDeletion = project
    }

    func deleteConfirmedProject() {
        guard let project = projectPendingDeletion else { return }
        projectPendingDeletion = nil
        request(.delete(project.id))
    }

    func resolveUnsavedChanges(_ choice: UnsavedChangesChoice) {
        do {
            let result = try workflow?.resolveUnsavedChanges(choice)
            showsUnsavedChangesDialog = false
            apply(result)
        } catch {
            showsUnsavedChangesDialog = false
            present(error)
        }
    }

    func updateDraft(_ update: (inout Project) -> Void) {
        do {
            try workflow?.updateDraft(update)
        } catch {
            present(error)
        }
    }

    func addResource(_ payload: ResourcePayload) {
        let name: String
        switch payload {
        case .browserWindow: name = "Safari Window"
        case .chromeWindow: name = "Chrome Window"
        case .terminalSession: name = "Terminal Session"
        case .finderWindow: name = "Finder Window"
        case .unsupported: return
        }
        let resource = Resource(name: name, payload: payload)
        updateDraft { $0.resources.append(resource) }
        selectedResourceID = resource.id
    }

    func removeSelectedResource() {
        guard let id = selectedResourceID else { return }
        selectedResourceID = nil
        updateDraft { $0.resources.removeAll { $0.id == id } }
    }

    func moveResources(from offsets: IndexSet, to destination: Int) {
        updateDraft { $0.resources.move(fromOffsets: offsets, toOffset: destination) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        lifecycleDecision(for: .closeWindow) == .closeWindow
    }

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        lifecycleDecision(for: .quit) == .quit ? .terminateNow : .terminateCancel
    }

    private func loadRepository() {
        let repository = ProjectRepository(directoryProvider: directoryAccess)
        let workflow = ProjectWorkflow(repository: repository)
        do {
            try workflow.load()
            self.workflow = workflow
            selectedResourceID = nil
        } catch {
            present(error)
        }
    }

    private func request(_ action: ProjectWorkflowAction) {
        do {
            apply(try workflow?.request(action))
        } catch {
            present(error)
        }
    }

    private func apply(_ result: ProjectWorkflowRequestResult?) {
        guard let result else { return }
        switch result {
        case .needsUnsavedChangesDecision:
            showsUnsavedChangesDialog = true
        case .completed, .cancelled:
            selectedResourceID = nil
        }
    }

    private func lifecycleDecision(for action: ProjectWorkflowAction) -> ProjectWorkflowContinuation {
        do {
            guard let workflow else {
                return action == .quit ? .quit : .closeWindow
            }
            let result = try workflow.request(action)
            if case let .completed(continuation) = result { return continuation }

            let alert = NSAlert()
            alert.icon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
            alert.messageText = "Do you want to save the changes to \"\(workflow.draft?.name ?? "Project")\"?"
            alert.informativeText = "Your changes will be lost if you don’t save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Discard Changes")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                if case let .completed(continuation) = try workflow.resolveUnsavedChanges(.save) {
                    return continuation
                }
            case .alertThirdButtonReturn:
                if case let .completed(continuation) = try workflow.resolveUnsavedChanges(.discard) {
                    return continuation
                }
            default:
                _ = try workflow.resolveUnsavedChanges(.cancel)
            }
        } catch {
            present(error)
        }
        return .stayOpen
    }

    private func present(_ error: Error) {
        presentedError = error.localizedDescription
    }

    private func presentLaunchReport(_ report: LaunchReport) {
        if report.hasProblems {
            launchReport = report
        }
    }

    private func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }
}
