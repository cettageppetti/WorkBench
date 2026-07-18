#if DEBUG
import Foundation

@MainActor
enum UITestModelFactory {
    private static let launchArgument = "--workbench-ui-testing"
    private static let launchEnvironmentKey = "WORKBENCH_UI_TESTING"
    private static var model: WorkBenchApplicationModel?

    static func makeIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) -> WorkBenchApplicationModel? {
        guard arguments.contains(launchArgument)
                || environment[launchEnvironmentKey] == "1"
                || defaults.bool(forKey: "workbenchUITesting") else { return nil }
        if let model { return model }

        let repository = UITestProjectRepository(
            projects: [
                .starter(),
                Project(name: "Second Project", resources: []),
                Project(
                    name: "Future Project",
                    resources: [
                        Resource(
                            name: "Future Resource",
                            payload: .unsupported(
                                type: "future-resource",
                                rawObject: ["type": .string("future-resource")]
                            )
                        )
                    ]
                )
            ],
            issues: [
                ProjectFileIssue(
                    fileURL: URL(fileURLWithPath: "/WorkBench/broken.json"),
                    message: "The file could not be decoded."
                )
            ]
        )
        let workflow = ProjectWorkflow(repository: repository)
        try? workflow.load()

        let launcher = ProjectLauncher(
            browserLauncher: UITestBrowserLauncher(),
            terminalLauncher: UITestTerminalLauncher(),
            finderLauncher: UITestFinderLauncher()
        )
        let directoryAccess = ConfigurationDirectoryAccess(
            initialStatus: .ready(URL(fileURLWithPath: "/WorkBench"))
        )
        let model = WorkBenchApplicationModel(
            directoryAccess: directoryAccess,
            workflow: workflow,
            launcher: launcher
        )
        self.model = model
        return model
    }
}

@MainActor
private final class UITestProjectRepository: ProjectRepositorying {
    private var projects: [Project]
    private let issues: [ProjectFileIssue]

    init(projects: [Project], issues: [ProjectFileIssue] = []) {
        self.projects = projects
        self.issues = issues
    }

    func load() throws -> ProjectRepositorySnapshot {
        ProjectRepositorySnapshot(projects: projects, issues: issues)
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

@MainActor
private struct UITestBrowserLauncher: BrowserLaunching {
    func open(_ browser: BrowserWindow) -> String? { nil }
}

@MainActor
private struct UITestTerminalLauncher: TerminalLaunching {
    func open(_ terminal: TerminalSession) -> String? { nil }
}

@MainActor
private struct UITestFinderLauncher: FinderLaunching {
    func open(_ finder: FinderWindow) -> String? { nil }
}
#endif
