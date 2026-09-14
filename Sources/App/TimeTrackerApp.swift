import SwiftUI
import AppKit

#if canImport(TimeTrackerCore)
import TimeTrackerCore
#endif

@main
struct TimeTrackerApp: App {
    /// Single shared view model so the main window and the menu-bar item always
    /// agree on state.
    @StateObject private var vm = TrackerViewModel()

    var body: some Scene {
        // Give the main window a stable id so the menu bar can open it
        // reliably via the `openWindow` action (see `MenuBarContent`).
        // The window title bar shows the app name ("Time Tracker") by default.
        WindowGroup(id: "main") {
            ContentView(vm: vm)
                .onAppear { configureNotifications(vm) }
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Quit Time Tracker") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }

        // The Settings window (Notifications section). Opened from the app
        // menu (Cmd+,) or the "Settings…" buttons in the UI.
        Settings {
            SettingsView(vm: vm)
                .onAppear { configureNotifications(vm) }
        }

        MenuBarExtra {
            MenuBarContent(vm: vm)
                .onAppear { configureNotifications(vm) }
        } label: {
            Image(systemName: menuBarIconName)
        }
        .menuBarExtraStyle(.window)
    }

    /// Wire the platform notification hooks into the view model. Idempotent,
    /// so it is safe to call from every surface's `onAppear`.
    @MainActor
    private func configureNotifications(_ vm: TrackerViewModel) {
        vm.postReminder = { title in AppNotifications.postBreakReminder(taskTitle: title) }
        vm.requestAuthorization = { AppNotifications.requestAuthorization() }
    }

    private var menuBarIconName: String {
        vm.runningEntry != nil ? "stop.circle.fill" : "clock"
    }
}

/// The menu-bar popover: shows the running task (if any) and quick controls.
struct MenuBarContent: View {
    @ObservedObject var vm: TrackerViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let running = vm.runningEntry {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(running.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(TimeFormat.string(vm.elapsed(for: running)))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Button {
                    vm.stop(running)
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else if let recent = vm.mostRecent {
                HStack(spacing: 8) {
                    Text(recent.title)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(TimeFormat.string(vm.elapsed(for: recent)))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Button {
                    vm.start(recent)
                } label: {
                    Label("Start", systemImage: "play.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label("No tasks yet", systemImage: "clock")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Divider()

            Button {
                // Bring the app forward, then open exactly the main window by
                // id. (We deliberately do NOT iterate `NSApp.windows` to force
                // windows to the front — that also surfaced the hidden Help
                // window, which is what produced the unclosable "no help" panel.)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Label("Open Time Tracker", systemImage: "window")
            }
            .buttonStyle(.plain)

            Button {
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 240)
    }

    /// Open the Settings window (the `Settings` scene). Works regardless of
    /// which window is frontmost.
    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
