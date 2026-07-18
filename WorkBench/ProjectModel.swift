import Foundation

struct ProjectID: Codable, Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct ResourceID: Codable, Equatable, Hashable, Sendable {
    let rawValue: UUID

    init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(UUID.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct Project: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: ProjectID
    var name: String
    var resources: [Resource]

    init(
        id: ProjectID = ProjectID(),
        name: String,
        resources: [Resource],
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.resources = resources
    }

    var filename: String {
        "\(id.rawValue.uuidString.lowercased()).json"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)

        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported schema version \(schemaVersion)."
            )
        }

        id = try container.decode(ProjectID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        resources = try container.decode([Resource].self, forKey: .resources)
    }
}

struct BrowserWindow: Codable, Equatable {
    var tabs: [String]
}

struct TerminalSession: Codable, Equatable {
    var workingDirectory: String
}

struct FinderWindow: Codable, Equatable {
    var folder: String
}

enum ResourcePayload: Equatable {
    case browserWindow(BrowserWindow)
    case chromeWindow(BrowserWindow)
    case terminalSession(TerminalSession)
    case finderWindow(FinderWindow)
    case unsupported(type: String, rawObject: [String: JSONValue])
}

struct Resource: Codable, Equatable {
    let id: ResourceID
    var name: String
    var payload: ResourcePayload

    var type: String {
        switch payload {
        case .browserWindow:
            "browser-window"
        case .chromeWindow:
            "chrome-window"
        case .terminalSession:
            "terminal-session"
        case .finderWindow:
            "finder-window"
        case let .unsupported(type, _):
            type
        }
    }

    init(id: ResourceID = ResourceID(), name: String, payload: ResourcePayload) {
        self.id = id
        self.name = name
        self.payload = payload
    }

    init(from decoder: any Decoder) throws {
        let rawValue = try JSONValue(from: decoder)
        guard let object = rawValue.objectValue else {
            throw DecodingError.typeMismatch(
                [String: JSONValue].self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "A Resource must be a JSON object."
                )
            )
        }

        guard let type = object["type"]?.stringValue else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "A Resource requires a string type."
                )
            )
        }

        let common = try decoder.container(keyedBy: CodingKeys.self)
        id = try common.decode(ResourceID.self, forKey: .id)
        name = try common.decode(String.self, forKey: .name)

        switch type {
        case "browser-window":
            payload = .browserWindow(
                BrowserWindow(tabs: try common.decode([String].self, forKey: .tabs))
            )
        case "chrome-window":
            payload = .chromeWindow(
                BrowserWindow(tabs: try common.decode([String].self, forKey: .tabs))
            )
        case "terminal-session":
            payload = .terminalSession(
                TerminalSession(
                    workingDirectory: try common.decode(String.self, forKey: .workingDirectory)
                )
            )
        case "finder-window":
            payload = .finderWindow(
                FinderWindow(folder: try common.decode(String.self, forKey: .folder))
            )
        default:
            payload = .unsupported(type: type, rawObject: object)
        }
    }

    func encode(to encoder: any Encoder) throws {
        if case let .unsupported(_, rawObject) = payload {
            try JSONValue.object(rawObject).encode(to: encoder)
            return
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)

        switch payload {
        case let .browserWindow(browser):
            try container.encode(browser.tabs, forKey: .tabs)
        case let .chromeWindow(browser):
            try container.encode(browser.tabs, forKey: .tabs)
        case let .terminalSession(terminal):
            try container.encode(terminal.workingDirectory, forKey: .workingDirectory)
        case let .finderWindow(finder):
            try container.encode(finder.folder, forKey: .folder)
        case .unsupported:
            break
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case tabs
        case workingDirectory
        case folder
    }
}

extension Project {
    static func starter() -> Project {
        Project(
            name: "Starter Project",
            resources: [
                Resource(
                    name: "Web",
                    payload: .browserWindow(
                        BrowserWindow(tabs: ["https://apple.com", "https://ibm.com"])
                    )
                ),
                Resource(
                    name: "Home Terminal",
                    payload: .terminalSession(TerminalSession(workingDirectory: "~/"))
                ),
                Resource(
                    name: "Home Folder",
                    payload: .finderWindow(FinderWindow(folder: "~/"))
                )
            ]
        )
    }

    func duplicated(named duplicateName: String) -> Project {
        Project(
            name: duplicateName,
            resources: resources.map { resource in
                Resource(id: ResourceID(), name: resource.name, payload: resource.payload)
            }
        )
    }
}
