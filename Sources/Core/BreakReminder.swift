import Foundation

/// Pure, clock/calendar-injected decision logic for the hourly break reminder.
///
/// The rule: while a task is running, remind the user once per calendar hour,
/// at the top of the hour. The view model calls this on its 1-second ticker;
/// it only needs to know "did we cross into a new hour since the last check?"
/// Keeping it pure (no timers, no notifications) makes it fully deterministic
/// under test.
public enum BreakReminder {
    /// Collapse an instant to the start of its calendar hour.
    ///
    /// Two instants map to the same bucket iff they fall within the same
    /// calendar hour, so bucketing is a cheap "which hour are we in?" key.
    public static func hourBucket(
        for date: Date,
        calendar: Calendar = Calendar.current
    ) -> Date {
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: comps) ?? date
    }

    /// True when `now` is in a different hour bucket than `lastBucket`, i.e. we
    /// have crossed an hour boundary since the last check.
    ///
    /// A `nil` `lastBucket` means "we have not checked yet" and returns false,
    /// so the first tick arms the reminder instead of firing it immediately.
    public static func crossedHourBoundary(
        now: Date,
        lastBucket: Date?,
        calendar: Calendar = Calendar.current
    ) -> Bool {
        guard let lastBucket else { return false }
        return hourBucket(for: now, calendar: calendar) != lastBucket
    }
}
