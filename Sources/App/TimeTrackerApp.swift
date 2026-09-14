import SwiftUI

@main
struct TimeTrackerApp: App {
    var body: some Scene {
        WindowGroup("Time Tracker") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.automatic)
        .windowToolbarStyle(.automatic)
    }
}
