import Foundation

/// A single tracked task.
///
/// A task accumulates completed time in `accumulated`. When it is running,
/// `runningSince` records the start of the current interval; the live elapsed
/// time is `accumulated + (now - runningSince)`.
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

    public init(
        id: UUID = UUID(),
        title: String,
        accumulated: TimeInterval = 0,
        runningSince: Date? = nil,
        createdAt: Date = Date(),
        lastActivityAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.accumulated = accumulated
        self.runningSince = runningSince
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
    }
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

/// A clock pinned to a fixed instant, for tests.
public struct FixedClock: Clock {
    public var instant: Date
    public init(instant: Date) { self.instant = instant }
    public func now() -> Date { instant }
}
