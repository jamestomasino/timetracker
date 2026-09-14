import SwiftUI

#if canImport(TimeTrackerCore)
import TimeTrackerCore
#endif

/// The Settings window. Currently a single "Notifications" section; the
/// structure is a list of sections so future settings can be added without
/// reshaping the window.
struct SettingsView: View {
    @ObservedObject var vm: TrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section: Notifications
            sectionHeader("Notifications")
            VStack(alignment: .leading, spacing: 0) {
                row(
                    title: "Toast notifications",
                    subtitle: "Show brief in-app confirmations for actions like deleting a task or exporting."
                ) {
                    Toggle("", isOn: Binding(
                        get: { vm.settings.toastEnabled },
                        set: { vm.setToastEnabled($0) }
                    ))
                    .labelsHidden()
                }

                Divider().padding(.vertical, 8)

                row(
                    title: "Hourly break reminder",
                    subtitle: "While a task is running, get a notification at the top of each hour to take a break."
                ) {
                    Toggle("", isOn: Binding(
                        get: { vm.settings.hourlyReminderEnabled },
                        set: { vm.setHourlyReminderEnabled($0) }
                    ))
                    .labelsHidden()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A section title row.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    /// A settings row: title + subtitle on the left, control on the right.
    private func row(
        title: String,
        subtitle: String,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, 6)
    }
}
