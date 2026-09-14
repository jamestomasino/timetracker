import Foundation

/// User preferences for the app, persisted across launches.
///
/// Defaults are chosen so a first launch behaves exactly like the app did
/// before settings existed: toasts are on (they were always on), and the
/// hourly break reminder is off (it is a new, opt-in feature).
///
/// Decoding is lenient: any missing key falls back to the default, so a
/// settings file written by an older version (or with a key removed) still
/// loads without throwing.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Whether transient in-app toasts (delete/export confirmations) are shown.
    public var toastEnabled: Bool
    /// While a task is running, post a notification at the top of each hour.
    public var hourlyReminderEnabled: Bool
    /// The day a week begins, used by the "tasks by week" export.
    public var weekStart: WeekStart

    public init(
        toastEnabled: Bool = true,
        hourlyReminderEnabled: Bool = false,
        weekStart: WeekStart = .monday
    ) {
        self.toastEnabled = toastEnabled
        self.hourlyReminderEnabled = hourlyReminderEnabled
        self.weekStart = weekStart
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.toastEnabled = try c.decodeIfPresent(Bool.self, forKey: .toastEnabled) ?? true
        self.hourlyReminderEnabled =
            try c.decodeIfPresent(Bool.self, forKey: .hourlyReminderEnabled) ?? false
        self.weekStart =
            try c.decodeIfPresent(WeekStart.self, forKey: .weekStart) ?? .monday
    }
}
