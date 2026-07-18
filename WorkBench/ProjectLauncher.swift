import AppKit
import Foundation

enum ResourceLaunchOutcome: Equatable {
    case succeeded
    case failed(String)
    case skipped(String)
}

struct ResourceLaunchResult: Equatable, Identifiable {
    let resourceID: ResourceID
    let resourceName: String
    let resourceType: String
    let outcome: ResourceLaunchOutcome

    var id: ResourceID { resourceID }
}

struct LaunchReport: Equatable, Identifiable {
    let projectID: ProjectID
    let projectName: String
    let validationIssues: [ProjectValidationIssue]
    let results: [ResourceLaunchResult]

    var id: ProjectID { projectID }

    var didLaunch: Bool { validationIssues.isEmpty }
    var hasProblems: Bool {
        !validationIssues.isEmpty || results.contains { result in
            switch result.outcome {
            case .succeeded: false
            case .failed, .skipped: true
            }
        }
    }
}

@MainActor
protocol BrowserLaunching {
    func open(_ browser: BrowserWindow) -> String?
}

@MainActor
protocol TerminalLaunching {
    func open(_ terminal: TerminalSession) -> String?
}

@MainActor
protocol FinderLaunching {
    func open(_ finder: FinderWindow) -> String?
}

@MainActor
protocol AppleScriptExecuting {
    func execute(source: String) -> String?
}

@MainActor
struct FoundationAppleScriptExecutor: AppleScriptExecuting {
    func execute(source: String) -> String? {
        guard let script = NSAppleScript(source: source) else {
            return "The automation script could not be created."
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return nil }
        return error[NSAppleScript.errorMessage] as? String ?? "The automation request failed."
    }
}

@MainActor
struct SafariLauncher: BrowserLaunching {
    private let executor: any AppleScriptExecuting

    init(executor: any AppleScriptExecuting = FoundationAppleScriptExecutor()) {
        self.executor = executor
    }

    func open(_ browser: BrowserWindow) -> String? {
        guard let firstURL = browser.tabs.first else { return "At least one Safari tab is required." }
        let additionalTabs = browser.tabs.dropFirst().map { url in
            "set createdTab to make new tab at end of tabs with properties {URL:\(appleScriptLiteral(url))}"
        }.joined(separator: "\n        ")
        let selectLastTab = browser.tabs.count > 1 ? "set current tab to createdTab" : ""
        return executor.execute(source: """
        tell application "Safari"
            activate
            make new document with properties {URL:\(appleScriptLiteral(firstURL))}
            tell front window
                \(additionalTabs)
                \(selectLastTab)
            end tell
        end tell
        """)
    }
}

@MainActor
struct ChromeLauncher: BrowserLaunching {
    private let executor: any AppleScriptExecuting

    init(executor: any AppleScriptExecuting = FoundationAppleScriptExecutor()) {
        self.executor = executor
    }

    func open(_ browser: BrowserWindow) -> String? {
        guard let firstURL = browser.tabs.first else { return "At least one Chrome tab is required." }
        let additionalTabs = browser.tabs.dropFirst().map { url in
            "make new tab at end of tabs with properties {URL:\(appleScriptLiteral(url))}"
        }.joined(separator: "\n        ")
        let selectLastTab = browser.tabs.count > 1
            ? "set active tab index to count of tabs"
            : ""
        return executor.execute(source: """
        tell application "Google Chrome"
            set createdWindow to make new window
            tell createdWindow
                set URL of active tab to \(appleScriptLiteral(firstURL))
                \(additionalTabs)
                \(selectLastTab)
            end tell
            activate
        end tell
        """)
    }
}

@MainActor
struct TerminalLauncher: TerminalLaunching {
    private let executor: any AppleScriptExecuting
    private let fileManager: FileManager

    init(
        executor: any AppleScriptExecuting = FoundationAppleScriptExecutor(),
        fileManager: FileManager = .default
    ) {
        self.executor = executor
        self.fileManager = fileManager
    }

    func open(_ terminal: TerminalSession) -> String? {
        guard let directory = resolveDirectory(terminal.workingDirectory, fileManager: fileManager) else {
            return "The working directory does not exist or is not a folder."
        }
        return executor.execute(source: """
        tell application "Terminal"
            do script ("cd -- " & quoted form of \(appleScriptLiteral(directory.path)))
            activate
        end tell
        """)
    }
}

@MainActor
struct FinderLauncher: FinderLaunching {
    private let executor: any AppleScriptExecuting
    private let fileManager: FileManager

    init(
        executor: any AppleScriptExecuting = FoundationAppleScriptExecutor(),
        fileManager: FileManager = .default
    ) {
        self.executor = executor
        self.fileManager = fileManager
    }

    func open(_ finder: FinderWindow) -> String? {
        guard let directory = resolveDirectory(finder.folder, fileManager: fileManager) else {
            return "The Finder folder does not exist or is not a folder."
        }
        return executor.execute(source: """
        tell application "Finder"
            activate
            set targetFolder to POSIX file \(appleScriptLiteral(directory.path)) as alias
            make new Finder window to targetFolder
        end tell
        """)
    }
}

@MainActor
final class ProjectLauncher {
    private let browserLauncher: any BrowserLaunching
    private let chromeLauncher: any BrowserLaunching
    private let terminalLauncher: any TerminalLaunching
    private let finderLauncher: any FinderLaunching

    init(
        browserLauncher: any BrowserLaunching = SafariLauncher(),
        chromeLauncher: any BrowserLaunching = ChromeLauncher(),
        terminalLauncher: any TerminalLaunching = TerminalLauncher(),
        finderLauncher: any FinderLaunching = FinderLauncher()
    ) {
        self.browserLauncher = browserLauncher
        self.chromeLauncher = chromeLauncher
        self.terminalLauncher = terminalLauncher
        self.finderLauncher = finderLauncher
    }

    func open(_ project: Project) -> LaunchReport {
        let validationIssues = ProjectValidator.validate(project)
        guard validationIssues.isEmpty else {
            return LaunchReport(
                projectID: project.id,
                projectName: project.name,
                validationIssues: validationIssues,
                results: []
            )
        }

        var results: [ResourceLaunchResult] = []
        for resource in project.resources {
            let outcome: ResourceLaunchOutcome
            switch resource.payload {
            case let .browserWindow(browser):
                outcome = launchOutcome(for: browserLauncher.open(browser))
            case let .chromeWindow(browser):
                outcome = launchOutcome(for: chromeLauncher.open(browser))
            case let .terminalSession(terminal):
                outcome = launchOutcome(for: terminalLauncher.open(terminal))
            case let .finderWindow(finder):
                outcome = launchOutcome(for: finderLauncher.open(finder))
            case let .unsupported(type, _):
                outcome = .skipped("Resource type \"\(type)\" is unsupported.")
            }
            results.append(
                ResourceLaunchResult(
                    resourceID: resource.id,
                    resourceName: resource.name,
                    resourceType: resource.type,
                    outcome: outcome
                )
            )
        }
        return LaunchReport(
            projectID: project.id,
            projectName: project.name,
            validationIssues: [],
            results: results
        )
    }

    private func launchOutcome(for errorMessage: String?) -> ResourceLaunchOutcome {
        errorMessage.map(ResourceLaunchOutcome.failed) ?? .succeeded
    }
}

private func appleScriptLiteral(_ value: String) -> String {
    let escaped = value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\n", with: "\\n")
    return "\"\(escaped)\""
}

private func resolveDirectory(_ storedPath: String, fileManager: FileManager) -> URL? {
    guard let path = try? ProjectPath(storedPath) else { return nil }
    let url = path.resolved()
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
          isDirectory.boolValue else { return nil }
    return url
}
