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
final class ManualClock: Clock {
    var instant: Date
    init(instant: Date) { self.instant = instant }
    func now() -> Date { instant }
    func advance(_ s: TimeInterval) { instant = instant.addingTimeInterval(s) }
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

check(csvLines.first == CSVExporter.header, "header is first line")
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

check(CSVExporter.entriesToCSV([], now: csvNow) == CSVExporter.header + "\n",
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
