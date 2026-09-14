import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The main window content: live header ticker, add row, search, and task list.
struct ContentView: View {
    @StateObject private var vm = TrackerViewModel()
    @State private var newTaskTitle: String = ""
    @State private var showExportAlert = false
    @State private var exportAlertMessage = "Export failed."

    private var isSearching: Bool {
        !vm.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            addRow
            Divider()
            searchRow
            Divider()
            taskList
        }
        .padding(14)
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 480,
               minHeight: 380, idealHeight: 520)
        .alert("Export failed", isPresented: $showExportAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportAlertMessage)
        }
        .alert(
            "Delete task?",
            isPresented: Binding(
                get: { vm.pendingDelete != nil },
                set: { if !$0 { vm.pendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { vm.pendingDelete = nil }
            Button("Delete", role: .destructive) { vm.confirmDelete() }
        } message: {
            if let entry = vm.pendingDelete {
                Text("\"\(entry.title)\" and its tracked time will be permanently deleted.")
            }
        }
    }

    // MARK: - Header (live ticker)

    @ViewBuilder
    private var header: some View {
        if let running = vm.runningEntry {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(running.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                Text(TimeFormat.string(vm.elapsed(for: running)))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text("Nothing is running")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Add row

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("New task…", text: $newTaskTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit(start: false) }

            Button("Add") { submit(start: false) }
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)

            Button("Add & Start") { submit(start: true) }
                .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func submit(start: Bool) {
        vm.addTask(newTaskTitle, start: start)
        newTaskTitle = ""
    }

    /// Export all tracked tasks to a CSV file chosen by the user.
    private func exportCSV() {
        let entries = vm.entries
        guard !entries.isEmpty else { return }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "time-tracker.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let csv = CSVExporter.entriesToCSV(entries, now: Date())
            try Data(csv.utf8).write(to: url, options: .atomic)
        } catch {
            exportAlertMessage = error.localizedDescription
            showExportAlert = true
        }
    }

    // MARK: - Search row

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search all tasks", text: $vm.searchText)
                .textFieldStyle(.plain)
            if isSearching {
                Button {
                    vm.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
            Spacer()
            Button("Export") { exportCSV() }
                .help("Export all tasks to CSV")
                .disabled(vm.entries.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Task list

    private var taskList: some View {
        List {
            if vm.visible.isEmpty {
                emptyState
            } else {
                ForEach(vm.visible) { entry in
                    TaskRow(vm: vm, entry: entry)
                }
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: isSearching ? "magnifyingglass" : "clock")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(isSearching
                 ? "No tasks match your search."
                 : "Add a task above to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
