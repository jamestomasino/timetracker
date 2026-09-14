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
