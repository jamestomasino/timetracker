import Foundation

/// A single tracked task.
///
/// A task accumulates completed time in `accumulated`. When it is running,
/// `runningSince` records the start of the current interval; the live elapsed
/// time is `accumulated + (now - runningSince)`.
///
/// `notes` and `tags` are optional metadata: free-text notes and a small set of
/// normalized tags. Both are decoded leniently so files written by older
/// versions of the app (which lack the keys) still load.
public struct TimeEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    /// Completed (stopped) time in seconds, accumulated across runs.
    public var accumulated: TimeInterval
    /// Start of the current running interval, or `nil` when stopped.
    public var runningSince: Date?
    /// When the task was first created.
    public var createdAt: Date
    /// When the task was last started/stopped, used for "recent" ordering.
    public var lastActivityAt: Date
    /// Free-text notes attached to the task (may be empty).
    public var notes: String
    /// Normalized tags (trimmed, lowercased, de-duplicated, in first-seen order).
    public var tags: [String]

    public init(
        id: UUID = UUID(),
        title: String,
        accumulated: TimeInterval = 0,
        runningSince: Date? = nil,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date(),
        notes: String = "",
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.accumulated = accumulated
        self.runningSince = runningSince
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.notes = notes
        self.tags = tags
    }

    /// Lenient decode: `notes` and `tags` default to empty when absent, so a
    /// snapshot saved before those fields existed still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.accumulated = try c.decode(TimeInterval.self, forKey: .accumulated)
        self.runningSince = try c.decodeIfPresent(Date.self, forKey: .runningSince)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.lastActivityAt = try c.decode(Date.self, forKey: .lastActivityAt)
        self.notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        self.tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    /// Total tracked seconds for this entry at `now`: completed time plus the
    /// live running interval (if any), clamped at zero. Single source of truth
    /// for "how long has this task been tracked," shared by the engine's
    /// live-elapsed reporting and the CSV export.
    public func duration(at now: Date) -> TimeInterval {
        let running = runningSince.map { now.timeIntervalSince($0) } ?? 0
        return max(0, accumulated + running)
    }
}

/// Parse a raw tag string into normalized tags.
///
/// Splits on commas (and semicolons), trims surrounding whitespace, drops
/// empties, lowercases for de-dup, and removes duplicates while preserving
/// first-seen order. So `"Work, design , design, urgent"` ->
/// `["work", "design", "urgent"]`.
public func parseTags(_ raw: String) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for piece in raw.components(separatedBy: CharacterSet(charactersIn: ",;")) {
        let t = piece.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty, !seen.contains(t) else { continue }
        seen.insert(t)
        out.append(t)
    }
    return out
}

/// Abstract clock so the core engine is deterministic under test.
public protocol Clock: Sendable {
    func now() -> Date
}

/// Wall-clock default.
public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}
