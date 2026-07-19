import Foundation
import Darwin

struct ProjectValidationIssue: Equatable {
    let field: String
    let message: String
}

enum ProjectPathError: LocalizedError, Equatable {
    case relativePath

    var errorDescription: String? {
        "Use an absolute path or a home-relative path beginning with ~/."
    }
}

struct ProjectPath: Equatable {
    let storedValue: String

    init(_ storedValue: String) throws {
        guard storedValue.hasPrefix("/")
                || storedValue == "~"
                || storedValue.hasPrefix("~/") else {
            throw ProjectPathError.relativePath
        }
        self.storedValue = storedValue
    }

    func resolved(homeDirectory: URL? = nil) -> URL {
        let homeDirectory = homeDirectory ?? LoginHomeDirectory.current
        if storedValue == "~" || storedValue == "~/" {
            return homeDirectory
        }
        if storedValue.hasPrefix("~/") {
            return homeDirectory.appending(path: String(storedValue.dropFirst(2)))
        }
        return URL(filePath: storedValue)
    }
}

enum LoginHomeDirectory {
    static var current: URL {
        if let passwordEntry = getpwuid(getuid()),
           let directory = passwordEntry.pointee.pw_dir {
            return URL(filePath: String(cString: directory), directoryHint: .isDirectory)
        }
        return URL(filePath: NSHomeDirectoryForUser(NSUserName()) ?? NSHomeDirectory(), directoryHint: .isDirectory)
    }
}

enum ProjectValidator {
    static func validate(_ project: Project) -> [ProjectValidationIssue] {
        var issues: [ProjectValidationIssue] = []

        if project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.init(field: "name", message: "Project name is required."))
        }

        if case let .aeroSpaceWorkspace(workspace) = project.launchDestination,
           workspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                .init(
                    field: "launchDestination.workspace",
                    message: "AeroSpace workspace name is required."
                )
            )
        }

        let duplicateResourceIDs = duplicates(in: project.resources.map(\.id))
        for duplicateID in duplicateResourceIDs {
            issues.append(
                .init(
                    field: "resources.id",
                    message: "Duplicate Resource identifier \(duplicateID.rawValue.uuidString)."
                )
            )
        }

        for (index, resource) in project.resources.enumerated() {
            let prefix = "resources[\(index)]"
            if resource.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(.init(field: "\(prefix).name", message: "Resource name is required."))
            }

            switch resource.payload {
            case let .browserWindow(browser):
                validateBrowser(browser, applicationName: "Safari", prefix: prefix, issues: &issues)
            case let .chromeWindow(browser):
                validateBrowser(browser, applicationName: "Chrome", prefix: prefix, issues: &issues)
            case let .terminalSession(terminal):
                validatePath(terminal.workingDirectory, field: "\(prefix).workingDirectory", into: &issues)
            case let .finderWindow(finder):
                validatePath(finder.folder, field: "\(prefix).folder", into: &issues)
            case let .application(application):
                if application.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(
                        .init(field: "\(prefix).bundleIdentifier", message: "Application bundle identifier is required.")
                    )
                }
                let path = application.lastKnownPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.hasPrefix("/") || URL(filePath: path).pathExtension.lowercased() != "app" {
                    issues.append(
                        .init(field: "\(prefix).lastKnownPath", message: "Choose a macOS application bundle.")
                    )
                }
            case .unsupported:
                break
            }
        }

        return issues
    }

    private static func validateBrowser(
        _ browser: BrowserWindow,
        applicationName: String,
        prefix: String,
        issues: inout [ProjectValidationIssue]
    ) {
        if browser.tabs.isEmpty {
            issues.append(
                .init(field: "\(prefix).tabs", message: "At least one \(applicationName) tab is required.")
            )
        }
        for (tabIndex, tab) in browser.tabs.enumerated()
            where URL(string: tab)?.scheme == nil {
            issues.append(
                .init(
                    field: "\(prefix).tabs[\(tabIndex)]",
                    message: "Enter a URL \(applicationName) can open."
                )
            )
        }
    }

    static func validateCollection(_ projects: [Project]) -> [ProjectValidationIssue] {
        var issues = projects.flatMap(validate)
        let normalizedNames = projects.map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        }
        for duplicateName in duplicates(in: normalizedNames) where !duplicateName.isEmpty {
            issues.append(
                .init(field: "projects.name", message: "Project name \"\(duplicateName)\" is not unique.")
            )
        }
        for duplicateID in duplicates(in: projects.map(\.id)) {
            issues.append(
                .init(
                    field: "projects.id",
                    message: "Duplicate Project identifier \(duplicateID.rawValue.uuidString)."
                )
            )
        }
        return issues
    }

    private static func validatePath(
        _ value: String,
        field: String,
        into issues: inout [ProjectValidationIssue]
    ) {
        do {
            _ = try ProjectPath(value)
        } catch {
            issues.append(.init(field: field, message: error.localizedDescription))
        }
    }

    private static func duplicates<Value: Hashable>(in values: [Value]) -> Set<Value> {
        var seen: Set<Value> = []
        var duplicates: Set<Value> = []
        for value in values where !seen.insert(value).inserted {
            duplicates.insert(value)
        }
        return duplicates
    }
}
