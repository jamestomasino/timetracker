# Time Tracker

A small native macOS time tracker. Add a task, start it, and watch the clock tick.
Starting a new task automatically stops the one that's running. Your recent tasks
stay at the top, and you can search the full list.

![MVP](https://img.shields.io/badge/status-MVP-blue)

## Features (MVP)

- **Small window** with standard macOS UI components (SwiftUI).
- **Add a task** with a title, optionally **Add & Start** it immediately.
- **Start / Stop** any task with one click.
- **Auto-stop**: starting a new task stops the currently running one and folds its
  time in. Only one task runs at a time.
- **Live ticker**: the running task's elapsed time updates every second in the
  header and in the row.
- **Recent list**: the running task is pinned to the top; the rest are ordered by
  most-recently-active.
- **Search**: a search box filters the full list by (case-insensitive) title
  substring.
- **Persistence**: tasks and their times are saved to disk and restored on launch
  (running tasks keep ticking across relaunches). Saves are debounced and
  durable: the previous file is kept as a `.bak` backup before each overwrite,
  and a corrupt primary file falls back to that backup instead of wiping history.
- **Safe delete**: deleting a task asks for confirmation first, since it also
  erases that task's tracked time.
- **Export to CSV**: the **Export** button writes all tracked tasks to a CSV file
  you choose (RFC-4180 escaped, so titles with commas, quotes, or new lines are safe).

## Requirements

- macOS 14+ (Sonoma or later).
- Swift 6 / the Xcode Command Line Tools. **Full Xcode is not required** — the
  app is built with `swiftc` directly.

## Build & run

```bash
bash build.sh          # compiles build/TimeTracker.app and ad-hoc signs it
open build/TimeTracker.app
```

To build the app **and** run the test suite:

```bash
bash build.sh test
```

The test suite (`Tests/main.swift`) is a self-contained assertion harness that
exercises the core engine (start/stop/auto-stop/toggle/ordering/search/persistence)
with a manually-advanced clock, so it's fast and deterministic.

## Project layout

```
build.sh                      # swiftc-only build + test runner
Sources/
  Core/
    TimeEntry.swift           # model + Clock abstraction (SystemClock / FixedClock)
    TimeTrackerEngine.swift   # pure state machine (no UI, no I/O) — fully testable
    EntryStore.swift          # JSON persistence to Application Support
    TimeFormat.swift          # h:mm:ss / mm:ss formatting
    TrackerViewModel.swift    # ObservableObject bridge + 1s ticker
  App/
    TimeTrackerApp.swift      # @main, small window
    ContentView.swift         # header, add row, search, list
    TaskRow.swift             # one task row: title, elapsed, play/stop, delete
Resources/                    # (reserved)
Tests/
  main.swift                  # assertion harness for the engine
```

## Design notes

- **Testable core.** `TimeTrackerEngine` is a pure state machine with an injected
  `Clock`. It has no dependency on SwiftUI, AppKit, or the file system, so the
  tricky logic (auto-stop, accumulation, ordering, search) is verified by fast,
  deterministic tests rather than by clicking around.
- **Elapsed time is derived, not stored.** A running task stores `runningSince`;
  elapsed = `accumulated + (now - runningSince)`. This means the timer stays
  correct even if the app is backgrounded or relaunched, and there's no drift
  from incrementing a counter.
- **Persistence is debounced** so the 1-second ticker doesn't hammer the disk.

## Data location

`~/Library/Application Support/TimeTracker/entries.json`

A previous copy is kept alongside it as `entries.json.bak` (the last known-good
state before the most recent save). Delete both files to reset all tasks.

## CSV export format

The **Export** button (in the search row) opens a save panel defaulting to
`time-tracker.csv` and writes one row per task, in the app's natural order:

```
Title,Created At,Last Activity,Duration (s),Status
```

- **Title** — the task title, RFC-4180 quoted if it contains a comma, quote, or newline.
- **Created At / Last Activity** — ISO-8601 UTC timestamps (e.g. `2026-09-14T18:44:00.123Z`).
- **Duration (s)** — total tracked seconds. For a running task this is
  `accumulated + (now - runningSince)`; for a stopped task it is the accumulated time.
- **Status** — `Running` if the task is currently running, otherwise `Stopped`.

The serialization lives in `Sources/Core/CSVExporter.swift` (pure, AppKit-free) and
is covered by the test suite's `csv export` section.

## Possible next steps

- Menu-bar / status-item mode.
- Per-task notes, tags, or projects.
- A proper `.xcodeproj` (e.g. via `swift package init`) if you want to open it in
  Xcode and use its test runner — the code is already structured for it.
