import Foundation

/// The day on which a week begins. Drives the "tasks by week" export.
///
/// Weeks are always seven consecutive days; this just chooses the anchor day.
/// The default is Monday (see `AppSettings.weekStart`).
public enum WeekStart: String, Codable, CaseIterable, Sendable {
    case monday
    case sunday
    case saturday

    /// The `Calendar` weekday number (1 = Sunday … 7 = Saturday) that anchors
    /// the week.
    var anchorWeekday: Int {
        switch self {
        case .monday: return 2
        case .sunday: return 1
        case .saturday: return 7
        }
    }

    public var label: String {
        switch self {
        case .monday: return "Monday"
        case .sunday: return "Sunday"
        case .saturday: return "Saturday"
        }
    }
}

/// A selectable span of time for exports, so the user need not dump all of
/// history.
public enum DateRange: String, Codable, CaseIterable, Sendable {
    case all
    case thisWeek
    case thisMonth
    case last30Days

    public var label: String {
        switch self {
        case .all: return "All"
        case .thisWeek: return "This week"
        case .thisMonth: return "This month"
        case .last30Days: return "Last 30 days"
        }
    }
}

/// Which shape an export takes.
public enum ExportMode: String, CaseIterable, Sendable {
    /// One row per task, total time.
    case totals
    /// One row per (task, day).
    case byDay
    /// One row per (task, week).
    case byWeek

    public var label: String {
        switch self {
        case .totals: return "task totals"
        case .byDay: return "tasks by day"
        case .byWeek: return "tasks by week"
        }
    }
}

/// A half-open span of days `[from, to)`, both at local midnight.
public struct TimeWindow: Equatable, Sendable {
    public let from: Date
    public let to: Date

    public init(from: Date, to: Date) {
        self.from = from
        self.to = to
    }

    /// True when the (midnight) day `d` falls inside the window.
    public func contains(_ d: Date) -> Bool { d >= from && d < to }
}

/// Pure, calendar-injected helpers for bucketing tracked time into days and
/// weeks.
///
/// Kept free of any UI or persistence so the math is fully deterministic under
/// test. A day is identified by its local `yyyy-MM-dd` key; a week by the
/// `yyyy-MM-dd` of its first day.
public enum TimeBuckets {

    // MARK: - Day keys

    /// Local `yyyy-MM-dd` key for the day containing `date`.
    public static func dayKey(for date: Date, calendar: Calendar = Calendar.current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Inverse of `dayKey`: parse a `yyyy-MM-dd` key back to local midnight.
    public static func dateFromDayKey(_ key: String, calendar: Calendar = Calendar.current) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    // MARK: - Week boundaries

    /// Start of the week (local midnight) containing `date`, for the given
    /// week-start day.
    public static func weekStart(
        for date: Date,
        calendar: Calendar = Calendar.current,
        weekStart: WeekStart = .monday
    ) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let offset = (weekday - weekStart.anchorWeekday + 7) % 7
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -offset, to: dayStart) ?? dayStart
    }

    /// The `yyyy-MM-dd` key of the first day of the week containing `date`.
    /// Convenience wrapper over `weekStart` for callers that want a stable
    /// string key rather than a `Date`.
    public static func weekKey(
        for date: Date,
        calendar: Calendar = Calendar.current,
        weekStart: WeekStart = .monday
    ) -> String {
        dayKey(for: Self.weekStart(for: date, calendar: calendar, weekStart: weekStart), calendar: calendar)
    }

    // MARK: - Splitting & grouping

    /// Split a `[start, end]` interval into per-day seconds, keyed by
    /// `yyyy-MM-dd`. Correctly handles intervals that span multiple days (e.g.
    /// a task left running across midnight).
    public static func splitByDay(
        start: Date,
        end: Date,
        calendar: Calendar = Calendar.current
    ) -> [String: TimeInterval] {
        guard end > start else { return [:] }
        var result: [String: TimeInterval] = [:]
        var dayStart = calendar.startOfDay(for: start)
        while dayStart < end {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)
                ?? dayStart.addingTimeInterval(86_400)
            let sliceStart = max(start, dayStart)
            let sliceEnd = min(end, nextDay)
            if sliceEnd > sliceStart {
                let key = dayKey(for: dayStart, calendar: calendar)
                result[key, default: 0] += sliceEnd.timeIntervalSince(sliceStart)
            }
            dayStart = nextDay
        }
        return result
    }

    /// Group a day -> seconds map into week -> seconds, keyed by the week's
    /// first day (`yyyy-MM-dd`).
    public static func groupWeeks(
        days: [String: TimeInterval],
        calendar: Calendar = Calendar.current,
        weekStart: WeekStart = .monday
    ) -> [String: TimeInterval] {
        var result: [String: TimeInterval] = [:]
        for (key, secs) in days {
            guard let d = dateFromDayKey(key, calendar: calendar) else { continue }
            let ws = TimeBuckets.weekStart(for: d, calendar: calendar, weekStart: weekStart)
            let wk = dayKey(for: ws, calendar: calendar)
            result[wk, default: 0] += secs
        }
        return result
    }

    /// True when the day key falls inside the window.
    public static func dayInWindow(
        _ key: String,
        _ window: TimeWindow,
        calendar: Calendar = Calendar.current
    ) -> Bool {
        guard let d = dateFromDayKey(key, calendar: calendar) else { return false }
        return window.contains(d)
    }

    // MARK: - Date ranges

    /// Resolve a `DateRange` to a day window (or `nil` for "all"), relative to
    /// `now`.
    public static func window(
        for range: DateRange,
        now: Date,
        calendar: Calendar = Calendar.current,
        weekStart: WeekStart = .monday
    ) -> TimeWindow? {
        switch range {
        case .all:
            return nil
        case .thisWeek:
            let ws = TimeBuckets.weekStart(for: now, calendar: calendar, weekStart: weekStart)
            let to = calendar.date(byAdding: .day, value: 7, to: ws) ?? ws
            return TimeWindow(from: ws, to: to)
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: now)
            guard let from = calendar.date(from: comps) else { return nil }
            let to = calendar.date(byAdding: .month, value: 1, to: from) ?? from
            return TimeWindow(from: from, to: to)
        case .last30Days:
            let today = calendar.startOfDay(for: now)
            let from = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            let to = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            return TimeWindow(from: from, to: to)
        }
    }
}
