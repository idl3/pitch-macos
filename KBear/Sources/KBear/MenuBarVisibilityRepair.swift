import Foundation

enum MenuBarVisibilityRepair {
    private static let suiteName = "com.apple.controlcenter"
    private static let visiblePrefix = "NSStatusItem Visible "
    private static let visibleCCPrefix = "NSStatusItem VisibleCC "
    private static let didRepairKey = "codes.ernest.tonos.hasRepairedMenuBarVisibility"

    static func repairHiddenVisibilityDefaults() {
        guard let defaults = UserDefaults(suiteName: suiteName),
              !defaults.bool(forKey: didRepairKey) else { return }

        let keysToRemove = defaults.dictionaryRepresentation().keys
            .filter { key in
                guard key.hasPrefix(visiblePrefix) || key.hasPrefix(visibleCCPrefix) else { return false }
                let value = defaults.object(forKey: key)
                return isHiddenValue(value)
            }

        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: didRepairKey)
        defaults.synchronize()
    }

    static func clearVisibilityDefault(for autosaveName: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let visibleKey = visiblePrefix + autosaveName
        let visibleCCKey = visibleCCPrefix + autosaveName
        if defaults.object(forKey: visibleKey) == nil || isHiddenValue(defaults.object(forKey: visibleKey)) {
            defaults.set(true, forKey: visibleKey)
        }
        if defaults.object(forKey: visibleCCKey) == nil || isHiddenValue(defaults.object(forKey: visibleCCKey)) {
            defaults.set(true, forKey: visibleCCKey)
        }
        defaults.synchronize()
    }

    private static func isHiddenValue(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber:
            return !number.boolValue
        case let bool as Bool:
            return !bool
        default:
            return false
        }
    }
}
