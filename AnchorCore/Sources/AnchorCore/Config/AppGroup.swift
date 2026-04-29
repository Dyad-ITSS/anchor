import Foundation

/// App Group constants shared between the main app and the helper.
public enum AppGroup {
    public static let id = "group.com.zieseniss.anchor"

    /// URL of the App Group container directory.
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// URL of the JSON config file within the App Group container.
    public static var configFileURL: URL? {
        containerURL?.appendingPathComponent("config.json")
    }
}
