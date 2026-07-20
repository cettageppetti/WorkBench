#if DEBUG
import Foundation

@MainActor
enum UITestModelFactory {
    private static let launchArgument = "--workbench-ui-testing"
    private static let launchEnvironmentKey = "WORKBENCH_UI_TESTING"
    private static let needsMigrationEnvironmentKey = "WORKBENCH_UI_TEST_NEEDS_MIGRATION"
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
                    name: "Placed Project",
                    resources: [],
                    launchDestination: .aeroSpaceWorkspace("2")
                ),
                Project(
                    name: "Application Project",
                    resources: [
                        Resource(
                            name: "Brave Browser",
                            payload: .application(
                                ApplicationResource(
                                    bundleIdentifier: "com.brave.Browser",
                                    lastKnownPath: "/Applications/Brave Browser.app"
                                )
                            )
                        )
                    ]
                ),
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
            chromeLauncher: UITestBrowserLauncher(),
            terminalLauncher: UITestTerminalLauncher(),
            finderLauncher: UITestFinderLauncher(),
            webBrowserLauncher: UITestWebBrowserLauncher()
        )
        let directoryStatus: ConfigurationDirectoryAccess.Status =
            environment[needsMigrationEnvironmentKey] == "1"
            ? .migrationAvailable(legacyDirectory: URL(fileURLWithPath: "/Documents/WorkBench"))
            : .ready(URL(fileURLWithPath: "/WorkBench"))
        let directoryAccess = ConfigurationDirectoryAccess(initialStatus: directoryStatus)
        let model = WorkBenchApplicationModel(
            directoryAccess: directoryAccess,
            workflow: workflow,
            launcher: launcher,
            aeroSpaceController: UITestAeroSpaceController(),
            aeroSpaceSettingsStore: UITestAeroSpaceSettingsStore()
        )
        self.model = model
        return model
    }

    static func makeSettingsModel() -> AeroSpaceSettingsModel {
        AeroSpaceSettingsModel(
            store: UITestAeroSpaceSettingsStore(),
            controller: UITestAeroSpaceController()
        )
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
private struct UITestWebBrowserLauncher: WebBrowserLaunching {
    func open(_ browser: WebBrowserResource) async -> String? { nil }
}

@MainActor
private struct UITestTerminalLauncher: TerminalLaunching {
    func open(_ terminal: TerminalSession) -> String? { nil }
}

@MainActor
private struct UITestFinderLauncher: FinderLaunching {
    func open(_ finder: FinderWindow) -> String? { nil }
}

@MainActor
private struct UITestAeroSpaceController: AeroSpaceControlling {
    func listWorkspaces() async -> Result<[String], AeroSpaceClientError> { .success(["1", "2"]) }
    func activateWorkspace(named workspace: String) async -> Result<Void, AeroSpaceClientError> {
        .success(())
    }
}

@MainActor
private struct UITestAeroSpaceSettingsStore: AeroSpaceIntegrationSettingsStoring {
    func load() -> AeroSpaceIntegrationSettings { AeroSpaceIntegrationSettings(isEnabled: false) }
    func save(_ settings: AeroSpaceIntegrationSettings) {}
}
#endif
