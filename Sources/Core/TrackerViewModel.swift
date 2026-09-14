import SwiftUI
import Combine
import AppKit

/// Bridges the pure engine to SwiftUI.
///
/// - Owns the `TimeTrackerEngine` and `EntryStore`.
/// - Runs a 1-second ticker that triggers UI updates while a task is running.
/// - Exposes the search text and the derived "recent"/"filtered" lists.
@MainActor
public final class TrackerViewModel: ObservableObject {
    private let engine: TimeTrackerEngine
    private let store: EntryStore

    @Published public var searchText: String = ""
    /// Bumped every tick so the elapsed-time views re-render.
    @Published public private(set) var tick: Int = 0
    /// Set when the user taps delete; the view shows a confirmation and, on
    /// confirm, calls `confirmDelete()`. Deleting also erases the task's tracked
    /// time, so we never do it in one irreversible tap.
    @Published public var pendingDelete: TimeEntry?
    private var ticker: AnyCancellable?
    private var terminateObserver: NSObjectProtocol?

    public init() {
        let engine = TimeTrackerEngine()
        self.engine = engine
        self.store = EntryStore(engine: engine)
        store.load()
        startTicking()
        registerTerminateHook()
    }

    // MARK: - Derived state

    public var runningID: UUID? { engine.runningID }
    public var runningEntry: TimeEntry? { engine.runningEntry }
    public var recent: [TimeEntry] { engine.recent }
    /// The most recently active task (running pinned to top). Used by the menu
    /// bar to offer a quick start when nothing is running.
    public var mostRecent: TimeEntry? { recent.first }
    /// All entries, in the engine's natural (insertion) order.
    public var entries: [TimeEntry] { engine.entries }

    /// The list to display: search results if searching, else the recent list.
    public var visible: [TimeEntry] {
        engine.search(searchText)
    }

    public func elapsed(for entry: TimeEntry) -> TimeInterval {
        engine.elapsed(for: entry, at: Date())
    }

    public func isRunning(_ entry: TimeEntry) -> Bool {
        entry.runningSince != nil
    }

    // MARK: - Intents

    public func addTask(_ title: String, start: Bool) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        engine.add(title: trimmed, start: start)
        afterMutation()
    }

    public func toggle(_ entry: TimeEntry) {
        engine.toggle(id: entry.id)
        afterMutation()
    }

    /// Start a task (auto-stops whatever is running).
    public func start(_ entry: TimeEntry) {
        engine.start(id: entry.id)
        afterMutation()
    }

    public func stop(_ entry: TimeEntry) {
        engine.stop(id: entry.id)
        afterMutation()
    }

    /// Set a task's notes and/or tags from the editor.
    public func updateNotesTags(_ entry: TimeEntry, notes: String, tags: [String]) {
        engine.update(id: entry.id, notes: notes, tags: tags)
        afterMutation()
    }

    public func delete(_ entry: TimeEntry) {
        pendingDelete = entry
    }

    /// Actually delete the task the user confirmed. Idempotent if the entry is
    /// already gone (e.g. a stale pending value from a prior render).
    public func confirmDelete() {
        guard let entry = pendingDelete, engine.entry(id: entry.id) != nil else {
            pendingDelete = nil
            return
        }
        engine.delete(id: entry.id)
        pendingDelete = nil
        afterMutation()
    }

    // MARK: - Ticking

    private func startTicking() {
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                // Only bump when something is actually running to avoid needless work.
                if self.engine.runningID != nil {
                    self.tick &+= 1
                }
            }
    }

    private func afterMutation() {
        tick &+= 1
        store.scheduleSave()
    }

    /// Flush pending state synchronously when the app is about to quit, so we
    /// never lose tracked time to the save debounce window. `deinit` remains a
    /// fallback, but `willTerminate` is the reliable hook.
    private func registerTerminateHook() {
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.store.saveNow()
        }
    }

    deinit {
        if let observer = terminateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        ticker?.cancel()
        store.saveNow()
    }
}
