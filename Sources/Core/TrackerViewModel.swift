import Foundation
import Combine

#if canImport(TimeTrackerCore)
import TimeTrackerCore
#endif

/// Bridges the pure `TimeTrackerEngine` to SwiftUI.
///
/// Exposes the engine's state as `@Published` properties and runs a 1-second
/// ticker that re-publishes `entries` so the live elapsed-time labels update
/// without each row needing its own timer.
///
/// The view model is deliberately independent of AppKit/SwiftUI so the same
/// type can be exercised by the headless test harness. It takes a `Clock`
/// (defaulting to the wall clock) so elapsed time and the break-reminder
/// decision are deterministic under test. The one platform hook (posting a
/// system notification) is injected as a closure by the app layer, keeping
/// this file UI-framework-free.
@MainActor
public final class TrackerViewModel: ObservableObject {
    @Published public var entries: [TimeEntry]
    @Published public var searchText: String = ""
    @Published public var toastMessage: String = ""
    @Published public var showToast: Bool = false
    @Published public var pendingDelete: TimeEntry?
    /// User preferences (toast on/off, hourly reminder on/off), persisted.
    @Published public var settings: AppSettings

    private let engine: TimeTrackerEngine
    private let store: EntryStore
    private let settingsStore: SettingsStore
    private let clock: Clock
    private var timer: Timer?
    private var toastResetTask: Task<Void, Never>?
    /// Last hour bucket checked for the break reminder (`nil` = not armed).
    private var reminderLastBucket: Date?

    /// Injected by the app layer: posts the break-reminder notification.
    /// Defaults to a no-op so the type works in the headless test harness.
    public var postReminder: ((String) -> Void)?
    /// Injected by the app layer: requests notification authorization.
    public var requestAuthorization: (() -> Void)?

    public init(
        engine: TimeTrackerEngine = TimeTrackerEngine(),
        store: EntryStore? = nil,
        settingsStore: SettingsStore = SettingsStore(),
        clock: Clock = SystemClock()
    ) {
        self.engine = engine
        // Default the store to one bound to the same engine, so the common
        // `TrackerViewModel()` call works without wiring the store by hand.
        self.store = store ?? EntryStore(engine: engine)
        self.settingsStore = settingsStore
        self.clock = clock
        self.entries = engine.entries
        self.settings = settingsStore.load()
    }

    // MARK: - Ticker

    public func startTicker() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    public func stopTicker() {
        timer?.invalidate()
        timer = nil
    }

    /// One tick: refresh published state and fire the break reminder if due.
    /// Exposed so the test harness can drive it deterministically.
    public func tick() {
        entries = engine.entries
        maybeFireBreakReminder()
    }

    // MARK: - Break reminder

    /// While a task is running and the reminder is enabled, fire once per
    /// calendar hour. The decision is pure (see `BreakReminder`); this method
    /// only handles the side effect of posting.
    private func maybeFireBreakReminder() {
        let now = clock.now()
        guard settings.hourlyReminderEnabled, let running = engine.runningEntry else {
            reminderLastBucket = nil
            return
        }
        let bucket = BreakReminder.hourBucket(for: now)
        if let last = reminderLastBucket {
            guard bucket != last else { return }   // same hour: do nothing
            reminderLastBucket = bucket
            postReminder?(running.title)
        } else {
            reminderLastBucket = bucket            // first tick: arm, don't fire
        }
    }

    /// Called when the user enables the hourly reminder: ask for permission.
    public func enableHourlyReminder() {
        guard settings.hourlyReminderEnabled == false else { return }
        settings.hourlyReminderEnabled = true
        settingsStore.save(settings)
        requestAuthorization?()
    }

    // MARK: - Settings

    /// Toggle the in-app toast notifications setting.
    public func setToastEnabled(_ enabled: Bool) {
        guard settings.toastEnabled != enabled else { return }
        settings.toastEnabled = enabled
        settingsStore.save(settings)
    }

    /// Toggle the hourly break reminder setting (no authorization side effect).
    public func setHourlyReminderEnabled(_ enabled: Bool) {
        guard settings.hourlyReminderEnabled != enabled else { return }
        settings.hourlyReminderEnabled = enabled
        if !enabled { reminderLastBucket = nil }
        settingsStore.save(settings)
    }

    // MARK: - Commands

    public var runningEntry: TimeEntry? { engine.runningEntry }
    public var runningID: UUID? { engine.runningID }
    public var mostRecent: TimeEntry? { engine.recent.first }

    public var visible: [TimeEntry] {
        engine.search(searchText, now: clock.now())
    }

    public func elapsed(for entry: TimeEntry) -> TimeInterval {
        engine.elapsed(for: entry, at: clock.now())
    }

    public func isRunning(_ entry: TimeEntry) -> Bool {
        entry.runningSince != nil
    }

    public func addTask(_ title: String, start: Bool) {
        engine.add(title: title, start: start)
        entries = engine.entries
        store.scheduleSave()
    }

    public func start(_ entry: TimeEntry) {
        engine.start(id: entry.id)
        entries = engine.entries
        store.scheduleSave()
    }

    public func stop(_ entry: TimeEntry) {
        engine.stop(id: entry.id)
        entries = engine.entries
        store.scheduleSave()
    }

    public func toggle(_ entry: TimeEntry) {
        engine.toggle(id: entry.id)
        entries = engine.entries
        store.scheduleSave()
    }

    public func delete(_ entry: TimeEntry) {
        pendingDelete = entry
    }

    public func confirmDelete() {
        guard let entry = pendingDelete else { return }
        engine.delete(id: entry.id)
        pendingDelete = nil
        entries = engine.entries
        store.scheduleSave()
        showToast("Deleted \"\(entry.title)\"")
    }

    public func updateNotesTags(_ entry: TimeEntry, notes: String, tags: [String]) {
        engine.update(id: entry.id, notes: notes, tags: tags)
        entries = engine.entries
        store.scheduleSave()
    }

    // MARK: - Toast

    /// Show a transient toast, gated by the toast-enabled setting.
    public func showToast(_ message: String) {
        guard settings.toastEnabled else { return }
        toastMessage = message
        showToast = true
        toastResetTask?.cancel()
        toastResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5s
            guard !Task.isCancelled else { return }
            self?.showToast = false
        }
    }
}
