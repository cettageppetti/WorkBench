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
protocol ApplicationLaunching {
    func open(_ application: ApplicationResource) async -> String?
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
        set chromeWasRunning to application "Google Chrome" is running
        tell application "Google Chrome"
            if chromeWasRunning then
                set createdWindow to make new window
            else
                repeat 100 times
                    if (count of windows) > 0 then exit repeat
                    delay 0.05
                end repeat
                if (count of windows) > 0 then
                    set createdWindow to front window
                else
                    set createdWindow to make new window
                end if
            end if
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
        if terminal.workingDirectory == "~" || terminal.workingDirectory == "~/" {
            return executor.execute(source: """
            tell application "Terminal"
                do script ""
                activate
            end tell
            """)
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
struct FoundationApplicationLauncher: ApplicationLaunching {
    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(workspace: NSWorkspace = .shared, fileManager: FileManager = .default) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func open(_ application: ApplicationResource) async -> String? {
        guard let url = applicationURL(for: application) else {
            return "The application is not installed or its saved location is unavailable."
        }
        return await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            workspace.openApplication(at: url, configuration: configuration) { _, error in
                continuation.resume(returning: error?.localizedDescription)
            }
        }
    }

    private func applicationURL(for application: ApplicationResource) -> URL? {
        if let registered = workspace.urlForApplication(
            withBundleIdentifier: application.bundleIdentifier
        ) {
            return registered
        }

        let fallback = URL(filePath: application.lastKnownPath)
        guard fileManager.fileExists(atPath: fallback.path),
              Bundle(url: fallback)?.bundleIdentifier == application.bundleIdentifier else {
            return nil
        }
        return fallback
    }
}

@MainActor
final class ProjectLauncher {
    private let browserLauncher: any BrowserLaunching
    private let chromeLauncher: any BrowserLaunching
    private let terminalLauncher: any TerminalLaunching
    private let finderLauncher: any FinderLaunching
    private let applicationLauncher: any ApplicationLaunching
    private let aeroSpaceWindowController: any AeroSpaceWindowControlling
    private let aeroSpaceWorkspaceController: any AeroSpaceControlling
    private let windowDetectionAttempts: Int
    private let windowDetectionInterval: Duration

    init(
        browserLauncher: any BrowserLaunching = SafariLauncher(),
        chromeLauncher: any BrowserLaunching = ChromeLauncher(),
        terminalLauncher: any TerminalLaunching = TerminalLauncher(),
        finderLauncher: any FinderLaunching = FinderLauncher(),
        applicationLauncher: any ApplicationLaunching = FoundationApplicationLauncher(),
        aeroSpaceWindowController: any AeroSpaceWindowControlling = AeroSpaceClient(),
        aeroSpaceWorkspaceController: any AeroSpaceControlling = AeroSpaceClient(),
        windowDetectionAttempts: Int = 20,
        windowDetectionInterval: Duration = .milliseconds(50)
    ) {
        self.browserLauncher = browserLauncher
        self.chromeLauncher = chromeLauncher
        self.terminalLauncher = terminalLauncher
        self.finderLauncher = finderLauncher
        self.applicationLauncher = applicationLauncher
        self.aeroSpaceWindowController = aeroSpaceWindowController
        self.aeroSpaceWorkspaceController = aeroSpaceWorkspaceController
        self.windowDetectionAttempts = max(1, windowDetectionAttempts)
        self.windowDetectionInterval = windowDetectionInterval
    }

    func open(
        _ project: Project,
        placementWorkspace: String? = nil
    ) async -> LaunchReport {
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
            let outcome = await launch(resource, placementWorkspace: placementWorkspace)
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

    private func launch(
        _ resource: Resource,
        placementWorkspace: String?
    ) async -> ResourceLaunchOutcome {
        guard let placementWorkspace else { return await launchUnplaced(resource) }
        guard let bundleIdentifier = applicationBundleIdentifier(for: resource) else {
            return await launchUnplaced(resource)
        }

        let beforeResult = await aeroSpaceWindowController
            .listWindows(forApplicationBundleIdentifier: bundleIdentifier)
        guard case let .success(beforeWindows) = beforeResult else {
            let error = beforeResult.failure ?? .invalidResponse
            return .failed("WorkBench could not prepare window placement: \(error.recoveryMessage)")
        }

        let launchOutcome = await launchUnplaced(resource)
        guard launchOutcome == .succeeded else { return launchOutcome }

        switch await detectCreatedWindow(
            bundleIdentifier: bundleIdentifier,
            previousIDs: Set(beforeWindows.map(\.id))
        ) {
        case let .success(window):
            switch await aeroSpaceWindowController.moveWindow(
                id: window.id,
                toWorkspace: placementWorkspace
            ) {
            case .success:
                break
            case let .failure(error):
                return await placementFailureAfterWindowOpened(
                    error.recoveryMessage,
                    workspace: placementWorkspace
                )
            }
        case let .failure(error):
            return await placementFailureAfterWindowOpened(
                error.message,
                workspace: placementWorkspace
            )
        }

        switch await aeroSpaceWorkspaceController.activateWorkspace(named: placementWorkspace) {
        case .success:
            return .succeeded
        case let .failure(error):
            return .failed(
                "The window was placed, but WorkBench could not restore the Project workspace: "
                    + error.recoveryMessage
            )
        }
    }

    private func placementFailureAfterWindowOpened(
        _ message: String,
        workspace: String
    ) async -> ResourceLaunchOutcome {
        let placementMessage = "The window opened, but WorkBench could not place it: \(message)"
        switch await aeroSpaceWorkspaceController.activateWorkspace(named: workspace) {
        case .success:
            return .failed(placementMessage)
        case let .failure(error):
            return .failed(
                placementMessage
                    + " WorkBench also could not restore the Project workspace: "
                    + error.recoveryMessage
            )
        }
    }

    private func launchUnplaced(_ resource: Resource) async -> ResourceLaunchOutcome {
        switch resource.payload {
        case let .browserWindow(browser):
            launchOutcome(for: browserLauncher.open(browser))
        case let .chromeWindow(browser):
            launchOutcome(for: chromeLauncher.open(browser))
        case let .terminalSession(terminal):
            launchOutcome(for: terminalLauncher.open(terminal))
        case let .finderWindow(finder):
            launchOutcome(for: finderLauncher.open(finder))
        case let .application(application):
            launchOutcome(for: await applicationLauncher.open(application))
        case let .unsupported(type, _):
            .skipped("Resource type \"\(type)\" is unsupported.")
        }
    }

    private func detectCreatedWindow(
        bundleIdentifier: String,
        previousIDs: Set<Int>
    ) async -> Result<AeroSpaceWindow, WindowDetectionError> {
        for attempt in 0..<windowDetectionAttempts {
            switch await aeroSpaceWindowController
                .listWindows(forApplicationBundleIdentifier: bundleIdentifier) {
            case let .success(windows):
                let candidates = windows.filter { !previousIDs.contains($0.id) }
                if candidates.count == 1, let window = candidates.first {
                    return .success(window)
                }
                if candidates.count > 1 {
                    let identifiers = candidates.map(\.id).sorted().map(String.init).joined(separator: ", ")
                    return .failure(
                        WindowDetectionError(
                            message: "AeroSpace reported multiple new windows (\(identifiers)); no window was moved."
                        )
                    )
                }
            case let .failure(error):
                return .failure(WindowDetectionError(message: error.recoveryMessage))
            }

            if attempt + 1 < windowDetectionAttempts {
                try? await Task.sleep(for: windowDetectionInterval)
            }
        }
        return .failure(
            WindowDetectionError(
                message: "AeroSpace did not detect the new application window before the timeout."
            )
        )
    }

    private func applicationBundleIdentifier(for resource: Resource) -> String? {
        switch resource.payload {
        case .browserWindow: "com.apple.Safari"
        case .chromeWindow: "com.google.Chrome"
        case .terminalSession: "com.apple.Terminal"
        case .finderWindow: "com.apple.finder"
        case let .application(application): application.bundleIdentifier
        case .unsupported: nil
        }
    }

    private func launchOutcome(for errorMessage: String?) -> ResourceLaunchOutcome {
        errorMessage.map(ResourceLaunchOutcome.failed) ?? .succeeded
    }
}

private struct WindowDetectionError: Error {
    let message: String
}

private extension Result {
    var failure: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
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
