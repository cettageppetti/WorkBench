import Foundation
import Darwin
import XCTest
@testable import WorkBench

@MainActor
final class ProjectModelTests: XCTestCase {
    func testStarterProjectMatchesAcceptanceScenario() {
        let project = Project.starter()

        XCTAssertEqual(project.schemaVersion, 2)
        XCTAssertNil(project.launchDestination)
        XCTAssertEqual(project.name, "Starter Project")
        XCTAssertEqual(project.resources.map(\.type), [
            "browser-window", "terminal-session", "finder-window"
        ])
        XCTAssertEqual(
            project.resources[0].payload,
            .browserWindow(BrowserWindow(tabs: ["https://apple.com", "https://ibm.com"]))
        )
        XCTAssertEqual(
            project.resources[1].payload,
            .terminalSession(TerminalSession(workingDirectory: "~/"))
        )
        XCTAssertEqual(
            project.resources[2].payload,
            .finderWindow(FinderWindow(folder: "~/"))
        )
        XCTAssertTrue(ProjectValidator.validate(project).isEmpty)
    }

    func testSupportedResourcesRoundTrip() throws {
        var project = Project.starter()
        project.resources.append(
            Resource(
                name: "Chrome Research",
                payload: .chromeWindow(BrowserWindow(tabs: ["https://google.com", "file:///tmp/example"]))
            )
        )
        project.resources.append(
            Resource(
                name: "iMovie",
                payload: .application(
                    ApplicationResource(
                        bundleIdentifier: "com.apple.iMovie",
                        lastKnownPath: "/Applications/iMovie.app"
                    )
                )
            )
        )
        let encoded = try encoder.encode(project)
        let decoded = try decoder.decode(Project.self, from: encoded)

        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.resources[3].type, "chrome-window")
        XCTAssertEqual(decoded.resources.last?.type, "application")
    }

    func testUnsupportedResourceRoundTripsWithoutDataLoss() throws {
        let projectID = UUID()
        let resourceID = UUID()
        let json = """
        {
          "schemaVersion": 1,
          "id": "\(projectID.uuidString)",
          "name": "Future Project",
          "resources": [{
            "id": "\(resourceID.uuidString)",
            "type": "future-resource",
            "name": "Future",
            "enabled": true,
            "count": 9007199254740993,
            "nested": {"values": [1, null, "three"]}
          }]
        }
        """
        let original = Data(json.utf8)
        let project = try decoder.decode(Project.self, from: original)

        guard case .unsupported = project.resources[0].payload else {
            return XCTFail("Expected an unsupported Resource.")
        }

        let reencoded = try encoder.encode(project)
        guard case var .object(originalJSON) = try decoder.decode(JSONValue.self, from: original) else {
            return XCTFail("Expected a Project JSON object.")
        }
        originalJSON["schemaVersion"] = .number(2)
        let reencodedJSON = try decoder.decode(JSONValue.self, from: reencoded)
        XCTAssertEqual(reencodedJSON, .object(originalJSON))
    }

    func testNewerSchemaVersionIsRejected() throws {
        let json = """
        {"schemaVersion": 3, "id": "\(UUID())", "name": "New", "resources": []}
        """

        XCTAssertThrowsError(try decoder.decode(Project.self, from: Data(json.utf8)))
    }

    func testVersionOneLoadsWithoutDestinationAndEncodesAsVersionTwo() throws {
        let json = """
        {"schemaVersion": 1, "id": "\(UUID())", "name": "Legacy", "resources": []}
        """

        let project = try decoder.decode(Project.self, from: Data(json.utf8))
        let encoded = try encoder.encode(project)
        let object = try XCTUnwrap(decoder.decode(JSONValue.self, from: encoded).objectValue)

        XCTAssertEqual(project.schemaVersion, 2)
        XCTAssertNil(project.launchDestination)
        XCTAssertEqual(object["schemaVersion"], .number(2))
        XCTAssertNil(object["launchDestination"])
    }

    func testAeroSpaceDestinationRoundTrips() throws {
        let project = Project(
            name: "Placed",
            resources: [],
            launchDestination: .aeroSpaceWorkspace("2")
        )

        let decoded = try decoder.decode(Project.self, from: encoder.encode(project))

        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.launchDestination, .aeroSpaceWorkspace("2"))
    }

    func testUnsupportedDestinationRoundTripsWithoutDataLoss() throws {
        let json = """
        {
          "schemaVersion": 2,
          "id": "\(UUID())",
          "name": "Future Placement",
          "launchDestination": {
            "type": "future-placement",
            "enabled": true,
            "nested": {"value": 9007199254740993}
          },
          "resources": []
        }
        """
        let original = Data(json.utf8)
        let project = try decoder.decode(Project.self, from: original)

        guard case .unsupported = project.launchDestination else {
            return XCTFail("Expected an unsupported launch destination.")
        }

        XCTAssertEqual(
            try decoder.decode(JSONValue.self, from: encoder.encode(project)),
            try decoder.decode(JSONValue.self, from: original)
        )
    }

    func testStableFilenameUsesProjectIdentifier() {
        let id = ProjectID(UUID(uuidString: "3B06EC67-9A7C-4D66-ACF4-3F869F195C1F")!)
        var project = Project(id: id, name: "Original", resources: [])
        let originalFilename = project.filename

        project.name = "Renamed"

        XCTAssertEqual(project.filename, originalFilename)
        XCTAssertEqual(project.filename, "3b06ec67-9a7c-4d66-acf4-3f869f195c1f.json")
    }

    func testPathAcceptsAbsoluteAndHomeRelativeValues() throws {
        let home = URL(filePath: "/Users/example", directoryHint: .isDirectory)

        XCTAssertEqual(try ProjectPath("/tmp/project").resolved(homeDirectory: home).path, "/tmp/project")
        XCTAssertEqual(try ProjectPath("~/").resolved(homeDirectory: home), home)
        XCTAssertEqual(
            try ProjectPath("~/Projects/App").resolved(homeDirectory: home).path,
            "/Users/example/Projects/App"
        )
    }

    func testDefaultHomeExpansionUsesLoginAccountHome() throws {
        let passwordEntry = try XCTUnwrap(getpwuid(getuid()))
        let expected = URL(
            filePath: String(cString: passwordEntry.pointee.pw_dir),
            directoryHint: .isDirectory
        )

        XCTAssertEqual(try ProjectPath("~/").resolved(), expected)
        XCTAssertFalse(try ProjectPath("~/").resolved().path.contains("/Library/Containers/"))
    }

    func testPathRejectsOtherRelativeValues() {
        XCTAssertThrowsError(try ProjectPath("Projects/App"))
        XCTAssertThrowsError(try ProjectPath("~someone/Projects"))
    }

    func testValidationFindsDuplicateNamesAndIdentifiers() {
        let projectID = ProjectID()
        let resourceID = ResourceID()
        let first = Project(
            id: projectID,
            name: " Example ",
            resources: [Resource(id: resourceID, name: "One", payload: .finderWindow(.init(folder: "~/")))]
        )
        let second = Project(
            id: projectID,
            name: "example",
            resources: [
                Resource(id: resourceID, name: "Two", payload: .finderWindow(.init(folder: "~/"))),
                Resource(id: resourceID, name: "Three", payload: .finderWindow(.init(folder: "relative")))
            ]
        )

        let issues = ProjectValidator.validateCollection([first, second])

        XCTAssertTrue(issues.contains { $0.field == "projects.name" })
        XCTAssertTrue(issues.contains { $0.field == "projects.id" })
        XCTAssertTrue(issues.contains { $0.field == "resources.id" })
        XCTAssertTrue(issues.contains { $0.field == "resources[1].folder" })
    }

    func testValidationReportsRequiredFieldsURLsAndPaths() {
        let project = Project(
            name: "  ",
            resources: [
                Resource(
                    name: " ",
                    payload: .browserWindow(BrowserWindow(tabs: []))
                ),
                Resource(
                    name: "Web",
                    payload: .browserWindow(BrowserWindow(tabs: ["not a URL"]))
                ),
                Resource(
                    name: "Chrome",
                    payload: .chromeWindow(BrowserWindow(tabs: []))
                ),
                Resource(
                    name: "Chrome Web",
                    payload: .chromeWindow(BrowserWindow(tabs: ["not a URL"]))
                ),
                Resource(
                    name: "Terminal",
                    payload: .terminalSession(TerminalSession(workingDirectory: "relative"))
                ),
                Resource(
                    name: "Invalid Application",
                    payload: .application(
                        ApplicationResource(bundleIdentifier: " ", lastKnownPath: "Applications/App")
                    )
                )
            ],
            launchDestination: .aeroSpaceWorkspace(" \n")
        )

        let issues = ProjectValidator.validate(project)

        XCTAssertTrue(issues.contains { $0.field == "name" })
        XCTAssertTrue(issues.contains { $0.field == "launchDestination.workspace" })
        XCTAssertTrue(issues.contains { $0.field == "resources[0].name" })
        XCTAssertTrue(issues.contains { $0.field == "resources[0].tabs" })
        XCTAssertTrue(issues.contains { $0.field == "resources[1].tabs[0]" })
        XCTAssertTrue(issues.contains {
            $0.field == "resources[2].tabs" && $0.message == "At least one Chrome tab is required."
        })
        XCTAssertTrue(issues.contains {
            $0.field == "resources[3].tabs[0]" && $0.message == "Enter a URL Chrome can open."
        })
        XCTAssertTrue(issues.contains { $0.field == "resources[4].workingDirectory" })
        XCTAssertTrue(issues.contains { $0.field == "resources[5].bundleIdentifier" })
        XCTAssertTrue(issues.contains { $0.field == "resources[5].lastKnownPath" })
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }
}
