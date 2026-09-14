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
        WindowGroup("Time Tracker") {
            ContentView(vm: vm)
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

        MenuBarExtra {
            MenuBarContent(vm: vm)
        } label: {
            Image(systemName: menuBarIconName)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIconName: String {
        vm.runningEntry != nil ? "stop.circle.fill" : "clock"
    }
}

/// The menu-bar popover: shows the running task (if any) and quick controls.
struct MenuBarContent: View {
    @ObservedObject var vm: TrackerViewModel

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
                    vm.toggle(running)
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label("Nothing is running", systemImage: "clock")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                openMainWindow()
            } label: {
                Label("Open Time Tracker", systemImage: "window")
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

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
