import Foundation
import XCTest
@testable import WorkBench

@MainActor
final class AeroSpaceClientTests: XCTestCase {
    func testFoundationRunnerCapturesOutputAndExitStatus() async throws {
        let result = await FoundationAeroSpaceCommandRunner().run(
            executableURL: URL(filePath: "/usr/bin/printf"),
            arguments: ["workspace-output"],
            timeout: .seconds(1)
        )

        let command = try result.get()
        XCTAssertEqual(command.exitCode, 0)
        XCTAssertEqual(String(data: command.standardOutput, encoding: .utf8), "workspace-output")
        XCTAssertTrue(command.standardError.isEmpty)
    }

    func testFoundationRunnerEnforcesTimeout() async {
        let result = await FoundationAeroSpaceCommandRunner().run(
            executableURL: URL(filePath: "/bin/sleep"),
            arguments: ["2"],
            timeout: .milliseconds(50)
        )

        XCTAssertEqual(result.failure, .timedOut)
    }

    func testListsWorkspacesFromTypedJSONResponse() async {
        let runner = AeroSpaceCommandRunnerStub(responses: [
            .success(commandResult(output: #"[{"workspace":"1"},{"workspace":"work"}]"#))
        ])
        let client = makeClient(runner: runner)

        let result = await client.listWorkspaces()

        XCTAssertEqual(try? result.get(), ["1", "work"])
        XCTAssertEqual(runner.invocations.map(\.arguments), [["list-workspaces", "--all", "--json"]])
    }

    func testActivatesWorkspaceAndConfirmsFocus() async {
        let runner = AeroSpaceCommandRunnerStub(responses: [
            .success(commandResult()),
            .success(commandResult(output: #"[{"workspace":"project name"}]"#))
        ])
        let client = makeClient(runner: runner)

        let result = await client.activateWorkspace(named: "project name")

        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(runner.invocations.map(\.arguments), [
            ["workspace", "--", "project name"],
            ["list-workspaces", "--focused", "--json"]
        ])
    }

    func testReportsUnavailableExecutableWithoutRunningCommand() async {
        let runner = AeroSpaceCommandRunnerStub(responses: [])
        let client = AeroSpaceClient(
            commandRunner: runner,
            executableCandidates: [URL(filePath: "/missing/aerospace")]
        )

        let result = await client.listWorkspaces()

        XCTAssertEqual(result.failure, .executableUnavailable)
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    func testPreservesCommandFailureDetailsAndStopsBeforeConfirmation() async {
        let runner = AeroSpaceCommandRunnerStub(responses: [
            .success(commandResult(exitCode: 1, error: "AeroSpace is not running\n"))
        ])
        let client = makeClient(runner: runner)

        let result = await client.activateWorkspace(named: "2")

        XCTAssertEqual(
            result.failure,
            .commandFailed(exitCode: 1, message: "AeroSpace is not running")
        )
        XCTAssertEqual(runner.invocations.count, 1)
    }

    func testReportsMalformedJSONAndFocusMismatch() async {
        let malformedRunner = AeroSpaceCommandRunnerStub(responses: [
            .success(commandResult(output: "not json"))
        ])
        let malformedResult = await makeClient(runner: malformedRunner).listWorkspaces()
        XCTAssertEqual(malformedResult.failure, .invalidResponse)

        let mismatchRunner = AeroSpaceCommandRunnerStub(responses: [
            .success(commandResult()),
            .success(commandResult(output: #"[{"workspace":"other"}]"#))
        ])
        let mismatchResult = await makeClient(runner: mismatchRunner)
            .activateWorkspace(named: "wanted")
        XCTAssertEqual(
            mismatchResult.failure,
            .workspaceNotFocused(expected: "wanted", actual: "other")
        )
    }

    func testPropagatesTimeout() async {
        let runner = AeroSpaceCommandRunnerStub(responses: [.failure(.timedOut)])

        let result = await makeClient(runner: runner).listWorkspaces()

        XCTAssertEqual(result.failure, .timedOut)
    }

    private func makeClient(runner: AeroSpaceCommandRunnerStub) -> AeroSpaceClient {
        AeroSpaceClient(
            commandRunner: runner,
            executableCandidates: [URL(filePath: "/usr/bin/true")]
        )
    }
}

@MainActor
private final class AeroSpaceCommandRunnerStub: AeroSpaceCommandRunning {
    struct Invocation {
        let executableURL: URL
        let arguments: [String]
        let timeout: Duration
    }

    private var responses: [Result<AeroSpaceCommandResult, AeroSpaceClientError>]
    private(set) var invocations: [Invocation] = []

    init(responses: [Result<AeroSpaceCommandResult, AeroSpaceClientError>]) {
        self.responses = responses
    }

    func run(
        executableURL: URL,
        arguments: [String],
        timeout: Duration
    ) async -> Result<AeroSpaceCommandResult, AeroSpaceClientError> {
        invocations.append(Invocation(executableURL: executableURL, arguments: arguments, timeout: timeout))
        return responses.removeFirst()
    }
}

private func commandResult(
    exitCode: Int32 = 0,
    output: String = "",
    error: String = ""
) -> AeroSpaceCommandResult {
    AeroSpaceCommandResult(
        exitCode: exitCode,
        standardOutput: Data(output.utf8),
        standardError: Data(error.utf8)
    )
}

private extension Result {
    var failure: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}
