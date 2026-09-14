import Foundation

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
check(stoppedRow.last == "Stopped", "stopped status")
check(stoppedRow[3] == "120", "stopped duration = accumulated (got \(stoppedRow[3]))")

let runningRow = csvLines[2].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
check(runningRow.last == "Running", "running status")
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
