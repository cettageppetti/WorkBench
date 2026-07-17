import Foundation
import XCTest
@testable import WorkBench

@MainActor
final class ProjectLauncherTests: XCTestCase {
    func testResourcesLaunchSequentiallyAndContinueAfterFailure() {
        let recorder = InvocationRecorder()
        let launcher = ProjectLauncher(
            browserLauncher: BrowserLauncherStub(recorder: recorder, error: "Safari denied"),
            terminalLauncher: TerminalLauncherStub(recorder: recorder),
            finderLauncher: FinderLauncherStub(recorder: recorder)
        )
        let unsupported = Resource(
            name: "Future",
            payload: .unsupported(type: "future", rawObject: ["type": .string("future")])
        )
        var project = Project.starter()
        project.resources.insert(unsupported, at: 1)

        let report = launcher.open(project)

        XCTAssertEqual(recorder.applications, ["Safari", "Terminal", "Finder"])
        XCTAssertTrue(report.didLaunch)
        XCTAssertTrue(report.hasProblems)
        XCTAssertEqual(report.results.map(\.outcome), [
            .failed("Safari denied"),
            .skipped("Resource type \"future\" is unsupported."),
            .succeeded,
            .succeeded
        ])
    }

    func testInvalidProjectDoesNotInvokeAnyAdapter() {
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

        let report = launcher.open(project)

        XCTAssertFalse(report.didLaunch)
        XCTAssertTrue(report.hasProblems)
        XCTAssertTrue(report.results.isEmpty)
        XCTAssertFalse(report.validationIssues.isEmpty)
        XCTAssertTrue(recorder.applications.isEmpty)
    }

    func testTerminalRejectsMissingDirectoryWithoutExecutingScript() {
        let executor = AppleScriptExecutorStub()
        let launcher = TerminalLauncher(executor: executor)

        let error = launcher.open(TerminalSession(workingDirectory: "/path/that/does/not/exist"))

        XCTAssertEqual(error, "The working directory does not exist or is not a folder.")
        XCTAssertTrue(executor.sources.isEmpty)
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
        XCTAssertNil(TerminalLauncher(executor: executor).open(
            TerminalSession(workingDirectory: directory.path)
        ))
        XCTAssertNil(FinderLauncher(executor: executor).open(
            FinderWindow(folder: directory.path)
        ))

        XCTAssertEqual(executor.sources.count, 3)
        XCTAssertTrue(executor.sources[0].contains("make new document"))
        XCTAssertTrue(executor.sources[0].contains("a\\\"b"))
        XCTAssertTrue(executor.sources[1].contains("do script"))
        XCTAssertTrue(executor.sources[1].contains("do script (\"cd -- \" & quoted form of"))
        XCTAssertLessThan(
            try XCTUnwrap(executor.sources[1].range(of: "do script")?.lowerBound),
            try XCTUnwrap(executor.sources[1].range(of: "activate")?.lowerBound)
        )
        XCTAssertTrue(executor.sources[1].contains("WorkBench Launcher \\\"Test\\\""))
        XCTAssertTrue(executor.sources[2].contains("make new Finder window"))
        XCTAssertTrue(executor.sources[2].contains("WorkBench Launcher \\\"Test\\\""))
    }
}

@MainActor
private final class InvocationRecorder {
    var applications: [String] = []
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
private final class AppleScriptExecutorStub: AppleScriptExecuting {
    private(set) var sources: [String] = []

    func execute(source: String) -> String? {
        sources.append(source)
        return nil
    }
}
