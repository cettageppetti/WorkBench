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

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "WorkBenchTests.AeroSpaceSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}
