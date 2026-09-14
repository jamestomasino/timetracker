import Foundation

/// Pure, AppKit-free CSV serialization of tracked entries.
///
/// Kept in Core so it is unit-testable without a UI. `now` is injected so the
/// duration of a running entry is deterministic under test.
public enum CSVExporter {

    /// Column header, in the order the rows are emitted.
    public static let header = "Title,Created At,Last Activity,Duration (s),Status"

    /// Serialize `entries` to a CSV string (header + one row per entry, in the
    /// order given). An empty list yields just the header line.
    public static func entriesToCSV(_ entries: [TimeEntry], now: Date) -> String {
        var lines = [header]
        for entry in entries {
            let row = [
                escape(entry.title),
                iso(entry.createdAt),
                iso(entry.lastActivityAt),
                durationString(entry, at: now),
                entry.runningSince != nil ? "Running" : "Stopped",
            ]
            lines.append(row.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Same duration definition as the engine: completed time plus the live
    /// running interval, clamped at zero.
    private static func durationString(_ entry: TimeEntry, at now: Date) -> String {
        let running = entry.runningSince.map { now.timeIntervalSince($0) } ?? 0
        let total = max(0, entry.accumulated + running)
        return String(format: "%.0f", total)
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
