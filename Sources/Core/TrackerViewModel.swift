import SwiftUI
import Combine

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
    private var ticker: AnyCancellable?

    public init() {
        let engine = TimeTrackerEngine()
        self.engine = engine
        self.store = EntryStore(engine: engine)
        store.load()
        startTicking()
    }

    // MARK: - Derived state

    public var runningID: UUID? { engine.runningID }
    public var runningEntry: TimeEntry? { engine.runningEntry }
    public var recent: [TimeEntry] { engine.recent }

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

    public func stop(_ entry: TimeEntry) {
        engine.stop(id: entry.id)
        afterMutation()
    }

    public func delete(_ entry: TimeEntry) {
        engine.delete(id: entry.id)
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

    deinit {
        ticker?.cancel()
        store.saveNow()
    }
}
