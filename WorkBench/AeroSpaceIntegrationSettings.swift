import Foundation

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
