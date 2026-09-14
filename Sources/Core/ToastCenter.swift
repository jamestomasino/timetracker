import Foundation
import Combine

/// Owns the transient toast state and its auto-dismiss timer.
///
/// Extracted from `TrackerViewModel` so the view model stays focused on the
/// engine/store/settings plumbing. The view model forwards this object's
/// `objectWillChange` into its own, so SwiftUI views that observe the view
/// model still update when a toast shows or hides.
///
/// Deliberately framework-free (no SwiftUI/AppKit) so it lives in Core and is
/// testable headless, like the rest of the view model.
@MainActor
public final class ToastCenter: ObservableObject {
    /// How long a toast stays on screen before auto-hiding (2.5s).
    private static let dismissDelay: UInt64 = 2_500_000_000

    /// Whether a toast is currently visible.
    @Published public var visible: Bool = false
    /// The message in the current toast (empty when none).
    @Published public var message: String = ""

    private var resetTask: Task<Void, Never>?

    public init() {}

    /// Show `message` for the default duration, then auto-hide. Re-showing
    /// replaces the message and restarts the timer.
    public func show(_ message: String) {
        self.message = message
        visible = true
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.dismissDelay)
            guard !Task.isCancelled else { return }
            self?.visible = false
        }
    }
}
