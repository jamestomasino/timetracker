import Foundation

#if canImport(TimeTrackerCore)
import TimeTrackerCore
#endif

// Lightweight assertion harness. Compiles the Core sources + this file into a
// single executable (no XCTest runner needed), so `swiftc ... && ./tests` works
// without SwiftPM or Xcode.

private var passed = 0
private var failed = 0
private var currentSection = ""

private func section(_ name: String) {
    currentSection = name
    print("\n\(name)")
}

private func check(_ cond: Bool, _ label: String, _ file: String = #file, _ line: Int = #line) {
    if cond {
        passed += 1
        print("  ✓ \(label)")
    } else {
        failed += 1
        print("  ✗ FAIL: \(label)  (\(file.split(separator: "/").last!.description):\(line))")
    }
}

private func approx(_ a: Double, _ b: Double, _ label: String, _ tol: Double = 0.0001) {
    check(abs(a - b) <= tol, "\(label)  (got \(a), want \(b))")
}

// A clock we can advance by hand so assertions are exact (no sleeps).
// Thread-safe (lock-guarded) so it satisfies `Clock: Sendable` even in the
// Swift 6 language mode, where a mutable stored property in a Sendable class
// is an error.
final class ManualClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date
    init(instant: Date) { self.instant = instant }
    func now() -> Date { lock.withLock { self.instant } }
    func advance(_ s: TimeInterval) { lock.withLock { self.instant = self.instant.addingTimeInterval(s) } }
}

let t0 = Date(timeIntervalSince1970: 0)
var clock = ManualClock(instant: t0)
var engine = TimeTrackerEngine(clock: clock)

func reset() {
    clock = ManualClock(instant: t0)
    engine = TimeTrackerEngine(clock: clock)
}

// MARK: - Add
section("add")
reset()
let e1 = engine.add(title: "Email")
check(engine.entries.count == 1, "adds one entry")
check(e1.runningSince == nil, "new task starts stopped")
approx(engine.elapsed(for: e1, at: clock.now()), 0, "new task has zero elapsed")

reset()
let e2 = engine.add(title: "   Standup   ")
check(e2.title == "Standup", "title is trimmed")

// MARK: - Start / stop / elapsed
section("start / stop / elapsed")
reset()
let a = engine.add(title: "Focus").id
engine.start(id: a)
clock.advance(90)
approx(engine.elapsed(for: engine.entry(id: a)!, at: clock.now()), 90, "elapsed tracks running time")

reset()
let s = engine.add(title: "Focus").id
engine.start(id: s)
clock.advance(60)
engine.stop(id: s)
approx(engine.entry(id: s)!.accumulated, 60, "stop folds interval into accumulated")
check(engine.entry(id: s)!.runningSince == nil, "entry is stopped after stop")
clock.advance(1000)
approx(engine.elapsed(for: engine.entry(id: s)!, at: clock.now()), 60, "stopped time does not grow")

reset()
let r = engine.add(title: "Focus").id
engine.start(id: r); clock.advance(30); engine.stop(id: r)
engine.start(id: r); clock.advance(20); engine.stop(id: r)
approx(engine.entry(id: r)!.accumulated, 50, "restart accumulates across runs")

// MARK: - Day attribution on stop
section("day attribution on stop")
// The stop path (foldRunning) is the runtime recorder of `dayTotals`. Verify a
// start->stop folds the interval into `dayTotals` for the day it occurred in,
// so by-day/by-week exports have data without relying on the legacy fallback.
reset()
let attr = engine.add(title: "Attributed").id
engine.start(id: attr)
let stopAt = clock.now().addingTimeInterval(60)
engine.stop(id: attr, now: stopAt)
let daEntry = engine.entry(id: attr)!
approx(daEntry.accumulated, 60, "stop folds the interval into accumulated")
check(daEntry.dayTotals.count == 1, "a same-day stop yields exactly one day bucket")
let expectedDay = TimeBuckets.dayKey(for: stopAt, calendar: Calendar.current)
check(daEntry.dayTotals[expectedDay] == 60,
      "the completed interval is attributed to the stop day")
approx(daEntry.dayBreakdown(at: stopAt, calendar: Calendar.current).values.reduce(0, +), 60,
       "dayBreakdown reflects the recorded total")

// A second run the same day adds to the same bucket rather than a new one.
engine.start(id: attr, now: stopAt)
engine.stop(id: attr, now: stopAt.addingTimeInterval(30))
approx(engine.entry(id: attr)!.accumulated, 90, "second same-day run adds to accumulated")
approx(engine.entry(id: attr)!.dayTotals[expectedDay] ?? -1, 90,
       "second same-day run merges into the same day bucket")

// The stop path must honor the *injected* calendar, not Calendar.current.
// Prove it with a cross-timezone check: the same instant that is still
// 2026-03-16 in UTC is already 2026-03-17 in Tokyo (UTC+9), so two engines
// that stop at that instant must attribute the time to different days.
var utcCal = Calendar(identifier: .gregorian)
utcCal.timeZone = TimeZone(identifier: "UTC")!
var tokyoCal = Calendar(identifier: .gregorian)
tokyoCal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
// Build the boundary instant directly in UTC: 2026-03-16 23:30:00 UTC.
let utcStop = DateComponents(calendar: utcCal, year: 2026, month: 3, day: 16,
                             hour: 23, minute: 30, second: 0).date!
let utcStart = utcStop.addingTimeInterval(-60)
let engUtc = TimeTrackerEngine(clock: ManualClock(instant: utcStart), calendar: utcCal)
let engTokyo = TimeTrackerEngine(clock: ManualClock(instant: utcStart), calendar: tokyoCal)
let aUtc = engUtc.add(title: "TZ", start: true, now: utcStart).id
let aTokyo = engTokyo.add(title: "TZ", start: true, now: utcStart).id
engUtc.stop(id: aUtc, now: utcStop)
engTokyo.stop(id: aTokyo, now: utcStop)
let utcKey = TimeBuckets.dayKey(for: utcStop, calendar: utcCal)
let tokyoKey = TimeBuckets.dayKey(for: utcStop, calendar: tokyoCal)
check(utcKey != tokyoKey, "the boundary instant falls on different days in UTC vs Tokyo")
check(engUtc.entry(id: aUtc)!.dayTotals[utcKey] == 60,
      "UTC engine attributes the interval to the UTC day")
check(engTokyo.entry(id: aTokyo)!.dayTotals[tokyoKey] == 60,
      "Tokyo engine attributes the interval to the Tokyo day")
check(engTokyo.entry(id: aTokyo)!.dayTotals[utcKey] == nil,
      "Tokyo engine does not attribute to the UTC day")

// MARK: - Auto-stop (only one running at a time)
section("auto-stop")
reset()
let xa = engine.add(title: "A").id
let xb = engine.add(title: "B").id
engine.start(id: xa); clock.advance(10)
engine.start(id: xb)
check(engine.entry(id: xa)!.runningSince == nil, "starting B stops A")
approx(engine.entry(id: xa)!.accumulated, 10, "A keeps its 10s")
check(engine.entry(id: xb)!.runningSince != nil, "B is running")
check(engine.runningID == xb, "runningID is B")

reset()
let ids = (0..<5).map { i in engine.add(title: "T\(i)").id }
for id in ids { engine.start(id: id) }
check(engine.entries.filter { $0.runningSince != nil }.count == 1, "exactly one running after 5 starts")
check(engine.runningID == ids.last, "the last-started task is the one running")

reset()
let same = engine.add(title: "A").id
engine.start(id: same); clock.advance(5)
engine.start(id: same)
approx(engine.elapsed(for: engine.entry(id: same)!, at: clock.now()), 5, "re-starting a running task does not reset")

// MARK: - Toggle
section("toggle")
reset()
let tg = engine.add(title: "X").id
engine.toggle(id: tg)
check(engine.entry(id: tg)!.runningSince != nil, "toggle starts a stopped task")
clock.advance(15)
engine.toggle(id: tg)
check(engine.entry(id: tg)!.runningSince == nil, "toggle stops a running task")
approx(engine.entry(id: tg)!.accumulated, 15, "toggle records the interval")

// MARK: - Add & start
section("add & start")
reset()
let aa = engine.add(title: "A").id
engine.start(id: aa); clock.advance(7)
let bb = engine.add(title: "B", start: true).id
check(engine.entry(id: aa)!.runningSince == nil, "add&start stops the previous runner")
approx(engine.entry(id: aa)!.accumulated, 7, "previous runner keeps its time")
check(engine.runningID == bb, "the new task is the one running")

// MARK: - Ordering (recent)
section("recent ordering")
reset()
let oa = engine.add(title: "A").id
let ob = engine.add(title: "B").id
engine.start(id: oa); engine.start(id: ob)
check(engine.recent.first?.id == ob, "running task is pinned to top")

reset()
let c1 = engine.add(title: "A").id
clock.advance(10)
let c2 = engine.add(title: "B").id
clock.advance(10)
let c3 = engine.add(title: "C").id
check(engine.recent.map(\.id) == [c3, c2, c1], "recent orders most-recently-active first")

// MARK: - Search
section("search")
reset()
_ = engine.add(title: "Alpha"); _ = engine.add(title: "Beta")
check(engine.search("").count == 2, "empty query returns all")
check(engine.search("   ").count == 2, "whitespace query returns all")

reset()
_ = engine.add(title: "Write report"); _ = engine.add(title: "Read docs"); _ = engine.add(title: "Meeting")
check(engine.search("rep").count == 1, "substring match")
check(engine.search("REPO").count == 1, "case-insensitive")
check(engine.search("read").count == 1, "matches another title")
check(engine.search("zzz").count == 0, "no match returns empty")

// MARK: - Delete
section("delete")
reset()
let da = engine.add(title: "A").id
let db = engine.add(title: "B").id
engine.start(id: da); clock.advance(3)
engine.delete(id: da)
check(engine.entries.count == 1, "delete removes the entry")
check(engine.entries.first?.id == db, "other entry remains")
check(engine.runningID == nil, "no task running after deleting the runner")

// MARK: - Persistence round-trip
section("persistence round-trip")
reset()
let p = engine.add(title: "A").id
engine.start(id: p); clock.advance(42)
let snap = engine.snapshot()
let data = try JSONEncoder().encode(snap)
let decoded = try JSONDecoder().decode(TimeTrackerEngine.Snapshot.self, from: data)
let engine2 = TimeTrackerEngine(clock: clock)
engine2.restore(decoded)
check(engine2.entries.count == 1, "snapshot restores one entry")
check(engine2.entry(id: p)!.runningSince != nil, "running state survives round-trip")
approx(engine2.elapsed(for: engine2.entry(id: p)!, at: clock.now()), 42, "live elapsed survives round-trip")

// A stopped task's dayTotals must survive the round-trip too, otherwise the
// by-day/by-week export silently loses data after a restart.
reset()
let q = engine.add(title: "D").id
engine.start(id: q); clock.advance(60)
engine.stop(id: q)
let qEntry = engine.entry(id: q)!
check(qEntry.dayTotals.count == 1, "stopped task has one day bucket before round-trip")
let snap2 = engine.snapshot()
let data2 = try JSONEncoder().encode(snap2)
let decoded2 = try JSONDecoder().decode(TimeTrackerEngine.Snapshot.self, from: data2)
let engine3 = TimeTrackerEngine(clock: clock)
engine3.restore(decoded2)
let qEntry2 = engine3.entry(id: q)!
check(qEntry2.dayTotals.count == qEntry.dayTotals.count, "dayTotals key count survives round-trip")
for (key, val) in qEntry.dayTotals {
    check(abs((qEntry2.dayTotals[key] ?? 0) - val) < 0.001, "dayTotals[\(key)] survives round-trip")
}

// MARK: - TimeBuckets (day / week / window)
section("time buckets")
// A fixed UTC calendar so the day/week math is deterministic regardless of the
// machine's time zone.
let utc = Calendar(identifier: .gregorian)
var dayCal = Calendar(identifier: .gregorian)
dayCal.timeZone = TimeZone(identifier: "UTC")!
let weekCal = dayCal

// 2026-03-15 is a Sunday (UTC).
let march15 = Date(timeIntervalSince1970: 1_773_552_000)
let march16 = march15.addingTimeInterval(86400)
let march17 = march15.addingTimeInterval(172800)

// dayKey: same day -> same key; next day -> different key.
check(TimeBuckets.dayKey(for: march15, calendar: dayCal)
      == TimeBuckets.dayKey(for: march15.addingTimeInterval(43200), calendar: dayCal),
      "two instants on the same day share a key")
check(TimeBuckets.dayKey(for: march15, calendar: dayCal)
      != TimeBuckets.dayKey(for: march16, calendar: dayCal),
      "the next day is a different key")

// splitByDay: an interval that does not cross a boundary is one bucket.
let single = TimeBuckets.splitByDay(
    start: march15.addingTimeInterval(3600),
    end: march15.addingTimeInterval(7200),
    calendar: dayCal)
check(single.count == 1, "same-day interval -> one bucket")
approx(single.values.first ?? -1, 3600, "same-day interval keeps its duration")

// splitByDay: an interval crossing a midnight is split 50/50. Anchor on the
// calendar's own midnights so the halves are exactly 12h each regardless of the
// instant's time of day.
let mid1 = dayCal.startOfDay(for: march15)
let mid2 = dayCal.startOfDay(for: march16)
let splitCrossed = TimeBuckets.splitByDay(
    start: mid1.addingTimeInterval(43200),   // 12:00 on the 15th
    end: mid2.addingTimeInterval(43200),     // 12:00 on the 16th
    calendar: dayCal)
check(splitCrossed.count == 2, "cross-midnight interval -> two buckets")
approx(splitCrossed[TimeBuckets.dayKey(for: mid1, calendar: dayCal)] ?? -1, 43200,
       "first day gets the first half")
approx(splitCrossed[TimeBuckets.dayKey(for: mid2, calendar: dayCal)] ?? -1, 43200,
       "second day gets the second half")

// splitByDay: a degenerate (zero-length) interval is empty, not a crash.
check(TimeBuckets.splitByDay(start: march15, end: march15, calendar: dayCal).isEmpty,
      "zero-length interval -> no buckets")

// weekKey: a week of 7 consecutive days is one key; the day after is another.
// Anchor on a Monday so the 7 days (Mon..Sun) sit inside a single Monday-start week.
let weekAnchor = dayCal.startOfDay(for: march16)   // 2026-03-16 is a Monday
let wk1 = TimeBuckets.weekKey(for: weekAnchor, calendar: weekCal, weekStart: .monday)
let wk7 = TimeBuckets.weekKey(for: weekAnchor.addingTimeInterval(6 * 86400), calendar: weekCal, weekStart: .monday)
let wk8 = TimeBuckets.weekKey(for: weekAnchor.addingTimeInterval(7 * 86400), calendar: weekCal, weekStart: .monday)
check(wk1 == wk7, "7 consecutive days share a week key")
check(wk1 != wk8, "the day after the week is a different key")

// window(for:): "all" is nil.
check(TimeBuckets.window(for: .all, now: march15, calendar: dayCal, weekStart: .monday) == nil,
      "range .all -> no window")

// window(for:): "this week" contains the current day, is 7 days wide, and is
// anchored at local midnight. Use a Monday as "now" so a later day of the same
// week (Tuesday) is also inside.
if let tw = TimeBuckets.window(for: .thisWeek, now: march16, calendar: dayCal, weekStart: .monday) {
    check(tw.contains(march16), "this-week window contains the current day")
    approx(tw.to.timeIntervalSince(tw.from), 7 * 86400, "this-week window is 7 days wide")
    check(dayCal.component(.hour, from: tw.from) == 0, "window starts at local midnight")
    check(tw.contains(march17), "this-week window contains a later day of the same week")
} else {
    check(false, "this-week window should not be nil")
}

// window(for:): "this month" contains the 1st of the month.
if let tm = TimeBuckets.window(for: .thisMonth, now: march15, calendar: dayCal, weekStart: .monday) {
    let first = dayCal.date(from: dayCal.dateComponents([.year, .month], from: march15))!
    check(tm.contains(first), "this-month window contains the 1st")
    check(tm.contains(march15), "this-month window contains the current day")
} else {
    check(false, "this-month window should not be nil")
}

// window(for:): "last 30 days" is exactly 30 days wide and contains today.
if let l30 = TimeBuckets.window(for: .last30Days, now: march15, calendar: dayCal, weekStart: .monday) {
    approx(l30.to.timeIntervalSince(l30.from), 30 * 86400, "last-30-days window is 30 days wide")
    check(l30.contains(march15), "last-30-days window contains today")
    check(!l30.contains(march15.addingTimeInterval(-31 * 86400)),
          "a day 31 days ago is outside last-30-days")
} else {
    check(false, "last-30-days window should not be nil")
}

// inWindow: entries inside the window pass; outside are excluded.
let inside = TimeEntry(id: UUID(), title: "in", accumulated: 10, runningSince: nil,
                       createdAt: march15, lastActivityAt: march15)
let outside = TimeEntry(id: UUID(), title: "out", accumulated: 10, runningSince: nil,
                        createdAt: march15.addingTimeInterval(-40 * 86400),
                        lastActivityAt: march15.addingTimeInterval(-40 * 86400))
if let w = TimeBuckets.window(for: .last30Days, now: march15, calendar: dayCal, weekStart: .monday) {
    check(inside.inWindow(w), "entry inside the window passes the filter")
    check(!outside.inWindow(w), "entry outside the window is filtered out")
} else {
    check(false, "window should not be nil for inWindow check")
}

// MARK: - CSV export
section("csv export")
let csvNow = Date(timeIntervalSince1970: 1_000_000)
let csvStopped = TimeEntry(
    id: UUID(),
    title: "Design",
    accumulated: 120,
    runningSince: nil,
    createdAt: Date(timeIntervalSince1970: 999_000),
    lastActivityAt: Date(timeIntervalSince1970: 999_120)
)
let csvRunning = TimeEntry(
    id: UUID(),
    title: "Build",
    accumulated: 0,
    runningSince: Date(timeIntervalSince1970: 999_900),
    createdAt: Date(timeIntervalSince1970: 999_900),
    lastActivityAt: Date(timeIntervalSince1970: 999_900)
)
let csvOut = CSVExporter.entriesToCSV([csvStopped, csvRunning], now: csvNow)
let csvLines = csvOut.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

check(csvLines.first == CSVExporter.totalsHeader, "header is first line")
check(csvLines.count == 3, "one row per entry (got \(csvLines.count))")

let stoppedRow = csvLines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
check(stoppedRow[4] == "Stopped", "stopped status")
check(stoppedRow[3] == "120", "stopped duration = accumulated (got \(stoppedRow[3]))")
check(stoppedRow[5] == "", "stopped notes empty by default")
check(stoppedRow[6] == "", "stopped tags empty by default")

let runningRow = csvLines[2].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
check(runningRow[4] == "Running", "running status")
check(runningRow[3] == "100", "running duration = now - runningSince (got \(runningRow[3]))")

let tricky = TimeEntry(id: UUID(), title: "A, \"quoted\"\nline", accumulated: 5,
                       runningSince: nil, createdAt: csvNow, lastActivityAt: csvNow)
check(CSVExporter.entriesToCSV([tricky], now: csvNow).contains("\"A, \"\"quoted\"\"\nline\""),
      "comma/quote/newline title is RFC-4180 escaped")

check(CSVExporter.entriesToCSV([], now: csvNow) == CSVExporter.totalsHeader + "\n",
      "empty list is header only")

// The real write step exportCSV() performs after the panel returns a URL:
// serialize -> atomic write to a file -> read it back. Confirms the bytes that
// land on disk are exactly the CSV, not just the in-memory string.
do {
    let writeURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("timetracker-csv-roundtrip-\(UUID().uuidString).csv")
    let writeCSV = CSVExporter.entriesToCSV([csvStopped, csvRunning, tricky], now: csvNow)
    try Data(writeCSV.utf8).write(to: writeURL, options: .atomic)
    let roundTrip = try Data(contentsOf: writeURL)
    try FileManager.default.removeItem(at: writeURL)
    check(roundTrip == Data(writeCSV.utf8), "exported file is byte-for-byte the CSV (got \(roundTrip.count) bytes)")
} catch {
    check(false, "export write/read round-trip threw: \(error)")
}

// MARK: - parseTags
section("parseTags")
check(parseTags("") == [], "empty string -> no tags")
check(parseTags("   ") == [], "whitespace only -> no tags")
check(parseTags("Work, design") == ["work", "design"], "comma split, lowercased")
check(parseTags("work, design , design, urgent") == ["work", "design", "urgent"], "dedupes and trims")
check(parseTags("a;b;c") == ["a", "b", "c"], "semicolon split")
check(parseTags("  X  ,  x  ") == ["x"], "case-insensitive dedup")
check(parseTags("solo") == ["solo"], "single tag")

// MARK: - Notes & tags search
section("notes & tags search")
reset()
let n1 = engine.add(title: "Client call").id
let n2 = engine.add(title: "Internal sync").id
engine.update(id: n1, notes: "discuss Q3 roadmap", tags: ["client", "sales"])
engine.update(id: n2, notes: "weekly team check-in", tags: ["team"])
check(engine.search("roadmap").count == 1, "search matches notes")
check(engine.search("roadmap").first?.id == n1, "notes match is the right task")
check(engine.search("client").count == 1, "search matches a tag")
check(engine.search("sales").count == 1, "search matches another tag")
check(engine.search("internal").count == 1, "title search still works")
check(engine.search("zzz").count == 0, "no match still empty")

// MARK: - update()
section("update notes/tags")
reset()
let u = engine.add(title: "Task").id
check(engine.entry(id: u)!.notes == "", "new entry has empty notes")
check(engine.entry(id: u)!.tags.isEmpty, "new entry has no tags")
engine.update(id: u, notes: "hello", tags: ["a", "b"])
check(engine.entry(id: u)!.notes == "hello", "update sets notes")
check(engine.entry(id: u)!.tags == ["a", "b"], "update sets tags")
engine.update(id: u, notes: "changed")
check(engine.entry(id: u)!.tags == ["a", "b"], "partial update keeps tags")
// Update on a missing id is a no-op, not a crash.
engine.update(id: UUID(), notes: "ghost")
check(engine.entries.count == 1, "update on missing id is a no-op")

// MARK: - Backward-compat decode
section("backward-compat decode")
// A snapshot written by an older version (no notes/tags keys) must still load.
// Dates are numeric (the app's default JSONEncoder date strategy).
let legacyJSON = """
{
  "id": "00000000-0000-0000-0000-000000000001",
  "title": "Legacy task",
  "accumulated": 30,
  "runningSince": null,
  "createdAt": 1704067200,
  "lastActivityAt": 1704067230
}
"""
do {
    let decoded = try JSONDecoder().decode(TimeEntry.self, from: Data(legacyJSON.utf8))
    check(decoded.title == "Legacy task", "legacy entry decodes title")
    check(decoded.notes == "", "legacy entry defaults notes to empty")
    check(decoded.tags.isEmpty, "legacy entry defaults tags to empty")
} catch {
    check(false, "legacy decode threw: \(error)")
}

// A modern entry with notes/tags round-trips through JSON.
do {
    let modern = TimeEntry(id: UUID(), title: "Modern", notes: "hi", tags: ["x"])
    let data = try JSONEncoder().encode(modern)
    let back = try JSONDecoder().decode(TimeEntry.self, from: data)
    check(back.notes == "hi", "modern notes round-trip")
    check(back.tags == ["x"], "modern tags round-trip")
} catch {
    check(false, "modern round-trip threw: \(error)")
}

// MARK: - CSV notes/tags columns
section("csv notes/tags columns")
let taggedEntry = TimeEntry(
    id: UUID(),
    title: "Tagged",
    accumulated: 10,
    runningSince: nil,
    createdAt: csvNow,
    lastActivityAt: csvNow,
    notes: "needs, a comma",
    tags: ["work", "urgent"]
)
let taggedCSV = CSVExporter.entriesToCSV([taggedEntry], now: csvNow)
let taggedLines = taggedCSV.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
check(taggedLines.count == 2, "one row for tagged entry")
// Notes contain a comma so the field must be quoted.
check(taggedLines[1].contains("\"needs, a comma\""), "notes with comma are quoted")
check(taggedLines[1].contains("work; urgent"), "tags joined with '; '")

// MARK: - dayBreakdown (per-day attribution)
section("day breakdown")
// A fixed UTC calendar so day math is deterministic.
var dbCal = Calendar(identifier: .gregorian)
dbCal.timeZone = TimeZone(identifier: "UTC")!
// d1 is a Monday and d2 the following Tuesday, so the two days fall in the
// same week under a Monday-start setting (a Sunday d1 would straddle two weeks).
let d1 = Date(timeIntervalSince1970: 1_773_619_200)      // 2026-03-16 (Mon)
let d2 = d1.addingTimeInterval(86400)                    // 2026-03-17 (Tue)
let k1 = TimeBuckets.dayKey(for: d1, calendar: dbCal)
let k2 = TimeBuckets.dayKey(for: d2, calendar: dbCal)

// A stopped entry with recorded dayTotals: breakdown == those totals.
let recorded = TimeEntry(id: UUID(), title: "Recorded",
    accumulated: 200, runningSince: nil, createdAt: d1, lastActivityAt: d2,
    dayTotals: [k1: 120, k2: 80])
let recBD = recorded.dayBreakdown(at: d2, calendar: dbCal)
check(recBD[k1] == 120, "recorded day total is preserved")
check(recBD[k2] == 80, "second day total is preserved")
approx(recBD.values.reduce(0, +), 200, "recorded breakdown sums to accumulated")

// A legacy stopped entry (no dayTotals, accumulated > 0): all time is attributed
// to the lastActivityAt day.
let legacy = TimeEntry(id: UUID(), title: "Legacy",
    accumulated: 90, runningSince: nil, createdAt: d1, lastActivityAt: d2)
let legBD = legacy.dayBreakdown(at: d2, calendar: dbCal)
check(legBD[k2] == 90, "legacy stopped time is attributed to the last-activity day")
check(legBD[k1] == nil, "legacy time is not split across other days")

// A legacy RUNNING entry: accumulated is attributed to the last-activity day AND
// the live interval is split by day, so the running split appears alongside.
let runningLegacy = TimeEntry(id: UUID(), title: "RunningLegacy",
    accumulated: 30, runningSince: d2.addingTimeInterval(3600),
    createdAt: d1, lastActivityAt: d2)
let runBD = runningLegacy.dayBreakdown(at: d2.addingTimeInterval(7200), calendar: dbCal)
check(runBD[k2] == 30 + 3600, "running legacy: accumulated + live split share the day")
approx(runBD.values.reduce(0, +), 30 + 3600, "running legacy breakdown sums to total")

// A zero-time entry (never ran, no recorded totals) has an empty breakdown.
let zero = TimeEntry(id: UUID(), title: "Zero",
    accumulated: 0, runningSince: nil, createdAt: d1, lastActivityAt: d1)
check(zero.dayBreakdown(at: d1, calendar: dbCal).isEmpty, "zero-time entry has empty breakdown")

// MARK: - Export shapes (totals / by-day / by-week)
section("export shapes")
let expCal = dbCal
let expNow = d2.addingTimeInterval(1000)
let taskA = TimeEntry(id: UUID(), title: "Alpha",
    accumulated: 200, runningSince: nil, createdAt: d1, lastActivityAt: d2,
    dayTotals: [k1: 120, k2: 80])
let taskB = TimeEntry(id: UUID(), title: "Beta",
    accumulated: 90, runningSince: nil, createdAt: d1, lastActivityAt: d2)

func lines(_ s: String) -> [String] {
    s.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
}
func field(_ line: String, _ i: Int) -> String {
    line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)[i]
}

// --- totals: one row per task, total time.
let totals = CSVExporter.totalsToCSV([taskA, taskB], now: expNow, calendar: expCal)
let tLines = lines(totals)
check(tLines.first == CSVExporter.totalsHeader, "totals header is first")
check(tLines.count == 3, "totals: one row per task (got \(tLines.count))")
check(field(tLines[1], 0) == "Alpha" && field(tLines[1], 3) == "200",
      "totals row: Alpha = 200")
check(field(tLines[1], 4) == "Stopped", "totals row: Alpha is stopped")
check(field(tLines[2], 0) == "Beta" && field(tLines[2], 3) == "90",
      "totals row: Beta = 90")

// --- by day: one row per (task, day), sorted by day then task.
let days = CSVExporter.daysToCSV([taskA, taskB], now: expNow, calendar: expCal)
let dLines = lines(days)
check(dLines.first == CSVExporter.byDayHeader, "days header is first")
check(dLines.count == 4, "days: one row per (task, day) (got \(dLines.count))")
check(field(dLines[1], 0) == "Alpha" && field(dLines[1], 1) == k1 && field(dLines[1], 2) == "120",
      "days row: Alpha on day 1")
check(field(dLines[2], 0) == "Alpha" && field(dLines[2], 1) == k2 && field(dLines[2], 2) == "80",
      "days row: Alpha on day 2")
check(field(dLines[3], 0) == "Beta" && field(dLines[3], 1) == k2 && field(dLines[3], 2) == "90",
      "days row: Beta on day 2")

// --- by week: one row per (task, week). Both days are in the same ISO week
// (2026-03-15 is a Sunday; with Monday-start, d1 and d2 fall in the same week).
let weeks = CSVExporter.weeksToCSV([taskA, taskB], now: expNow, calendar: expCal, weekStart: .monday)
let wLines = lines(weeks)
check(wLines.first == CSVExporter.byWeekHeader, "weeks header is first")
let wkKey = TimeBuckets.weekKey(for: d1, calendar: expCal, weekStart: .monday)
check(wLines.count == 3, "weeks: one row per (task, week) (got \(wLines.count))")
check(field(wLines[1], 0) == "Alpha" && field(wLines[1], 1) == wkKey && field(wLines[1], 2) == "200",
      "weeks row: Alpha = 200 in its week")
check(field(wLines[2], 0) == "Beta" && field(wLines[2], 1) == wkKey && field(wLines[2], 2) == "90",
      "weeks row: Beta = 90 in its week")

// --- by week, multiple weeks: a task with time in two different weeks must
// produce one row per week (groupWeeks splits by week anchor). 2026-03-16 is
// a Monday (week 1); 2026-03-23 is the following Monday (week 2).
let multiWeek = TimeEntry(id: UUID(), title: "Span",
    accumulated: 10800, runningSince: nil,
    createdAt: d1, lastActivityAt: d1,
    dayTotals: ["2026-03-16": 3600, "2026-03-23": 7200])
let mwLines = lines(CSVExporter.weeksToCSV([multiWeek], now: expNow, calendar: expCal, weekStart: .monday))
let mw1 = TimeBuckets.weekKey(for: DateComponents(calendar: expCal, year: 2026, month: 3, day: 16).date!, calendar: expCal, weekStart: .monday)
let mw2 = TimeBuckets.weekKey(for: DateComponents(calendar: expCal, year: 2026, month: 3, day: 23).date!, calendar: expCal, weekStart: .monday)
check(mw1 != mw2, "multi-week: the two days land in different weeks")
check(mwLines.count == 3, "multi-week: header + one row per week (got \(mwLines.count))")
check(field(mwLines[1], 0) == "Span" && field(mwLines[1], 1) == mw1 && field(mwLines[1], 2) == "3600",
      "multi-week: Span = 3600 in week 1")
check(field(mwLines[2], 0) == "Span" && field(mwLines[2], 1) == mw2 && field(mwLines[2], 2) == "7200",
      "multi-week: Span = 7200 in week 2")

// --- weekStart is honored: switching the week anchor can move a day into a
// different week. Find a day whose weekKey differs between Monday and Sunday
// starts, to prove the setting is actually threaded through.
var found = false
for offset in 0..<14 {
    let a = d1.addingTimeInterval(TimeInterval(offset * 86400))
    let wkMon = TimeBuckets.weekKey(for: a, calendar: expCal, weekStart: .monday)
    let wkSun = TimeBuckets.weekKey(for: a, calendar: expCal, weekStart: .sunday)
    if wkMon != wkSun { found = true; break }
}
check(found, "some day lands in a different week under Monday vs Sunday start")

// --- date-range filtering: a window excludes entries whose activity is outside it.
let window = TimeBuckets.window(for: .last30Days, now: expNow, calendar: expCal, weekStart: .monday)!
let inRange = CSVExporter.totalsToCSV([taskA, taskB], now: expNow, calendar: expCal, window: window)
check(lines(inRange).count == 3, "a window that contains both tasks keeps both rows")

// A window that excludes both tasks (anchored far in the past) yields header only.
let past = TimeWindow(from: d1.addingTimeInterval(-100 * 86400),
                      to: d1.addingTimeInterval(-90 * 86400))
let outRange = CSVExporter.totalsToCSV([taskA, taskB], now: expNow, calendar: expCal, window: past)
check(lines(outRange).count == 1, "a window that excludes both tasks -> header only")

// MARK: - End-to-end: engine stop path -> CSV export
section("end-to-end engine -> CSV")
// The stop path (foldRunning) and the CSV exporter have each been tested in
// isolation. This test exercises them together on data that flowed through the
// real engine: a task that runs across midnight, then all three export shapes
// are run on engine.entries (not synthetic entries) and the CSV is checked.
var e2eCal = Calendar(identifier: .gregorian)
e2eCal.timeZone = TimeZone(identifier: "UTC")!
// 2026-03-16 is a Monday. Start 22:00, run 3h -> crosses midnight.
//   Day 2026-03-16: 22:00->24:00 = 7200s
//   Day 2026-03-17: 00:00->01:00 = 3600s
//   Total:          10800s
let e2eStart = DateComponents(calendar: e2eCal, year: 2026, month: 3, day: 16, hour: 22, minute: 0, second: 0).date!
let e2eStop = e2eStart.addingTimeInterval(3 * 3600)
let e2eEngine = TimeTrackerEngine(clock: ManualClock(instant: e2eStart), calendar: e2eCal)
let e2eID = e2eEngine.add(title: "Cross", start: true, now: e2eStart).id
e2eEngine.stop(id: e2eID, now: e2eStop)
let e2eEntries = e2eEngine.entries
check(e2eEntries.count == 1, "e2e: one entry in the engine")
approx(e2eEntries.first!.accumulated, 10800, "e2e: engine recorded 10800s")
check(e2eEntries.first!.dayTotals.count == 2, "e2e: engine attributed to two days")

let e2eDay1 = TimeBuckets.dayKey(for: e2eStart, calendar: e2eCal)
let e2eDay2 = TimeBuckets.dayKey(for: e2eStop, calendar: e2eCal)
check(e2eDay1 != e2eDay2, "e2e: start and stop fall on different days")

// --- totals: one row, 10800s.
let e2eTotals = CSVExporter.totalsToCSV(e2eEntries, now: e2eStop, calendar: e2eCal)
let e2eTLines = lines(e2eTotals)
check(e2eTLines.count == 2, "e2e totals: header + one row")
check(field(e2eTLines[1], 0) == "Cross" && field(e2eTLines[1], 3) == "10800",
      "e2e totals: Cross = 10800")
check(field(e2eTLines[1], 4) == "Stopped", "e2e totals: Cross is stopped")

// --- by day: two rows (7200 on day1, 3600 on day2).
let e2eDays = CSVExporter.daysToCSV(e2eEntries, now: e2eStop, calendar: e2eCal)
let e2eDLines = lines(e2eDays)
check(e2eDLines.count == 3, "e2e days: header + two rows")
check(field(e2eDLines[1], 0) == "Cross" && field(e2eDLines[1], 1) == e2eDay1 && field(e2eDLines[1], 2) == "7200",
      "e2e days: Cross = 7200 on day 1")
check(field(e2eDLines[2], 0) == "Cross" && field(e2eDLines[2], 1) == e2eDay2 && field(e2eDLines[2], 2) == "3600",
      "e2e days: Cross = 3600 on day 2")

// --- by week: both days are in the same Monday-start week -> one row, 10800s.
let e2eWeeks = CSVExporter.weeksToCSV(e2eEntries, now: e2eStop, calendar: e2eCal, weekStart: .monday)
let e2eWLines = lines(e2eWeeks)
let e2eWkKey = TimeBuckets.weekKey(for: e2eStart, calendar: e2eCal, weekStart: .monday)
check(e2eWLines.count == 2, "e2e weeks: header + one row")
check(field(e2eWLines[1], 0) == "Cross" && field(e2eWLines[1], 1) == e2eWkKey && field(e2eWLines[1], 2) == "10800",
      "e2e weeks: Cross = 10800 in its week")

// --- date-range filter: a window that contains both days keeps all rows.
let e2eWindow = TimeBuckets.window(for: .last30Days, now: e2eStop, calendar: e2eCal, weekStart: .monday)!
let e2eFiltered = CSVExporter.daysToCSV(e2eEntries, now: e2eStop, calendar: e2eCal, window: e2eWindow)
check(lines(e2eFiltered).count == 3, "e2e days: a window containing both days keeps both rows")

// A window that excludes both days yields header only.
let e2ePast = TimeWindow(from: e2eStart.addingTimeInterval(-100 * 86400),
                         to: e2eStart.addingTimeInterval(-90 * 86400))
let e2eExcluded = CSVExporter.daysToCSV(e2eEntries, now: e2eStop, calendar: e2eCal, window: e2ePast)
check(lines(e2eExcluded).count == 1, "e2e days: a window excluding both days -> header only")

// MARK: - Toasts (ViewModel)
section("toasts")
// TrackerViewModel is @MainActor; this harness runs on the main thread, so we
// hop onto the main actor for the duration of these checks.
MainActor.assumeIsolated {
    // Point the store at a throwaway file so the test never reads or writes the
    // user's real Application Support data.
    let toastDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("timetracker-toast-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: toastDir, withIntermediateDirectories: true)
    let toastEngine = TimeTrackerEngine(clock: clock)
    let vm = TrackerViewModel(
        engine: toastEngine,
        store: EntryStore(engine: toastEngine, fileURL: toastDir.appendingPathComponent("entries.json")),
        settingsStore: SettingsStore.inMemory()
    )
    check(vm.showToast == false, "no toast shown initially")
    check(vm.toastMessage.isEmpty, "toast message empty initially")

    vm.showToast("hello")
    check(vm.showToast == true, "showToast turns the toast on")
    check(vm.toastMessage == "hello", "toast carries the message")

    vm.showToast("second")
    check(vm.toastMessage == "second", "a second toast replaces the first")

    // confirmDelete fires a "Deleted ..." toast and removes the entry.
    vm.addTask("Doomed", start: false)
    let before = vm.entries.count
    vm.delete(vm.entries.first!)
    check(vm.pendingDelete != nil, "delete is staged for confirmation")
    vm.confirmDelete()
    check(vm.showToast == true, "confirmDelete shows a toast")
    check(vm.toastMessage == "Deleted \"Doomed\"", "delete toast names the task")
    check(vm.entries.count == before - 1, "entry is removed on confirm")
    check(vm.pendingDelete == nil, "pending delete clears after confirm")

    try? FileManager.default.removeItem(at: toastDir)
}

// MARK: - EntryStore (file persistence)
section("entry store")

// A unique temp dir so parallel runs never collide.
let storeDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("timetracker-store-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
let storeFile = storeDir.appendingPathComponent("entries.json")
let storeBackup = storeFile.appendingPathExtension("bak")

func freshEngine() -> TimeTrackerEngine { TimeTrackerEngine(clock: clock) }

do {
    // 1. Load with no file present: engine stays empty, no crash.
    let emptyEngine = freshEngine()
    let emptyStore = EntryStore(engine: emptyEngine, fileURL: storeFile)
    emptyStore.load()
    check(emptyEngine.entries.isEmpty, "load with no file leaves engine empty")

    // 2. Save then load into a fresh engine: entries survive the round-trip.
    let src = freshEngine()
    let savedId = src.add(title: "Design").id
    src.start(id: savedId); clock.advance(42)
    src.stop(id: savedId)
    let s1 = EntryStore(engine: src, fileURL: storeFile)
    s1.saveNow()
    check(FileManager.default.fileExists(atPath: storeFile.path), "saveNow writes the primary file")

    let dst = freshEngine()
    let s2 = EntryStore(engine: dst, fileURL: storeFile)
    s2.load()
    check(dst.entries.count == 1, "load restores one entry")
    approx(dst.entry(id: savedId)!.accumulated, 42, "accumulated survives save/load")

    // 3. A second save rotates the previous primary into a .bak backup.
    let src2 = freshEngine()
    src2.add(title: "Meeting")
    let s3 = EntryStore(engine: src2, fileURL: storeFile)
    s3.saveNow()
    check(FileManager.default.fileExists(atPath: storeBackup.path), "second save creates a .bak backup")

    // 4. Corrupt the primary: load must fall back to the backup, not wipe.
    try "not json at all".write(to: storeFile, atomically: true, encoding: .utf8)
    let recovered = freshEngine()
    let s4 = EntryStore(engine: recovered, fileURL: storeFile)
    s4.load()
    check(recovered.entries.count == 1, "corrupt primary falls back to backup")
    check(recovered.entries.first?.title == "Design", "recovered entry is the last-known-good one")

    // 5. A save that yields valid data overwrites a corrupt primary (recovers).
    let src3 = freshEngine()
    src3.add(title: "Recover")
    let s5 = EntryStore(engine: src3, fileURL: storeFile)
    s5.saveNow()
    let afterRecover = freshEngine()
    EntryStore(engine: afterRecover, fileURL: storeFile).load()
    check(afterRecover.entries.first?.title == "Recover", "a good save overwrites a corrupt primary")
} catch {
    check(false, "entry store tests threw: \(error)")
}

// Clean up the temp store dir.
try? FileManager.default.removeItem(at: storeDir)

// MARK: - ViewModel restores persisted state on init
// Regression: the app used to start with an empty engine even when a saved
// snapshot was on disk, because `TrackerViewModel.init` never called
// `store.load()`. Tracked time must survive a relaunch.
section("view model restores persisted entries")
MainActor.assumeIsolated {
    let vmDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("timetracker-vm-restore-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: vmDir, withIntermediateDirectories: true)
    let vmFile = vmDir.appendingPathComponent("entries.json")

    // Simulate a prior session: write a snapshot to disk.
    let prior = TimeTrackerEngine(clock: clock)
    let priorId = prior.add(title: "Carried over").id
    prior.start(id: priorId); clock.advance(77); prior.stop(id: priorId)
    EntryStore(engine: prior, fileURL: vmFile).saveNow()

    // A fresh view model (new engine, same file) must restore that state.
    let freshEngine = TimeTrackerEngine(clock: clock)
    let vm = TrackerViewModel(
        engine: freshEngine,
        store: EntryStore(engine: freshEngine, fileURL: vmFile),
        settingsStore: SettingsStore.inMemory()
    )
    check(vm.entries.count == 1, "vm restores one entry from disk on init")
    check(vm.entries.first?.title == "Carried over", "restored entry is the saved one")
    approx(vm.entries.first!.accumulated, 77, "restored accumulated time is intact")

    try? FileManager.default.removeItem(at: vmDir)
}

// MARK: - AppSettings (model + decode)
section("app settings")
check(AppSettings().toastEnabled == true, "toast enabled by default")
check(AppSettings().hourlyReminderEnabled == false, "hourly reminder off by default")

// A settings file written by an older version (no keys) must still load.
do {
    let legacy = """
    {}
    """
    let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
    check(decoded.toastEnabled == true, "legacy (empty) settings default toast on")
    check(decoded.hourlyReminderEnabled == false, "legacy (empty) settings default reminder off")
} catch {
    check(false, "legacy settings decode threw: \(error)")
}

// A modern settings file round-trips.
do {
    let s = AppSettings(toastEnabled: false, hourlyReminderEnabled: true)
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    check(back == s, "modern settings round-trip")
} catch {
    check(false, "modern settings round-trip threw: \(error)")
}

// MARK: - BreakReminder (pure hour-boundary logic)
section("break reminder")
// A fixed, known calendar so the hour math is deterministic regardless of the
// machine's time zone.
let cal = Calendar(identifier: .gregorian)
let base = Date(timeIntervalSince1970: 1_700_000_000) // some arbitrary instant

// Two instants within the same hour share a bucket.
let h = BreakReminder.hourBucket(for: base, calendar: cal)
check(BreakReminder.hourBucket(for: base.addingTimeInterval(59), calendar: cal) == h,
      "instants 59s apart share an hour bucket")

// Crossing an hour boundary changes the bucket.
let crossed = BreakReminder.hourBucket(for: base, calendar: cal).addingTimeInterval(3600)
check(BreakReminder.hourBucket(for: crossed, calendar: cal) != h,
      "an hour later is a different bucket")

// crossedHourBoundary: nil lastBucket means "not armed yet" -> false.
check(BreakReminder.crossedHourBoundary(now: base, lastBucket: nil, calendar: cal) == false,
      "no prior bucket -> no fire (arms the reminder)")

// Same hour -> false.
let last = BreakReminder.hourBucket(for: base, calendar: cal)
check(BreakReminder.crossedHourBoundary(now: base.addingTimeInterval(30), lastBucket: last, calendar: cal) == false,
      "same hour does not fire")

// New hour -> true.
check(BreakReminder.crossedHourBoundary(now: base.addingTimeInterval(3600), lastBucket: last, calendar: cal) == true,
      "crossing an hour boundary fires")

// MARK: - SettingsStore (persistence)
section("settings store")
let setDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("timetracker-settings-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: setDir, withIntermediateDirectories: true)
let setFile = setDir.appendingPathComponent("settings.json")

do {
    // In-memory mode: save then load returns the same value.
    let mem = SettingsStore.inMemory()
    mem.save(AppSettings(toastEnabled: false, hourlyReminderEnabled: true))
    let memLoaded = mem.load()
    check(memLoaded.toastEnabled == false, "in-memory store persists toast setting")
    check(memLoaded.hourlyReminderEnabled == true, "in-memory store persists reminder setting")

    // File mode: save then load round-trips.
    let fileStore = SettingsStore(fileURL: setFile)
    fileStore.save(AppSettings(toastEnabled: false, hourlyReminderEnabled: true))
    check(FileManager.default.fileExists(atPath: setFile.path), "save writes the settings file")
    let loaded = SettingsStore(fileURL: setFile).load()
    check(loaded.toastEnabled == false, "file store restores toast setting")
    check(loaded.hourlyReminderEnabled == true, "file store restores reminder setting")

    // A missing file falls back to defaults (toast on, reminder off).
    let missing = SettingsStore(fileURL: setDir.appendingPathComponent("nope.json")).load()
    check(missing == AppSettings(), "missing file falls back to defaults")

    // A corrupt file falls back to defaults, not a crash.
    let corruptFile = setDir.appendingPathComponent("corrupt.json")
    try "not json".write(to: corruptFile, atomically: true, encoding: .utf8)
    check(SettingsStore(fileURL: corruptFile).load() == AppSettings(),
          "corrupt file falls back to defaults")
} catch {
    check(false, "settings store tests threw: \(error)")
}
try? FileManager.default.removeItem(at: setDir)

// MARK: - Settings wiring (ViewModel)
section("settings wiring")
MainActor.assumeIsolated {
    // Capture the injected reminder side effect so we can assert on it.
    var posted: [String] = []
    var authRequested = false

    // A fresh manual clock so we can advance time to cross an hour boundary
    // deterministically, without disturbing the shared `clock` used elsewhere.
    let wiringClock = ManualClock(instant: Date(timeIntervalSince1970: 1_700_000_000))
    let wiringEngine = TimeTrackerEngine(clock: wiringClock)
    let wiringDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("timetracker-wiring-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: wiringDir, withIntermediateDirectories: true)
    let vm = TrackerViewModel(
        engine: wiringEngine,
        store: EntryStore(engine: wiringEngine, fileURL: wiringDir.appendingPathComponent("entries.json")),
        settingsStore: SettingsStore.inMemory(),
        clock: wiringClock
    )
    vm.postReminder = { posted.append($0) }
    vm.requestAuthorization = { authRequested = true }

    // Regression: the ticker must auto-start in init. It is what keeps the
    // live elapsed-time labels updating AND what drives the break reminder,
    // so if it ever stops auto-starting the reminder silently never fires in
    // production (the tests below call tick() directly and would not notice).
    check(vm.isTickerRunning, "ticker auto-starts in init")
    vm.stopTicker()
    check(!vm.isTickerRunning, "stopTicker stops the ticker")
    vm.startTicker()
    check(vm.isTickerRunning, "startTicker restarts the ticker")
    // Leave it running for the reminder checks that follow.

    // Defaults loaded from the (empty) in-memory store.
    check(vm.settings.toastEnabled == true, "vm loads toast-enabled default")
    check(vm.settings.hourlyReminderEnabled == false, "vm loads reminder-off default")

    // setToastEnabled toggles and persists to the store.
    vm.setToastEnabled(false)
    check(vm.settings.toastEnabled == false, "setToastEnabled(false) flips the setting")
    vm.setToastEnabled(true)
    check(vm.settings.toastEnabled == true, "setToastEnabled(true) flips it back")

    // Toast gating: when disabled, showToast is a no-op.
    vm.setToastEnabled(false)
    vm.showToast("hidden")
    check(vm.showToast == false, "toast suppressed when disabled")
    check(vm.toastMessage.isEmpty, "toast message untouched when disabled")
    vm.setToastEnabled(true)
    vm.showToast("shown")
    check(vm.showToast == true, "toast shown when enabled")
    check(vm.toastMessage == "shown", "toast carries the message when enabled")

    // enableHourlyReminder turns it on and requests authorization.
    vm.enableHourlyReminder()
    check(vm.settings.hourlyReminderEnabled == true, "enableHourlyReminder turns it on")
    check(authRequested == true, "enabling requests notification authorization")

    // The toggle must work in BOTH directions: turning it off flips the
    // setting (a common bug is a toggle that only ever calls "enable").
    vm.setHourlyReminderEnabled(false)
    check(vm.settings.hourlyReminderEnabled == false, "setHourlyReminderEnabled(false) turns it off")
    vm.setHourlyReminderEnabled(true)
    check(vm.settings.hourlyReminderEnabled == true, "re-enabling turns it back on")

    // Reminder does not fire when nothing is running.
    posted = []
    vm.tick()
    check(posted.isEmpty, "no reminder when no task is running")

    // Reminder fires exactly once when a task is running and an hour boundary
    // is crossed. Advance 2h (guaranteed to cross a boundary in any time zone)
    // rather than exactly 1h, which would only cross a boundary near :00.
    posted = []
    let task = wiringEngine.add(title: "Deep work").id
    wiringEngine.start(id: task)
    vm.tick()                       // arms the reminder (records current hour)
    check(posted.isEmpty, "first tick arms without firing")
    wiringClock.advance(7200)       // cross at least one hour boundary
    vm.tick()
    check(posted.count == 1, "reminder fires once when a task is running")
    check(posted.first == "Deep work", "reminder names the running task")

    // A small same-hour tick does not re-fire.
    wiringClock.advance(5)
    vm.tick()
    check(posted.count == 1, "same-hour tick does not re-fire")

    // Disabling stops reminders.
    vm.setHourlyReminderEnabled(false)
    posted = []
    wiringClock.advance(7200)
    vm.tick()
    check(posted.isEmpty, "reminder suppressed when disabled")

    // flushOnQuit must force a synchronous save so tracked time is never lost
    // to the debounce window when the app quits. A mutation only schedules a
    // debounced save (300ms); flushOnQuit writes immediately, so the entry is
    // on disk right away.
    vm.addTask("Quit flush", start: false)
    vm.flushOnQuit()
    let flushed = TimeTrackerEngine(clock: wiringClock)
    EntryStore(engine: flushed, fileURL: wiringDir.appendingPathComponent("entries.json")).load()
    check(flushed.entries.contains { $0.title == "Quit flush" },
          "flushOnQuit force-saves synchronously (no debounce window)")

    try? FileManager.default.removeItem(at: wiringDir)
}

// MARK: - Summary
print("\n──────────────────────────────")
print("\(passed) passed, \(failed) failed")
if failed > 0 {
    print("RESULT: FAIL")
    exit(1)
} else {
    print("RESULT: PASS")
    exit(0)
}
