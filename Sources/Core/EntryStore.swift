import Foundation

/// Persists the engine's snapshot to a JSON file in Application Support.
///
/// The engine owns state; this layer only serializes/deserializes it and keeps
/// a debounced save so we don't hammer disk while a timer ticks.
public final class EntryStore {
    private let engine: TimeTrackerEngine
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var saveTask: Task<Void, Never>?

    public init(engine: TimeTrackerEngine, fileURL: URL = EntryStore.defaultFileURL()) {
        self.engine = engine
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    /// ~/Library/Application Support/TimeTracker/entries.json
    public static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.homeDirectoryForCurrentUser
        let dir = base.appendingPathComponent("TimeTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("entries.json")
    }

    /// Load a saved snapshot into the engine. Safe to call when no file exists.
    public func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snap = try? decoder.decode(TimeTrackerEngine.Snapshot.self, from: data)
        else { return }
        engine.restore(snap)
    }

    /// Schedule a debounced save of the current snapshot.
    public func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Save synchronously.
    public func saveNow() {
        let data = (try? encoder.encode(engine.snapshot())) ?? Data()
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
