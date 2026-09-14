import SwiftUI

/// The main window content: live header ticker, add row, search, and task list.
struct ContentView: View {
    @StateObject private var vm = TrackerViewModel()
    @State private var newTaskTitle: String = ""

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
