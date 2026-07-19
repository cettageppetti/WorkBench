import Foundation

protocol ConfigurationDirectoryProviding {
    func withConfigurationDirectoryAccess<Result>(
        _ operation: (URL) throws -> Result
    ) throws -> Result
}

extension ConfigurationDirectoryAccess: ConfigurationDirectoryProviding {}

struct FixedConfigurationDirectory: ConfigurationDirectoryProviding {
    let url: URL

    func withConfigurationDirectoryAccess<Result>(
        _ operation: (URL) throws -> Result
    ) throws -> Result {
        try operation(url)
    }
}

protocol RepositoryInitializationStoring {
    var isInitialized: Bool { get }
    func markInitialized()
}

struct UserDefaultsRepositoryInitializationStore: RepositoryInitializationStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "applicationSupportProjectRepositoryInitialized") {
        self.defaults = defaults
        self.key = key
    }

    var isInitialized: Bool {
        defaults.bool(forKey: key)
    }

    func markInitialized() {
        defaults.set(true, forKey: key)
    }
}

protocol ProjectDataWriting {
    func write(_ data: Data, to url: URL) throws
}

struct AtomicProjectDataWriter: ProjectDataWriting {
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

struct ProjectFileIssue: Identifiable {
    var id: URL { fileURL }
    let fileURL: URL
    let message: String
}

struct ProjectRepositorySnapshot {
    let projects: [Project]
    let issues: [ProjectFileIssue]
}

@MainActor
protocol ProjectRepositorying: AnyObject {
    func load() throws -> ProjectRepositorySnapshot
    func save(_ project: Project) throws
    func delete(_ project: Project) throws
}

enum ProjectRepositoryError: LocalizedError {
    case invalidProject([ProjectValidationIssue])
    case duplicateProjectName(String)
    case duplicateProjectIdentifier(ProjectID)
    case incorrectFilename(expected: String)

    var errorDescription: String? {
        switch self {
        case let .invalidProject(issues):
            issues.map { "\($0.field): \($0.message)" }.joined(separator: "\n")
        case let .duplicateProjectName(name):
            "A Project named \"\(name)\" already exists."
        case let .duplicateProjectIdentifier(id):
            "Project identifier \(id.rawValue.uuidString) is duplicated."
        case let .incorrectFilename(expected):
            "The filename does not match the Project identifier. Rename the file to \(expected)."
        }
    }
}

@MainActor
final class ProjectRepository {
    private let directoryProvider: any ConfigurationDirectoryProviding
    private let initializationStore: any RepositoryInitializationStoring
    private let writer: any ProjectDataWriting
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        directoryProvider: any ConfigurationDirectoryProviding,
        initializationStore: any RepositoryInitializationStoring = UserDefaultsRepositoryInitializationStore(),
        writer: any ProjectDataWriting = AtomicProjectDataWriter(),
        fileManager: FileManager = .default
    ) {
        self.directoryProvider = directoryProvider
        self.initializationStore = initializationStore
        self.writer = writer
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
        decoder = JSONDecoder()
    }

    func load() throws -> ProjectRepositorySnapshot {
        try directoryProvider.withConfigurationDirectoryAccess { directory in
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var fileURLs = try configurationFileURLs(in: directory)

            if fileURLs.isEmpty && !initializationStore.isInitialized {
                let starter = Project.starter()
                try persist(starter, in: directory)
                initializationStore.markInitialized()
                fileURLs = [directory.appending(path: starter.filename)]
            }

            return load(fileURLs: fileURLs)
        }
    }

    func save(_ project: Project) throws {
        let validationIssues = ProjectValidator.validate(project)
        guard validationIssues.isEmpty else {
            throw ProjectRepositoryError.invalidProject(validationIssues)
        }

        try directoryProvider.withConfigurationDirectoryAccess { directory in
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let snapshot = load(fileURLs: try configurationFileURLs(in: directory))

            for existing in snapshot.projects where existing.id != project.id {
                if normalized(existing.name) == normalized(project.name) {
                    throw ProjectRepositoryError.duplicateProjectName(project.name)
                }
            }

            try persist(project, in: directory)
        }
    }

    func delete(_ project: Project) throws {
        try directoryProvider.withConfigurationDirectoryAccess { directory in
            let fileURL = directory.appending(path: project.filename)
            try fileManager.removeItem(at: fileURL)
        }
    }

    private func persist(_ project: Project, in directory: URL) throws {
        let data = try encoder.encode(project)
        try writer.write(data, to: directory.appending(path: project.filename))
    }

    private func configurationFileURLs(in directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension.lowercased() == "json" }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func load(fileURLs: [URL]) -> ProjectRepositorySnapshot {
        var loaded: [(url: URL, project: Project)] = []
        var issues: [ProjectFileIssue] = []

        for fileURL in fileURLs {
            do {
                let project = try decoder.decode(Project.self, from: Data(contentsOf: fileURL))
                guard fileURL.lastPathComponent == project.filename else {
                    throw ProjectRepositoryError.incorrectFilename(expected: project.filename)
                }
                let validationIssues = ProjectValidator.validate(project)
                guard validationIssues.isEmpty else {
                    throw ProjectRepositoryError.invalidProject(validationIssues)
                }
                loaded.append((fileURL, project))
            } catch {
                issues.append(ProjectFileIssue(fileURL: fileURL, message: error.localizedDescription))
            }
        }

        let duplicateNames = duplicateValues(loaded.map { normalized($0.project.name) })
        let duplicateIDs = duplicateValues(loaded.map(\.project.id))
        var validProjects: [Project] = []

        for entry in loaded {
            if duplicateIDs.contains(entry.project.id) {
                issues.append(
                    ProjectFileIssue(
                        fileURL: entry.url,
                        message: ProjectRepositoryError
                            .duplicateProjectIdentifier(entry.project.id)
                            .localizedDescription
                    )
                )
            } else if duplicateNames.contains(normalized(entry.project.name)) {
                issues.append(
                    ProjectFileIssue(
                        fileURL: entry.url,
                        message: ProjectRepositoryError
                            .duplicateProjectName(entry.project.name)
                            .localizedDescription
                    )
                )
            } else {
                validProjects.append(entry.project)
            }
        }

        validProjects.sort {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        issues.sort {
            $0.fileURL.lastPathComponent.localizedStandardCompare($1.fileURL.lastPathComponent)
                == .orderedAscending
        }
        return ProjectRepositorySnapshot(projects: validProjects, issues: issues)
    }

    private func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    private func duplicateValues<Value: Hashable>(_ values: [Value]) -> Set<Value> {
        var seen: Set<Value> = []
        var duplicates: Set<Value> = []
        for value in values where !seen.insert(value).inserted {
            duplicates.insert(value)
        }
        return duplicates
    }
}

extension ProjectRepository: ProjectRepositorying {}
