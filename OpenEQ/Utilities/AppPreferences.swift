import Foundation

enum AppPreferences {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let hasCompletedSystemEQOnboarding = "openeq.hasCompletedSystemEQOnboarding"
        static let preferSystemEQOnLaunch = "openeq.preferSystemEQOnLaunch"
        static let autoApplyDeviceProfiles = "openeq.autoApplyDeviceProfiles"
        static let feedbackProtectionEnabled = "openeq.feedbackProtectionEnabled"
    }

    static var hasCompletedSystemEQOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedSystemEQOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedSystemEQOnboarding) }
    }

    static var preferSystemEQOnLaunch: Bool {
        get { defaults.bool(forKey: Key.preferSystemEQOnLaunch) }
        set { defaults.set(newValue, forKey: Key.preferSystemEQOnLaunch) }
    }

    static var autoApplyDeviceProfiles: Bool {
        get {
            if defaults.object(forKey: Key.autoApplyDeviceProfiles) == nil {
                return true
            }
            return defaults.bool(forKey: Key.autoApplyDeviceProfiles)
        }
        set { defaults.set(newValue, forKey: Key.autoApplyDeviceProfiles) }
    }

    static var feedbackProtectionEnabled: Bool {
        get {
            if defaults.object(forKey: Key.feedbackProtectionEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Key.feedbackProtectionEnabled)
        }
        set { defaults.set(newValue, forKey: Key.feedbackProtectionEnabled) }
    }
}
