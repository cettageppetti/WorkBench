import AppKit
import Observation
import SwiftUI

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

    @ObservationIgnored private var attemptedInitialSelection = false
    @ObservationIgnored private let launcher: ProjectLauncher

    init(
        directoryAccess: ConfigurationDirectoryAccess = ConfigurationDirectoryAccess(),
        workflow: ProjectWorkflow? = nil,
        launcher: ProjectLauncher = ProjectLauncher()
    ) {
        self.directoryAccess = directoryAccess
        self.workflow = workflow
        self.launcher = launcher
    }

    func start() {
        guard workflow == nil else { return }
        directoryAccess.restoreAccess()
        if case .ready = directoryAccess.status {
            loadRepository()
        }
    }

    func selectDirectory(_ url: URL) {
        directoryAccess.selectDirectory(url)
        if case .ready = directoryAccess.status {
            loadRepository()
        }
    }

    func shouldOfferInitialFolderSelection() -> Bool {
        guard !attemptedInitialSelection,
              case .needsSelection(message: nil) = directoryAccess.status else { return false }
        attemptedInitialSelection = true
        return true
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

    func openSelectedProject() {
        guard let project = workflow?.draft else { return }
        let report = launcher.open(project)
        if report.hasProblems {
            launchReport = report
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
        case .browserWindow: name = "Browser Window"
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
            selectedResourceID = workflow.draft?.resources.first?.id
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
            selectedResourceID = workflow?.draft?.resources.first?.id
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

    private func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }
}
