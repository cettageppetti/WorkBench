import Foundation
import XCTest
@testable import WorkBench

@MainActor
final class AeroSpaceIntegrationSettingsTests: XCTestCase {
    func testIntegrationDefaultsToDisabled() throws {
        let defaults = try makeDefaults()
        let store = UserDefaultsAeroSpaceIntegrationSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), AeroSpaceIntegrationSettings(isEnabled: false))
    }

    func testIntegrationEnablementPersists() throws {
        let defaults = try makeDefaults()
        let store = UserDefaultsAeroSpaceIntegrationSettingsStore(defaults: defaults)

        store.save(AeroSpaceIntegrationSettings(isEnabled: true))

        XCTAssertEqual(store.load(), AeroSpaceIntegrationSettings(isEnabled: true))
    }

    func testSettingsModelPersistsToggleAndDiscoversWorkspaces() async {
        let store = SettingsStoreSpy(settings: AeroSpaceIntegrationSettings())
        let controller = SettingsAeroSpaceController(result: .success(["1", "work"]))
        let model = AeroSpaceSettingsModel(store: store, controller: controller)

        model.setEnabled(true)
        await model.discoverWorkspaces()

        XCTAssertEqual(store.savedSettings, [AeroSpaceIntegrationSettings(isEnabled: true)])
        XCTAssertEqual(model.workspaces, ["1", "work"])
        XCTAssertNil(model.discoveryError)

        model.setEnabled(false)
        XCTAssertTrue(model.workspaces.isEmpty)
        XCTAssertEqual(store.savedSettings.last, AeroSpaceIntegrationSettings(isEnabled: false))
    }

    func testSettingsModelPresentsDiscoveryFailure() async {
        let model = AeroSpaceSettingsModel(
            store: SettingsStoreSpy(settings: AeroSpaceIntegrationSettings(isEnabled: true)),
            controller: SettingsAeroSpaceController(result: .failure(.timedOut))
        )

        await model.discoverWorkspaces()

        XCTAssertTrue(model.workspaces.isEmpty)
        XCTAssertEqual(
            model.discoveryError,
            "AeroSpace did not respond before the operation timed out."
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "WorkBenchTests.AeroSpaceSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}

@MainActor
private final class SettingsStoreSpy: AeroSpaceIntegrationSettingsStoring {
    private let settings: AeroSpaceIntegrationSettings
    private(set) var savedSettings: [AeroSpaceIntegrationSettings] = []

    init(settings: AeroSpaceIntegrationSettings) {
        self.settings = settings
    }

    func load() -> AeroSpaceIntegrationSettings { settings }
    func save(_ settings: AeroSpaceIntegrationSettings) { savedSettings.append(settings) }
}

@MainActor
private struct SettingsAeroSpaceController: AeroSpaceControlling {
    let result: Result<[String], AeroSpaceClientError>

    func listWorkspaces() async -> Result<[String], AeroSpaceClientError> { result }
    func activateWorkspace(named workspace: String) async -> Result<Void, AeroSpaceClientError> {
        .success(())
    }
}
