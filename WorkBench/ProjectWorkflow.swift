import Foundation
import Observation

enum UnsavedChangesChoice {
    case save
    case discard
    case cancel
}

enum ProjectWorkflowAction: Equatable {
    case select(ProjectID)
    case reload
    case closeWindow
    case quit
    case create(name: String)
    case duplicate(ProjectID)
    case delete(ProjectID)
}

enum ProjectWorkflowContinuation: Equatable {
    case stayOpen
    case closeWindow
    case quit
}

enum ProjectWorkflowRequestResult: Equatable {
    case completed(ProjectWorkflowContinuation)
    case needsUnsavedChangesDecision
    case cancelled
}

enum ProjectWorkflowError: LocalizedError {
    case projectNotFound
    case noActiveDraft
    case duplicateProjectName(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            "The selected Project is no longer available."
        case .noActiveDraft:
            "No Project is selected."
        case let .duplicateProjectName(name):
            "A Project named \"\(name)\" already exists."
        }
    }
}

@MainActor
@Observable
final class ProjectWorkflow {
    private struct DraftSession {
        var persisted: Project?
        var draft: Project
        var returnSelectionID: ProjectID?

        var isDirty: Bool { persisted != draft }
    }

    @ObservationIgnored private let repository: any ProjectRepositorying
    private var session: DraftSession?
    private(set) var pendingAction: ProjectWorkflowAction?

    private(set) var projects: [Project] = []
    private(set) var issues: [ProjectFileIssue] = []

    var selectedProjectID: ProjectID? { session?.draft.id }
    var draft: Project? { session?.draft }
    var isDirty: Bool { session?.isDirty ?? false }

    init(repository: any ProjectRepositorying) {
        self.repository = repository
    }

    func load() throws {
        apply(try repository.load(), preferredSelectionID: selectedProjectID)
    }

    func updateDraft(_ update: (inout Project) -> Void) throws {
        guard var session else { throw ProjectWorkflowError.noActiveDraft }
        update(&session.draft)
        self.session = session
    }

    func request(_ action: ProjectWorkflowAction) throws -> ProjectWorkflowRequestResult {
        guard pendingAction == nil else {
            return .needsUnsavedChangesDecision
        }
        if isDirty {
            pendingAction = action
            return .needsUnsavedChangesDecision
        }
        return try perform(action)
    }

    func resolveUnsavedChanges(
        _ choice: UnsavedChangesChoice
    ) throws -> ProjectWorkflowRequestResult {
        guard let action = pendingAction else { return .cancelled }

        switch choice {
        case .save:
            try saveDraft()
        case .discard:
            discardDraft()
        case .cancel:
            pendingAction = nil
            return .cancelled
        }

        pendingAction = nil
        return try perform(action)
    }

    func saveDraft() throws {
        guard var session else { throw ProjectWorkflowError.noActiveDraft }
        try ensureUniqueName(session.draft.name, excluding: session.draft.id)
        try repository.save(session.draft)

        session.persisted = session.draft
        session.returnSelectionID = nil
        self.session = session
        upsert(session.draft)
    }

    private func perform(_ action: ProjectWorkflowAction) throws -> ProjectWorkflowRequestResult {
        switch action {
        case let .select(id):
            try select(id)
            return .completed(.stayOpen)
        case .reload:
            apply(try repository.load(), preferredSelectionID: selectedProjectID)
            return .completed(.stayOpen)
        case .closeWindow:
            return .completed(.closeWindow)
        case .quit:
            return .completed(.quit)
        case let .create(name):
            try beginNewProject(Project(name: name, resources: []))
            return .completed(.stayOpen)
        case let .duplicate(id):
            guard let source = projects.first(where: { $0.id == id }) else {
                throw ProjectWorkflowError.projectNotFound
            }
            let name = uniqueDuplicateName(for: source.name)
            try beginNewProject(source.duplicated(named: name))
            return .completed(.stayOpen)
        case let .delete(id):
            guard let project = projects.first(where: { $0.id == id }) else {
                throw ProjectWorkflowError.projectNotFound
            }
            try repository.delete(project)
            let preferredID = projects.first(where: { $0.id != id })?.id
            apply(try repository.load(), preferredSelectionID: preferredID)
            return .completed(.stayOpen)
        }
    }

    private func select(_ id: ProjectID) throws {
        guard let project = projects.first(where: { $0.id == id }) else {
            throw ProjectWorkflowError.projectNotFound
        }
        session = DraftSession(persisted: project, draft: project, returnSelectionID: nil)
    }

    private func beginNewProject(_ project: Project) throws {
        try ensureUniqueName(project.name, excluding: project.id)
        let returnID = selectedProjectID.flatMap { id in
            projects.contains(where: { $0.id == id }) ? id : nil
        }
        session = DraftSession(persisted: nil, draft: project, returnSelectionID: returnID)
    }

    private func discardDraft() {
        guard let session else { return }
        if let persisted = session.persisted {
            self.session = DraftSession(persisted: persisted, draft: persisted, returnSelectionID: nil)
        } else if let returnID = session.returnSelectionID,
                  let project = projects.first(where: { $0.id == returnID }) {
            self.session = DraftSession(persisted: project, draft: project, returnSelectionID: nil)
        } else {
            self.session = nil
        }
    }

    private func apply(_ snapshot: ProjectRepositorySnapshot, preferredSelectionID: ProjectID?) {
        projects = snapshot.projects
        issues = snapshot.issues
        let selected = preferredSelectionID.flatMap { preferred in
            projects.first(where: { $0.id == preferred })
        } ?? projects.first
        session = selected.map {
            DraftSession(persisted: $0, draft: $0, returnSelectionID: nil)
        }
    }

    private func upsert(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
        projects.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func ensureUniqueName(_ name: String, excluding id: ProjectID) throws {
        let normalizedName = normalized(name)
        if projects.contains(where: { $0.id != id && normalized($0.name) == normalizedName }) {
            throw ProjectWorkflowError.duplicateProjectName(name)
        }
    }

    private func uniqueDuplicateName(for name: String) -> String {
        let base = "\(name) Copy"
        if !projects.contains(where: { normalized($0.name) == normalized(base) }) {
            return base
        }
        var suffix = 2
        while projects.contains(where: { normalized($0.name) == normalized("\(base) \(suffix)") }) {
            suffix += 1
        }
        return "\(base) \(suffix)"
    }

    private func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }
}
