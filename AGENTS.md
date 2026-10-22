# AGENTS.md

Guidance for agents (and humans) working in this repo.

## Build — the one gotcha to know

- Build with `bash build.sh` (app) or `bash build.sh test` (app + test suite).
  Both use `swiftc` only; **full Xcode is not required and is not assumed.**
- If the build prints `external macro implementation type 'SwiftUIMacros.StateMacro'
  could not be found`, that is **expected on some machines, not a regression**.
  Recent Command Line Tools SDKs (e.g. 27.0) declare SwiftUI `@State`/`@Observable`
  as external macros backed by a `SwiftUIMacros` plugin that is not always
  installed. `build.sh` already detects this and falls back to an older installed
  SDK (e.g. 26.5) that compiles the same code. Do **not** "fix" this by removing
  the fallback, pinning the SDK, or rewriting the SwiftUI views.
- The test suite is a **custom assertion harness** (`Tests/main.swift`), not
  XCTest. `swift run TimeTrackerTests` (SwiftPM) runs the same harness.

## Hard constraints (do not regress)

- **CLT-only build must keep working.** The `swiftc` path is a stated requirement,
  not a convenience. Keep `build.sh` self-contained and Xcode-free.
- **Remove dead public APIs** rather than leaving them with a "maybe someone will
  use it" comment. If a `public` member is only exercised by a test that exists
  solely to keep it alive, delete both.
- **Keep the Core layer pure.** `TimeTrackerEngine` and the Core module avoid
  SwiftUI, AppKit, `UserNotifications`, and the file system so the tricky logic
  stays deterministic and testable. Platform detail (notifications, panels) stays
  in the App layer, behind injected closures.

## Conventions

- Persistence layers (`EntryStore`, `SettingsStore`) are small and swappable; the
  view model never touches the file system directly. `SettingsStore.inMemory()`
  exists so tests never read/write the user's real preferences — keep that seam.
- Prefer fixing problems over surfacing them; validate end-to-end (the app should
  actually launch and run, not just compile and pass tests).
