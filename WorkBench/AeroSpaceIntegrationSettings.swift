import Foundation
import Observation

struct AeroSpaceIntegrationSettings: Equatable {
    var isEnabled: Bool = false
}

protocol AeroSpaceIntegrationSettingsStoring {
    func load() -> AeroSpaceIntegrationSettings
    func save(_ settings: AeroSpaceIntegrationSettings)
}

struct UserDefaultsAeroSpaceIntegrationSettingsStore: AeroSpaceIntegrationSettingsStoring {
    private let defaults: UserDefaults
    private let enabledKey: String

    init(
        defaults: UserDefaults = .standard,
        enabledKey: String = "aeroSpaceIntegrationEnabled"
    ) {
        self.defaults = defaults
        self.enabledKey = enabledKey
    }

    func load() -> AeroSpaceIntegrationSettings {
        AeroSpaceIntegrationSettings(isEnabled: defaults.bool(forKey: enabledKey))
    }

    func save(_ settings: AeroSpaceIntegrationSettings) {
        defaults.set(settings.isEnabled, forKey: enabledKey)
    }
}

@MainActor
@Observable
final class AeroSpaceSettingsModel {
    private(set) var settings: AeroSpaceIntegrationSettings
    private(set) var workspaces: [String] = []
    private(set) var discoveryError: String?
    private(set) var isDiscovering = false

    @ObservationIgnored private let store: any AeroSpaceIntegrationSettingsStoring
    @ObservationIgnored private let controller: any AeroSpaceControlling

    init(
        store: any AeroSpaceIntegrationSettingsStoring =
            UserDefaultsAeroSpaceIntegrationSettingsStore(),
        controller: any AeroSpaceControlling = AeroSpaceClient()
    ) {
        self.store = store
        self.controller = controller
        settings = store.load()
    }

    func setEnabled(_ isEnabled: Bool) {
        settings.isEnabled = isEnabled
        store.save(settings)
        if !isEnabled {
            workspaces = []
            discoveryError = nil
        }
    }

    func discoverWorkspaces() async {
        guard settings.isEnabled, !isDiscovering else { return }
        isDiscovering = true
        defer { isDiscovering = false }
        switch await controller.listWorkspaces() {
        case let .success(workspaces):
            self.workspaces = workspaces
            discoveryError = nil
        case let .failure(error):
            workspaces = []
            discoveryError = error.recoveryMessage
        }
    }
}
