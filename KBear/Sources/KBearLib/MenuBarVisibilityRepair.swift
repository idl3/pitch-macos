import Foundation

enum MenuBarVisibilityRepair {
    private static let controlCenterSuite = "com.apple.controlcenter"
    private static let systemUIServerSuite = "com.apple.systemuiserver"
    private static let visiblePrefix = "NSStatusItem Visible "
    private static let visibleCCPrefix = "NSStatusItem VisibleCC "

    static func repairHiddenVisibilityDefaults(for autosaveName: String) {
        setVisible(true, for: autosaveName)
    }

    static func clearVisibilityDefault(for autosaveName: String) {
        setVisible(true, for: autosaveName)
    }

    private static func setVisible(_ visible: Bool, for autosaveName: String) {
        let domains = [controlCenterSuite, systemUIServerSuite]
        let keys = [visiblePrefix + autosaveName, visibleCCPrefix + autosaveName]
        let value = visible ? "YES" : "NO"
        for domain in domains {
            for key in keys {
                let task = Process()
                task.launchPath = "/usr/bin/defaults"
                task.arguments = ["write", domain, key, "-bool", value]
                task.standardOutput = FileHandle.nullDevice
                task.standardError = FileHandle.nullDevice
                try? task.run()
                task.waitUntilExit()
            }
        }
    }
}
