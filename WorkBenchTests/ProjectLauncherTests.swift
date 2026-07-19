import Foundation
import XCTest
@testable import WorkBench

@MainActor
final class ProjectLauncherTests: XCTestCase {
    func testStandardRegistryProvidesBundleIdentityForEverySupportedType() {
        let recorder = InvocationRecorder()
        let registry = ResourceLaunchAdapterRegistry.standard(
            browserLauncher: BrowserLauncherStub(recorder: recorder),
            chromeLauncher: ChromeLauncherStub(recorder: recorder),
            terminalLauncher: TerminalLauncherStub(recorder: recorder),
            finderLauncher: FinderLauncherStub(recorder: recorder),
            applicationLauncher: ApplicationLauncherStub(recorder: recorder)
        )
        let resources = [
            Resource(name: "Safari", payload: .browserWindow(.init(tabs: ["https://example.com"]))),
            Resource(name: "Chrome", payload: .chromeWindow(.init(tabs: ["https://example.com"]))),
            Resource(name: "Terminal", payload: .terminalSession(.init(workingDirectory: "~/"))),
            Resource(name: "Finder", payload: .finderWindow(.init(folder: "~/"))),
            Resource(
                name: "Editor",
                payload: .application(.init(
                    bundleIdentifier: "com.example.Editor",
                    lastKnownPath: "/Applications/Editor.app"
                ))
            )
        ]

        XCTAssertEqual(
            resources.map { resource in
                registry.adapter(for: resource.type)?.bundleIdentifier(for: resource.payload)
            },
            [
                "com.apple.Safari",
                "com.google.Chrome",
                "com.apple.Terminal",
                "com.apple.finder",
                "com.example.Editor"
            ]
        )
    }

    func testRegistryControlsDispatchWithoutSwitchFallback() async {
        let launcher = ProjectLauncher(
            adapterRegistry: ResourceLaunchAdapterRegistry(adapters: [])
        )
        let resource = Resource(
            name: "Safari",
            payload: .browserWindow(.init(tabs: ["https://example.com"]))
        )

        let report = await launcher.open(Project(name: "No Adapters", resources: [resource]))

        XCTAssertEqual(
            report.results.map(\.outcome),
            [.skipped("Resource type \"browser-window\" is unsupported.")]
        )
    }

    func testResourcesLaunchSequentiallyAndContinueAfterFailure() async {
        let recorder = InvocationRecorder()
        let launcher = ProjectLauncher(
            browserLauncher: BrowserLauncherStub(recorder: recorder, error: "Safari denied"),
            chromeLauncher: ChromeLauncherStub(recorder: recorder, error: "Chrome denied"),
            terminalLauncher: TerminalLauncherStub(recorder: recorder),
            finderLauncher: FinderLauncherStub(recorder: recorder)
        )
        let unsupported = Resource(
            name: "Future",
            payload: .unsupported(type: "future", rawObject: ["type": .string("future")])
        )
        var project = Project.starter()
        project.resources.insert(unsupported, at: 1)
        project.resources.insert(
            Resource(
                name: "Chrome",
                payload: .chromeWindow(BrowserWindow(tabs: ["https://google.com"]))
            ),
            at: 2
        )

        let report = await launcher.open(project)

        XCTAssertEqual(recorder.applications, ["Safari", "Chrome", "Terminal", "Finder"])
        XCTAssertTrue(report.didLaunch)
        XCTAssertTrue(report.hasProblems)
        XCTAssertEqual(report.results.map(\.outcome), [
            .failed("Safari denied"),
            .skipped("Resource type \"future\" is unsupported."),
            .failed("Chrome denied"),
            .succeeded,
            .succeeded
        ])
    }

    func testInvalidProjectDoesNotInvokeAnyAdapter() async {
        let recorder = InvocationRecorder()
        let launcher = ProjectLauncher(
            browserLauncher: BrowserLauncherStub(recorder: recorder),
            terminalLauncher: TerminalLauncherStub(recorder: recorder),
            finderLauncher: FinderLauncherStub(recorder: recorder)
        )
        let project = Project(
            name: "Invalid",
            resources: [Resource(name: "Browser", payload: .browserWindow(BrowserWindow(tabs: [])))]
        )

        let report = await launcher.open(project)

        XCTAssertFalse(report.didLaunch)
        XCTAssertTrue(report.hasProblems)
        XCTAssertTrue(report.results.isEmpty)
        XCTAssertFalse(report.validationIssues.isEmpty)
        XCTAssertTrue(recorder.applications.isEmpty)
    }

    func testApplicationResourceUsesDefaultLauncher() async {
        let recorder = InvocationRecorder()
        let application = ApplicationResource(
            bundleIdentifier: "com.apple.iMovie",
            lastKnownPath: "/Applications/iMovie.app"
        )
        let launcher = ProjectLauncher(
            applicationLauncher: ApplicationLauncherStub(recorder: recorder)
        )
        let project = Project(name: "Movie", resources: [
            Resource(name: "iMovie", payload: .application(application))
        ])

        let report = await launcher.open(project)

        XCTAssertEqual(recorder.applications, ["com.apple.iMovie"])
        XCTAssertEqual(report.results.map(\.outcome), [.succeeded])
    }

    func testGenericSafariApplicationDoesNotUseEnhancedSafariAdapter() async {
        let recorder = InvocationRecorder()
        let launcher = ProjectLauncher(
            browserLauncher: BrowserLauncherStub(recorder: recorder),
            applicationLauncher: ApplicationLauncherStub(recorder: recorder)
        )
        let application = ApplicationResource(
            bundleIdentifier: "com.apple.Safari",
            lastKnownPath: "/Applications/Safari.app"
        )

        let report = await launcher.open(Project(name: "Generic Safari", resources: [
            Resource(name: "Safari", payload: .application(application))
        ]))

        XCTAssertEqual(recorder.applications, ["com.apple.Safari"])
        XCTAssertEqual(report.results.map(\.outcome), [.succeeded])
    }

    func testDefaultApplicationLauncherReportsMissingApplication() async {
        let identifier = "com.workbench.tests.missing.\(UUID().uuidString)"
        let application = ApplicationResource(
            bundleIdentifier: identifier,
            lastKnownPath: "/Applications/WorkBench Missing \(UUID().uuidString).app"
        )

        let error = await FoundationApplicationLauncher().open(application)

        XCTAssertEqual(
            error,
            "The application is not installed or its saved location is unavailable."
        )
    }

    func testApplicationResourceUsesBundleIdentifierForPlacement() async {
        let recorder = InvocationRecorder()
        let application = ApplicationResource(
            bundleIdentifier: "com.example.Editor",
            lastKnownPath: "/Applications/Editor.app"
        )
        let windowController = AeroSpaceWindowControllerStub(listResults: [
            .success([]),
            .success([aeroSpaceWindow(id: 81, bundleIdentifier: application.bundleIdentifier, workspace: "C")])
        ])
        let launcher = ProjectLauncher(
            applicationLauncher: ApplicationLauncherStub(recorder: recorder),
            aeroSpaceWindowController: windowController,
            aeroSpaceWorkspaceController: AeroSpaceWorkspaceControllerStub(),
            windowDetectionInterval: .zero
        )
        let project = Project(name: "Editor", resources: [
            Resource(name: "Editor", payload: .application(application))
        ])

        let report = await launcher.open(project, placementWorkspace: "6")

        XCTAssertEqual(recorder.applications, [application.bundleIdentifier])
        XCTAssertEqual(windowController.listBundleIdentifiers, [
            application.bundleIdentifier, application.bundleIdentifier
        ])
        XCTAssertEqual(windowController.moves, [.init(id: 81, workspace: "6")])
        XCTAssertEqual(report.results.map(\.outcome), [.succeeded])
    }

    func testPlacedResourceSnapshotsCreatesMovesConfirmsAndRestoresWorkspace() async {
        let recorder = InvocationRecorder()
        let windowController = AeroSpaceWindowControllerStub(listResults: [
            .success([aeroSpaceWindow(id: 10, bundleIdentifier: "com.apple.Safari", workspace: "C")]),
            .success([
                aeroSpaceWindow(id: 10, bundleIdentifier: "com.apple.Safari", workspace: "C"),
                aeroSpaceWindow(id: 42, bundleIdentifier: "com.apple.Safari", workspace: "C")
            ])
        ])
        let workspaceController = AeroSpaceWorkspaceControllerStub()
        let launcher = ProjectLauncher(
            browserLauncher: BrowserLauncherStub(recorder: recorder),
            aeroSpaceWindowController: windowController,
            aeroSpaceWorkspaceController: workspaceController,
            windowDetectionInterval: .zero
        )
        let project = Project(name: "Placed", resources: [
            Resource(
                name: "Safari",
                payload: .browserWindow(BrowserWindow(tabs: ["https://example.com"]))
            )
        ])

        let report = await launcher.open(project, placementWorkspace: "6")

        XCTAssertEqual(report.results.map(\.outcome), [.succeeded])
        XCTAssertEqual(recorder.applications, ["Safari"])
        XCTAssertEqual(windowController.listBundleIdentifiers, [
            "com.apple.Safari", "com.apple.Safari"
        ])
        XCTAssertEqual(windowController.moves, [.init(id: 42, workspace: "6")])
        XCTAssertEqual(workspaceController.activations, ["6"])
    }

    func testAmbiguousPlacementMovesNothingAndContinuesWithLaterResource() async {
        let recorder = InvocationRecorder()
        let windowController = AeroSpaceWindowControllerStub(listResults: [
            .success([]),
            .success([
                aeroSpaceWindow(id: 42, bundleIdentifier: "com.apple.Safari", workspace: "6"),
                aeroSpaceWindow(id: 43, bundleIdentifier: "com.apple.Safari", workspace: "6")
            ]),
            .success([]),
            .success([
                aeroSpaceWindow(id: 44, bundleIdentifier: "com.apple.finder", workspace: "C")
            ])
        ])
        let workspaceController = AeroSpaceWorkspaceControllerStub()
        let launcher = ProjectLauncher(
            browserLauncher: BrowserLauncherStub(recorder: recorder),
            finderLauncher: FinderLauncherStub(recorder: recorder),
            aeroSpaceWindowController: windowController,
            aeroSpaceWorkspaceController: workspaceController,
            windowDetectionInterval: .zero
        )
        let project = Project(name: "Placed", resources: [
            Resource(
                name: "Safari",
                payload: .browserWindow(BrowserWindow(tabs: ["https://example.com"]))
            ),
            Resource(name: "Finder", payload: .finderWindow(FinderWindow(folder: "~/")))
        ])

        let report = await launcher.open(project, placementWorkspace: "6")

        XCTAssertEqual(recorder.applications, ["Safari", "Finder"])
        XCTAssertEqual(windowController.moves, [.init(id: 44, workspace: "6")])
        XCTAssertEqual(workspaceController.activations, ["6", "6"])
        XCTAssertEqual(
            report.results.first?.outcome,
            .failed(
                "The window opened, but WorkBench could not place it: "
                    + "AeroSpace reported multiple new windows (42, 43); no window was moved."
            )
        )
        XCTAssertEqual(report.results.last?.outcome, .succeeded)
    }

    func testDetectionTimeoutReportsOpenedWindowWithoutMovingAnything() async {
        let recorder = InvocationRecorder()
        let windowController = AeroSpaceWindowControllerStub(listResults: [
            .success([]), .success([]), .success([])
        ])
        let workspaceController = AeroSpaceWorkspaceControllerStub()
        let launcher = ProjectLauncher(
            browserLauncher: BrowserLauncherStub(recorder: recorder),
            aeroSpaceWindowController: windowController,
            aeroSpaceWorkspaceController: workspaceController,
            windowDetectionAttempts: 2,
            windowDetectionInterval: .zero
        )
        let project = Project(name: "Placed", resources: [
            Resource(
                name: "Safari",
                payload: .browserWindow(BrowserWindow(tabs: ["https://example.com"]))
            )
        ])

        let report = await launcher.open(project, placementWorkspace: "6")

        XCTAssertEqual(recorder.applications, ["Safari"])
        XCTAssertTrue(windowController.moves.isEmpty)
        XCTAssertEqual(workspaceController.activations, ["6"])
        XCTAssertEqual(
            report.results.first?.outcome,
            .failed(
                "The window opened, but WorkBench could not place it: "
                    + "AeroSpace did not detect the new application window before the timeout."
            )
        )
    }

    func testMoveFailureRestoresWorkspaceAndReportsOpenedWindow() async {
        let recorder = InvocationRecorder()
        let windowController = AeroSpaceWindowControllerStub(
            listResults: [
                .success([]),
                .success([
                    aeroSpaceWindow(id: 42, bundleIdentifier: "com.apple.Safari", workspace: "C")
                ])
            ],
            moveResult: .failure(.timedOut)
        )
        let workspaceController = AeroSpaceWorkspaceControllerStub()
        let launcher = ProjectLauncher(
            browserLauncher: BrowserLauncherStub(recorder: recorder),
            aeroSpaceWindowController: windowController,
            aeroSpaceWorkspaceController: workspaceController,
            windowDetectionInterval: .zero
        )
        let project = Project(name: "Placed", resources: [
            Resource(
                name: "Safari",
                payload: .browserWindow(BrowserWindow(tabs: ["https://example.com"]))
            )
        ])

        let report = await launcher.open(project, placementWorkspace: "6")

        XCTAssertEqual(windowController.moves, [.init(id: 42, workspace: "6")])
        XCTAssertEqual(workspaceController.activations, ["6"])
        XCTAssertEqual(
            report.results.first?.outcome,
            .failed(
                "The window opened, but WorkBench could not place it: "
                    + "AeroSpace did not respond before the operation timed out."
            )
        )
    }

    func testSnapshotFailureSkipsUnsafeLaunchAndContinues() async {
        let recorder = InvocationRecorder()
        let windowController = AeroSpaceWindowControllerStub(listResults: [
            .failure(.timedOut),
            .success([]),
            .success([aeroSpaceWindow(id: 44, bundleIdentifier: "com.apple.finder", workspace: "C")])
        ])
        let launcher = ProjectLauncher(
            browserLauncher: BrowserLauncherStub(recorder: recorder),
            finderLauncher: FinderLauncherStub(recorder: recorder),
            aeroSpaceWindowController: windowController,
            aeroSpaceWorkspaceController: AeroSpaceWorkspaceControllerStub(),
            windowDetectionInterval: .zero
        )
        let project = Project(name: "Placed", resources: [
            Resource(
                name: "Safari",
                payload: .browserWindow(BrowserWindow(tabs: ["https://example.com"]))
            ),
            Resource(name: "Finder", payload: .finderWindow(FinderWindow(folder: "~/")))
        ])

        let report = await launcher.open(project, placementWorkspace: "6")

        XCTAssertEqual(recorder.applications, ["Finder"])
        XCTAssertEqual(windowController.moves, [.init(id: 44, workspace: "6")])
        XCTAssertEqual(
            report.results.first?.outcome,
            .failed(
                "WorkBench could not prepare window placement: "
                    + "AeroSpace did not respond before the operation timed out."
            )
        )
        XCTAssertEqual(report.results.last?.outcome, .succeeded)
    }

    func testTerminalRejectsMissingDirectoryWithoutExecutingScript() {
        let executor = AppleScriptExecutorStub()
        let launcher = TerminalLauncher(executor: executor)

        let error = launcher.open(TerminalSession(workingDirectory: "/path/that/does/not/exist"))

        XCTAssertEqual(error, "The working directory does not exist or is not a folder.")
        XCTAssertTrue(executor.sources.isEmpty)
    }

    func testHomeTerminalUsesNormalStartupWithoutInjectingCD() {
        for storedPath in ["~", "~/"] {
            let executor = AppleScriptExecutorStub()
            let launcher = TerminalLauncher(executor: executor)

            XCTAssertNil(launcher.open(TerminalSession(workingDirectory: storedPath)))
            XCTAssertEqual(executor.sources.count, 1)
            XCTAssertTrue(executor.sources[0].contains("do script \"\""))
            XCTAssertFalse(executor.sources[0].contains("cd --"))
        }
    }

    func testParameterizedAdaptersEscapeValuesAndCreateNewWindows() throws {
        let executor = AppleScriptExecutorStub()
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "WorkBench Launcher \"Test\" \(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertNil(SafariLauncher(executor: executor).open(
            BrowserWindow(tabs: ["https://example.com/a\"b", "file:///tmp/example"])
        ))
        XCTAssertNil(ChromeLauncher(executor: executor).open(
            BrowserWindow(tabs: ["https://example.com/chrome\"tab", "file:///tmp/chrome"])
        ))
        XCTAssertNil(TerminalLauncher(executor: executor).open(
            TerminalSession(workingDirectory: directory.path)
        ))
        XCTAssertNil(FinderLauncher(executor: executor).open(
            FinderWindow(folder: directory.path)
        ))

        XCTAssertEqual(executor.sources.count, 4)
        XCTAssertTrue(executor.sources[0].contains("make new document"))
        XCTAssertTrue(executor.sources[0].contains("a\\\"b"))
        XCTAssertTrue(executor.sources[1].contains("tell application \"Google Chrome\""))
        XCTAssertTrue(executor.sources[1].contains(
            "set chromeWasRunning to application \"Google Chrome\" is running"
        ))
        XCTAssertTrue(executor.sources[1].contains("if chromeWasRunning then"))
        XCTAssertTrue(executor.sources[1].contains("set createdWindow to make new window"))
        XCTAssertTrue(executor.sources[1].contains("set createdWindow to front window"))
        XCTAssertTrue(executor.sources[1].contains("repeat 100 times"))
        XCTAssertTrue(executor.sources[1].contains("delay 0.05"))
        XCTAssertTrue(executor.sources[1].contains("tell createdWindow"))
        XCTAssertTrue(executor.sources[1].contains("make new tab at end of tabs with properties"))
        XCTAssertTrue(executor.sources[1].contains("chrome\\\"tab"))
        XCTAssertTrue(executor.sources[1].contains("set active tab index to count of tabs"))
        XCTAssertTrue(executor.sources[2].contains("do script"))
        XCTAssertTrue(executor.sources[2].contains("do script (\"cd -- \" & quoted form of"))
        XCTAssertTrue(executor.sources[2].contains("cd --"))
        XCTAssertLessThan(
            try XCTUnwrap(executor.sources[2].range(of: "do script")?.lowerBound),
            try XCTUnwrap(executor.sources[2].range(of: "activate")?.lowerBound)
        )
        XCTAssertTrue(executor.sources[2].contains("WorkBench Launcher \\\"Test\\\""))
        XCTAssertTrue(executor.sources[3].contains("make new Finder window"))
        XCTAssertTrue(executor.sources[3].contains("WorkBench Launcher \\\"Test\\\""))
    }
}

@MainActor
private final class InvocationRecorder {
    var applications: [String] = []
}

@MainActor
private final class AeroSpaceWindowControllerStub: AeroSpaceWindowControlling {
    struct Move: Equatable {
        let id: Int
        let workspace: String
    }

    private var listResults: [Result<[AeroSpaceWindow], AeroSpaceClientError>]
    var moveResult: Result<Void, AeroSpaceClientError>
    private(set) var listBundleIdentifiers: [String] = []
    private(set) var moves: [Move] = []

    init(
        listResults: [Result<[AeroSpaceWindow], AeroSpaceClientError>],
        moveResult: Result<Void, AeroSpaceClientError> = .success(())
    ) {
        self.listResults = listResults
        self.moveResult = moveResult
    }

    func listWindows(
        forApplicationBundleIdentifier bundleIdentifier: String
    ) async -> Result<[AeroSpaceWindow], AeroSpaceClientError> {
        listBundleIdentifiers.append(bundleIdentifier)
        return listResults.removeFirst()
    }

    func moveWindow(
        id: Int,
        toWorkspace workspace: String
    ) async -> Result<Void, AeroSpaceClientError> {
        moves.append(Move(id: id, workspace: workspace))
        return moveResult
    }
}

@MainActor
private final class AeroSpaceWorkspaceControllerStub: AeroSpaceControlling {
    var activationResult: Result<Void, AeroSpaceClientError>
    private(set) var activations: [String] = []

    init(activationResult: Result<Void, AeroSpaceClientError> = .success(())) {
        self.activationResult = activationResult
    }

    func listWorkspaces() async -> Result<[String], AeroSpaceClientError> { .success([]) }

    func activateWorkspace(named workspace: String) async -> Result<Void, AeroSpaceClientError> {
        activations.append(workspace)
        return activationResult
    }
}

private func aeroSpaceWindow(
    id: Int,
    bundleIdentifier: String,
    workspace: String
) -> AeroSpaceWindow {
    AeroSpaceWindow(
        id: id,
        applicationBundleIdentifier: bundleIdentifier,
        processIdentifier: 1234,
        workspace: workspace,
        title: "Window \(id)"
    )
}

@MainActor
private struct BrowserLauncherStub: BrowserLaunching {
    let recorder: InvocationRecorder
    var error: String?

    init(recorder: InvocationRecorder, error: String? = nil) {
        self.recorder = recorder
        self.error = error
    }

    func open(_ browser: BrowserWindow) -> String? {
        recorder.applications.append("Safari")
        return error
    }
}

@MainActor
private struct ChromeLauncherStub: BrowserLaunching {
    let recorder: InvocationRecorder
    var error: String?

    init(recorder: InvocationRecorder, error: String? = nil) {
        self.recorder = recorder
        self.error = error
    }

    func open(_ browser: BrowserWindow) -> String? {
        recorder.applications.append("Chrome")
        return error
    }
}

@MainActor
private struct TerminalLauncherStub: TerminalLaunching {
    let recorder: InvocationRecorder
    var error: String?

    func open(_ terminal: TerminalSession) -> String? {
        recorder.applications.append("Terminal")
        return error
    }
}

@MainActor
private struct FinderLauncherStub: FinderLaunching {
    let recorder: InvocationRecorder
    var error: String?

    func open(_ finder: FinderWindow) -> String? {
        recorder.applications.append("Finder")
        return error
    }
}

@MainActor
private struct ApplicationLauncherStub: ApplicationLaunching {
    let recorder: InvocationRecorder
    var error: String?

    init(recorder: InvocationRecorder, error: String? = nil) {
        self.recorder = recorder
        self.error = error
    }

    func open(_ application: ApplicationResource) async -> String? {
        recorder.applications.append(application.bundleIdentifier)
        return error
    }
}

@MainActor
private final class AppleScriptExecutorStub: AppleScriptExecuting {
    private(set) var sources: [String] = []

    func execute(source: String) -> String? {
        sources.append(source)
        return nil
    }
}
