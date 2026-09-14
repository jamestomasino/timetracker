import Foundation

/// The pure state machine for the tracker.
///
/// Responsibilities:
/// - Add a task (optionally start it immediately).
/// - Start a task, which *stops whichever task is currently running* (only one
///   task can run at a time).
/// - Stop a task, folding its running interval into `accumulated`.
/// - Report the currently running task and live elapsed times.
/// - Provide ordering ("recent") and search.
///
/// The engine is clock-injected so it is fully deterministic under test. It has
/// no dependency on SwiftUI, AppKit, or the file system — persistence is a
/// separate concern (see `EntryStore`).
public final class TimeTrackerEngine {
    public private(set) var entries: [TimeEntry] = []
    private let clock: Clock
    /// The calendar used to attribute completed intervals to days. Defaults to
    /// the user's current calendar (so production behavior is unchanged); tests
    /// inject a fixed one so the stop path is timezone-deterministic.
    private let calendar: Calendar

    public init(clock: Clock = SystemClock(), calendar: Calendar = Calendar.current) {
        self.clock = clock
        self.calendar = calendar
    }

    // MARK: - Identity / lookups

    public func entry(id: UUID) -> TimeEntry? {
        entries.first { $0.id == id }
    }

    /// The task currently running, if any.
    public var runningEntry: TimeEntry? {
        entries.first { $0.runningSince != nil }
    }

    public var runningID: UUID? {
        runningEntry?.id
    }

    // MARK: - Elapsed time

    /// Live elapsed seconds for a task, given an instant.
    public func elapsed(for entry: TimeEntry, at now: Date) -> TimeInterval {
        entry.duration(at: now)
    }

    // MARK: - Mutations

    /// Add a new task. If `start` is true, it begins running immediately.
    @discardableResult
    public func add(title: String, start: Bool = false, now: Date? = nil) -> TimeEntry {
        let now = now ?? clock.now()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = TimeEntry(
            title: trimmed,
            accumulated: 0,
            runningSince: start ? now : nil,
            createdAt: now,
            lastActivityAt: now
        )
        // Starting a brand-new task must stop whatever was running.
        if start { stopRunning(now: now) }
        entries.append(entry)
        return entry
    }

    /// Start a task. Any other running task is stopped first (auto-stop).
    public func start(id: UUID, now: Date? = nil) {
        let now = now ?? clock.now()
        guard let idx = index(of: id) else { return }
        if entries[idx].runningSince != nil { return } // already running
        stopRunning(now: now)
        entries[idx].runningSince = now
        entries[idx].lastActivityAt = now
    }

    /// Stop the task with the given id (no-op if it isn't running).
    public func stop(id: UUID, now: Date? = nil) {
        let now = now ?? clock.now()
        guard let idx = index(of: id), entries[idx].runningSince != nil else { return }
        foldRunning(at: now, idx: idx)
    }

    /// Stop whichever task is currently running.
    public func stopRunning(now: Date? = nil) {
        let now = now ?? clock.now()
        guard let idx = entries.firstIndex(where: { $0.runningSince != nil }) else { return }
        foldRunning(at: now, idx: idx)
    }

    /// Toggle a task: start if stopped, stop if running.
    public func toggle(id: UUID, now: Date? = nil) {
        let now = now ?? clock.now()
        if let idx = index(of: id), entries[idx].runningSince != nil {
            foldRunning(at: now, idx: idx)
        } else {
            start(id: id, now: now)
        }
    }

    /// Delete a task (stops it first if it was running).
    public func delete(id: UUID, now: Date? = nil) {
        let now = now ?? clock.now()
        guard let idx = index(of: id) else { return }
        if entries[idx].runningSince != nil { foldRunning(at: now, idx: idx) }
        entries.remove(at: idx)
    }

    /// Update a task's notes and/or tags (no time mutation).
    public func update(id: UUID, notes: String? = nil, tags: [String]? = nil, now: Date? = nil) {
        guard let idx = index(of: id) else { return }
        if let notes { entries[idx].notes = notes }
        if let tags { entries[idx].tags = tags }
        entries[idx].lastActivityAt = now ?? clock.now()
    }

    // MARK: - Ordering & search

    /// Entries ordered most-recently-active first (running task pinned to top).
    public var recent: [TimeEntry] {
        entries.sorted { a, b in
            let aRunning = a.runningSince != nil
            let bRunning = b.runningSince != nil
            if aRunning != bRunning { return aRunning } // running first
            if a.lastActivityAt != b.lastActivityAt { return a.lastActivityAt > b.lastActivityAt }
            return a.id.uuidString > b.id.uuidString // stable tiebreak
        }
    }

    /// Case-insensitive substring search over titles, notes, and tags.
    public func search(_ query: String, now: Date? = nil) -> [TimeEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return recent }
        let lowered = q.lowercased()
        return recent.filter { entry in
            entry.title.lowercased().contains(lowered)
                || entry.notes.lowercased().contains(lowered)
                || entry.tags.contains { $0.contains(lowered) }
        }
    }

    // MARK: - Persistence snapshot

    /// A snapshot of the model that can be encoded to disk.
    public struct Snapshot: Codable {
        public var entries: [TimeEntry]
    }

    public func snapshot() -> Snapshot { Snapshot(entries: entries) }

    public func restore(_ snap: Snapshot) {
        self.entries = snap.entries
    }

    // MARK: - Private

    private func index(of id: UUID) -> Int? {
        entries.firstIndex { $0.id == id }
    }

    /// Fold a running interval into `accumulated`, attribute it to the day(s)
    /// it spanned, and mark it stopped.
    private func foldRunning(at now: Date, idx: Int) {
        guard let since = entries[idx].runningSince else { return }
        let delta = max(0, now.timeIntervalSince(since))
        entries[idx].accumulated += delta
        // Attribute the completed interval to the day(s) it covered so the
        // by-day and by-week exports are correct.
        let perDay = TimeBuckets.splitByDay(start: since, end: now, calendar: self.calendar)
        for (key, secs) in perDay {
            entries[idx].dayTotals[key, default: 0] += secs
        }
        entries[idx].runningSince = nil
        entries[idx].lastActivityAt = now
    }
}
