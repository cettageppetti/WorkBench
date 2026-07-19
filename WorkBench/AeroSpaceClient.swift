import Foundation

enum AeroSpaceClientError: Error, Equatable {
    case executableUnavailable
    case processCouldNotStart(String)
    case timedOut
    case commandFailed(exitCode: Int32, message: String)
    case invalidResponse
    case workspaceNotFocused(expected: String, actual: String?)
}

extension AeroSpaceClientError {
    var recoveryMessage: String {
        switch self {
        case .executableUnavailable:
            "The AeroSpace command-line tool was not found in a standard Homebrew location."
        case let .processCouldNotStart(message):
            "WorkBench could not start AeroSpace: \(message)"
        case .timedOut:
            "AeroSpace did not respond before the operation timed out."
        case let .commandFailed(_, message):
            "AeroSpace could not activate the workspace: \(message)"
        case .invalidResponse:
            "AeroSpace returned a response that WorkBench could not understand."
        case let .workspaceNotFocused(expected, actual):
            if let actual {
                "AeroSpace focused workspace \"\(actual)\" instead of \"\(expected)\"."
            } else {
                "AeroSpace did not report a focused workspace after activating \"\(expected)\"."
            }
        }
    }
}

protocol AeroSpaceControlling {
    func listWorkspaces() async -> Result<[String], AeroSpaceClientError>
    func activateWorkspace(named workspace: String) async -> Result<Void, AeroSpaceClientError>
}

struct AeroSpaceCommandResult: Equatable {
    let exitCode: Int32
    let standardOutput: Data
    let standardError: Data
}

protocol AeroSpaceCommandRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        timeout: Duration
    ) async -> Result<AeroSpaceCommandResult, AeroSpaceClientError>
}

struct FoundationAeroSpaceCommandRunner: AeroSpaceCommandRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        timeout: Duration
    ) async -> Result<AeroSpaceCommandResult, AeroSpaceClientError> {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            return .failure(.processCouldNotStart(error.localizedDescription))
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while process.isRunning && clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard !process.isRunning else {
            process.terminate()
            return .failure(.timedOut)
        }

        return .success(
            AeroSpaceCommandResult(
                exitCode: process.terminationStatus,
                standardOutput: standardOutput.fileHandleForReading.readDataToEndOfFile(),
                standardError: standardError.fileHandleForReading.readDataToEndOfFile()
            )
        )
    }
}

struct AeroSpaceClient: AeroSpaceControlling {
    private let commandRunner: any AeroSpaceCommandRunning
    private let fileManager: FileManager
    private let executableCandidates: [URL]
    private let commandTimeout: Duration

    init(
        commandRunner: any AeroSpaceCommandRunning = FoundationAeroSpaceCommandRunner(),
        fileManager: FileManager = .default,
        executableCandidates: [URL] = [
            URL(filePath: "/opt/homebrew/bin/aerospace"),
            URL(filePath: "/usr/local/bin/aerospace")
        ],
        commandTimeout: Duration = .seconds(5)
    ) {
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.executableCandidates = executableCandidates
        self.commandTimeout = commandTimeout
    }

    func listWorkspaces() async -> Result<[String], AeroSpaceClientError> {
        switch await execute(["list-workspaces", "--all", "--json"]) {
        case let .success(result):
            guard let workspaces = decodeWorkspaces(result.standardOutput) else {
                return .failure(.invalidResponse)
            }
            return .success(workspaces)
        case let .failure(error):
            return .failure(error)
        }
    }

    func activateWorkspace(named workspace: String) async -> Result<Void, AeroSpaceClientError> {
        guard !workspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.workspaceNotFocused(expected: workspace, actual: nil))
        }
        switch await execute(["workspace", "--", workspace]) {
        case .success:
            break
        case let .failure(error):
            return .failure(error)
        }

        switch await execute(["list-workspaces", "--focused", "--json"]) {
        case let .success(result):
            guard let focused = decodeWorkspaces(result.standardOutput)?.first else {
                return .failure(.invalidResponse)
            }
            guard focused == workspace else {
                return .failure(.workspaceNotFocused(expected: workspace, actual: focused))
            }
            return .success(())
        case let .failure(error):
            return .failure(error)
        }
    }

    private func execute(_ arguments: [String]) async -> Result<AeroSpaceCommandResult, AeroSpaceClientError> {
        guard let executableURL = executableCandidates.first(where: {
            fileManager.isExecutableFile(atPath: $0.path)
        }) else {
            return .failure(.executableUnavailable)
        }
        switch await commandRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            timeout: commandTimeout
        ) {
        case let .success(result) where result.exitCode == 0:
            return .success(result)
        case let .success(result):
            let errorText = String(data: result.standardError, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(
                .commandFailed(
                    exitCode: result.exitCode,
                    message: errorText.flatMap { $0.isEmpty ? nil : $0 } ?? "AeroSpace command failed."
                )
            )
        case let .failure(error):
            return .failure(error)
        }
    }

    private func decodeWorkspaces(_ data: Data) -> [String]? {
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let array = value as? [Any] else { return nil }
        if let names = array as? [String] {
            return names
        }
        return array.compactMap { item in
            (item as? [String: Any])?["workspace"] as? String
        }.count == array.count
            ? array.compactMap { ($0 as? [String: Any])?["workspace"] as? String }
            : nil
    }
}
