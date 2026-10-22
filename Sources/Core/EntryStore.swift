import Foundation
import os

/// Persists the engine's snapshot to a JSON file in Application Support.
///
/// The engine owns state; this layer only serializes/deserializes it and keeps
/// a debounced save so we don't hammer disk while a timer ticks.
///
/// Durability: the tracked time is the whole point of the app, so we never let
/// a save destroy the last known-good file. `saveNow()` refuses to write if
/// encoding fails, and it keeps the previous file as a `.bak` backup before
/// overwriting. `load()` falls back to that backup if the primary is missing or
/// unparseable, so a corrupt write can't silently wipe the user's history.
public final class EntryStore {
    private let engine: TimeTrackerEngine
    private let fileURL: URL
    private let backupURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var saveTask: Task<Void, Never>?

    public init(engine: TimeTrackerEngine, fileURL: URL = EntryStore.defaultFileURL()) {
        self.engine = engine
        self.fileURL = fileURL
        self.backupURL = fileURL.appendingPathExtension("bak")
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
    ///
    /// Prefers the primary file; if it is missing or unparseable, falls back to
    /// the last-known-good backup so a corrupt primary never wipes history.
    public func load() {
        if let snap = decode(at: fileURL) {
            engine.restore(snap)
        } else if let snap = decode(at: backupURL) {
            engine.restore(snap)
        }
        // Otherwise nothing readable: keep the engine as-is (empty on first run).
    }

    private func decode(at url: URL) -> TimeTrackerEngine.Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(TimeTrackerEngine.Snapshot.self, from: data)
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

    /// Save synchronously. Never writes an empty/invalid file over existing data.
    public func saveNow() {
        // If encoding fails, leave whatever is on disk untouched rather than
        // clobbering the last good file with an empty write.
        guard let data = try? encoder.encode(engine.snapshot()) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            // Rotate the current primary into a backup before overwriting it,
            // so the previous state is always recoverable.
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            }
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // On any failure the existing file is left intact (atomic write +
            // backup rotation means there is nothing to roll back). But a failed
            // save of tracked time is exactly the kind of thing that should not
            // be silent — log it so a disk-full or permission problem is visible
            // in Console.
            os_log(.error, "TimeTracker: failed to save entries: %{public}@",
                   error.localizedDescription)
        }
    }
}
