# Time Tracker

A small native macOS time tracker. Add a task, start it, and watch the clock tick.
Starting a new task automatically stops the one that's running. Your recent tasks
stay at the top, and you can search the full list by title, notes, or tag.

![MVP](https://img.shields.io/badge/status-MVP-blue)

## Features

- **Small window** with standard macOS UI components (SwiftUI).
- **Add a task** with a title, optionally **Add & Start** it immediately.
- **Start / Stop** any task with one click.
- **Auto-stop**: starting a new task stops the currently running one and folds its
  time in. Only one task runs at a time.
- **Live ticker**: the running task's elapsed time updates every second in the
  header and in the row.
- **Recent list**: the running task is pinned to the top; the rest are ordered by
  most-recently-active.
- **Search**: a search box filters the full list by (case-insensitive) substring of
  title, notes, or any tag.
- **Notes & tags**: add free-form notes and comma/semicolon-separated tags to any
  task via the pencil button. Tags render as `#chips` and are searchable.
- **Menu bar**: a live popover with the running task's timer, a Stop button, and a
  shortcut to open the window. The icon shows a filled stop-circle when something is
  running.
- **Persistence**: tasks and their times survive app restarts (saved to
  `~/Library/Application Support/TimeTracker/`), with automatic backup and
  corrupt-file recovery.
- **CSV export**: export all tasks (title, dates, duration, status, notes, tags) to
  a spreadsheet, with a success toast confirming the result.
- **Toasts as needed**: transient, non-blocking feedback exactly where the UI alone
  doesn't tell the story — deleting a task and finishing a CSV export. Add/start/stop
  and notes-save are intentionally silent because their result is already visible.
- **Safe delete**: deleting a task asks for confirmation first, since it also
  erases that task's tracked time.
- **Testable core**: the engine is deterministic (injectable clock) and covered by a
  lightweight test suite (131 checks).

## Requirements

- macOS 14+ (Sonoma or later).
- Swift 6 / the Xcode Command Line Tools. **Full Xcode is not required** — the
  app is built with `swiftc` directly (or SwiftPM).

## Build & run

```bash
bash build.sh          # compiles build/TimeTracker.app and ad-hoc signs it
open build/TimeTracker.app
```

To build the app **and** run the test suite:

```bash
bash build.sh test
```

### SwiftPM (optional)

The project is also a valid SwiftPM package, so you can build and test without
`build.sh`:

```bash
swift build                 # builds the TimeTracker executable
swift run TimeTrackerTests  # runs the same assertion-based test suite
```

Both paths compile the exact same source files; `Package.swift` is additive and
does not change the `build.sh` flow.

The test suite (`Tests/main.swift`) is a self-contained assertion harness that
exercises the core engine (start/stop/auto-stop/toggle/ordering/search/notes &
tags/persistence/CSV) with a manually-advanced clock, so it's fast and
deterministic.

## Project layout

```
build.sh                      # swiftc-only build + test runner
Package.swift                 # additive SwiftPM manifest (Core lib + App + Tests)
Sources/
  Core/
    TimeEntry.swift           # model + parseTags + Clock abstraction
    TimeTrackerEngine.swift   # pure state machine (no UI, no I/O) — fully testable
    EntryStore.swift          # JSON persistence to Application Support
    TimeFormat.swift          # h:mm:ss / mm:ss formatting
    CSVExporter.swift         # RFC-4180 CSV serialization (notes + tags columns)
    TrackerViewModel.swift    # ObservableObject bridge + 1s ticker + notes/tags update
    ToastCenter.swift         # transient toast state + auto-dismiss timer (VM forwards its changes)
  App/
    TimeTrackerApp.swift      # @main, small window + MenuBarExtra
    ContentView.swift         # header, add row, search, list, export toast
    TaskRow.swift             # one task row: title, tags, notes, play/stop, edit, delete
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
- **Backward-compatible model.** `TimeEntry` decodes `notes` and `tags` with
  `decodeIfPresent`, so `entries.json` files written by older versions (without
  those keys) still load cleanly, defaulting to empty.
- **Menu bar lives in the App layer.** The `MenuBarExtra` shares the same
  `TrackerViewModel` as the window, so starting/stopping from the popover and the
  window stay in sync.
- **Toasts are a ViewModel concern, not a view concern.** `showToast(_:)` lives on
  `TrackerViewModel` (Core layer) so it's testable and shared by the window and the
  menu bar. It's used sparingly — only for actions whose result isn't already
  visible (delete, export) — and auto-dismisses after a fixed delay.

## Data location

`~/Library/Application Support/TimeTracker/entries.json`

A previous copy is kept alongside it as `entries.json.bak` (the last known-good
state before the most recent save). Delete both files to reset all tasks.

## CSV export format

The **Export** button (in the search row) opens a save panel defaulting to
`time-tracker.csv` and writes one row per task, in the app's natural order:

```
Title,Created At,Last Activity,Duration (s),Status,Notes,Tags
```

- **Title** — the task title, RFC-4180 quoted if it contains a comma, quote, or newline.
- **Created At / Last Activity** — ISO-8601 UTC timestamps (e.g. `2026-09-14T18:44:00.123Z`).
- **Duration (s)** — total tracked seconds. For a running task this is
  `accumulated + (now - runningSince)`; for a stopped task it is the accumulated time.
- **Status** — `Running` if the task is currently running, otherwise `Stopped`.
- **Notes** — the task's free-form notes, RFC-4180 quoted if needed.
- **Tags** — the task's tags joined with `"; "`.

The serialization lives in `Sources/Core/CSVExporter.swift` (pure, AppKit-free) and
is covered by the test suite's `csv export` and `csv notes/tags columns` sections.
