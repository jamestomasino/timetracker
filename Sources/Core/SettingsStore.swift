import Foundation

/// Persists `AppSettings` to a JSON file in Application Support.
///
/// Mirrors `EntryStore`'s approach: a small, swappable persistence layer so
/// the view model never touches the file system directly. Unlike `EntryStore`,
/// settings are low-stakes (toggles), so there is no backup rotation — a failed
/// write simply leaves the previous file intact (atomic write), and a missing
/// or corrupt file falls back to the defaults.
///
/// An in-memory mode is provided for tests so the suite never reads or writes
/// the user's real preferences.
public final class SettingsStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var memoryOnly = false
    private var memoryValue: AppSettings?

    public init(fileURL: URL = SettingsStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    /// A store that keeps its value in memory and never touches disk.
    public static func inMemory(_ initial: AppSettings = AppSettings()) -> SettingsStore {
        let store = SettingsStore(fileURL: URL(fileURLWithPath: "/dev/null/settings.json"))
        store.memoryOnly = true
        store.memoryValue = initial
        return store
    }

    /// ~/Library/Application Support/TimeTracker/settings.json
    public static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("TimeTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    /// Load the saved settings, or the defaults when nothing is readable.
    public func load() -> AppSettings {
        if memoryOnly { return memoryValue ?? AppSettings() }
        if let data = try? Data(contentsOf: fileURL),
           let settings = try? decoder.decode(AppSettings.self, from: data) {
            return settings
        }
        return AppSettings()
    }

    /// Persist the settings atomically. A failed encode/write leaves the
    /// existing file untouched.
    public func save(_ settings: AppSettings) {
        if memoryOnly {
            memoryValue = settings
            return
        }
        guard let data = try? encoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
