import Foundation

/// Pure, AppKit-free CSV serialization of tracked entries.
///
/// Kept in Core so it is unit-testable without a UI. `now` is injected so the
/// duration of a running entry is deterministic under test.
///
/// Three shapes are offered (see `ExportMode`):
/// - **totals**: one row per task, total time.
/// - **byDay**: one row per (task, day), time attributed to that day.
/// - **byWeek**: one row per (task, week), time attributed to that week.
///
/// Every row is per-task (never a bare grand total), and an optional
/// `TimeWindow` lets the user export a slice of history instead of all of it.
public enum CSVExporter {

    /// Column headers, in the order the rows are emitted.
    public static let totalsHeader = "Title,Created At,Last Activity,Duration (s),Status,Notes,Tags"
    public static let byDayHeader = "Title,Day,Duration (s),Notes,Tags"
    public static let byWeekHeader = "Title,Week Start,Duration (s),Notes,Tags"

    /// Serialize `entries` to a CSV string (header + one row per entry, in the
    /// order given). An empty list yields just the header line.
    public static func entriesToCSV(_ entries: [TimeEntry], now: Date) -> String {
        totalsToCSV(entries, now: now)
    }

    // MARK: - Totals

    /// One row per task, total tracked time.
    public static func totalsToCSV(
        _ entries: [TimeEntry],
        now: Date,
        calendar: Calendar = Calendar.current,
        window: TimeWindow? = nil
    ) -> String {
        var lines = [totalsHeader]
        for entry in entries {
            // A task contributes to the totals only if it has any time at all
            // (completed or live) inside the window.
            let total = window.map { w in totalInWindow(entry, now: now, window: w, calendar: calendar) } ?? entry.duration(at: now)
            guard total > 0 else { continue }
            let row = [
                escape(entry.title),
                iso(entry.createdAt),
                iso(entry.lastActivityAt),
                seconds(total),
                entry.runningSince != nil ? "Running" : "Stopped",
                escape(entry.notes),
                escape(entry.tags.joined(separator: "; ")),
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Total tracked seconds for `entry` inside `window` at `now`.
    private static func totalInWindow(_ entry: TimeEntry, now: Date, window: TimeWindow, calendar: Calendar) -> TimeInterval {
        let days = entry.dayBreakdown(at: now, calendar: calendar)
        return days.reduce(0) { sum, kv in
            TimeBuckets.dayInWindow(kv.key, window, calendar: calendar) ? sum + kv.value : sum
        }
    }

    // MARK: - By day

    /// One row per (task, day) with time attributed to that day.
    public static func daysToCSV(
        _ entries: [TimeEntry],
        now: Date,
        calendar: Calendar = Calendar.current,
        window: TimeWindow? = nil
    ) -> String {
        var lines = [byDayHeader]
        for entry in entries {
            let days = entry.dayBreakdown(at: now, calendar: calendar)
            for key in days.keys.sorted() {
                if let window, !TimeBuckets.dayInWindow(key, window, calendar: calendar) { continue }
                let secs = days[key] ?? 0
                guard secs > 0 else { continue }
                let row = [
                    escape(entry.title),
                    key,
                    seconds(secs),
                    escape(entry.notes),
                    escape(entry.tags.joined(separator: "; ")),
                ]
                lines.append(row.joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - By week

    /// One row per (task, week) with time attributed to that week.
    public static func weeksToCSV(
        _ entries: [TimeEntry],
        now: Date,
        calendar: Calendar = Calendar.current,
        weekStart: WeekStart = .monday,
        window: TimeWindow? = nil
    ) -> String {
        var lines = [byWeekHeader]
        for entry in entries {
            let days = entry.dayBreakdown(at: now, calendar: calendar)
            let weeks = TimeBuckets.groupWeeks(days: days, calendar: calendar, weekStart: weekStart)
            for weekKey in weeks.keys.sorted() {
                // A week is in the window when its first day falls in it.
                if let window, !TimeBuckets.dayInWindow(weekKey, window, calendar: calendar) { continue }
                let secs = weeks[weekKey] ?? 0
                guard secs > 0 else { continue }
                let row = [
                    escape(entry.title),
                    weekKey,
                    seconds(secs),
                    escape(entry.notes),
                    escape(entry.tags.joined(separator: "; ")),
                ]
                lines.append(row.joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    /// Whole seconds, rounded, so the CSV is clean (e.g. `120`, not `120.0`).
    private static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.0f", value)
    }

    /// RFC-4180 field escaping: wrap in quotes and double any embedded quotes.
    /// Fields without special characters are left bare for readability.
    private static func escape(_ value: String) -> String {
        let needsQuotes = value.contains(where: { $0 == "\"" || $0 == "," || $0 == "\n" || $0 == "\r" })
        guard needsQuotes else { return value }
        let doubled = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"" + doubled + "\""
    }

    /// ISO-8601 timestamp, e.g. `2026-09-14T18:44:00Z`.
    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
