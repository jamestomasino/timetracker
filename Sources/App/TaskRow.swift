import SwiftUI

#if canImport(TimeTrackerCore)
import TimeTrackerCore
#endif

/// A single task row: title + tags + notes on the left, controls on the right.
struct TaskRow: View {
    @ObservedObject var vm: TrackerViewModel
    let entry: TimeEntry
    @State private var showEditor = false

    private var running: Bool { vm.isRunning(entry) }
    private var elapsed: String { TimeFormat.string(vm.elapsed(for: entry)) }
    private var hasNotes: Bool { !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            // Status dot: green when running, gray when stopped.
            Circle()
                .fill(running ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)

            // Title + tags + notes
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.body)
                        .lineLimit(1)
                    if running {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    if !entry.tags.isEmpty {
                        tagChips
                    }
                }
                if hasNotes {
                    Text(entry.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            // Elapsed time (monospaced so it doesn't jiggle while ticking)
            Text(elapsed)
                .font(.body.monospacedDigit())
                .foregroundStyle(running ? .primary : .secondary)
                .frame(minWidth: 44, alignment: .trailing)

            // Controls
            controls
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .popover(isPresented: $showEditor, arrowEdge: .trailing) {
            EntryEditor(vm: vm, entry: entry)
        }
    }

    @ViewBuilder
    private var tagChips: some View {
        ForEach(entry.tags.prefix(3), id: \.self) { tag in
            Text("#\(tag)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 6) {
            Button {
                vm.toggle(entry)
            } label: {
                Image(systemName: running ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(running ? .red : .accentColor)
            }
            .buttonStyle(.plain)
            .help(running ? "Stop" : "Start")

            Button {
                showEditor = true
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit notes & tags")

            Button {
                vm.delete(entry)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
    }
}

/// A small editor for a task's notes and tags, shown in a popover.
struct EntryEditor: View {
    @ObservedObject var vm: TrackerViewModel
    let entry: TimeEntry
    @State private var notes: String
    @State private var tagsText: String
    @Environment(\.dismiss) private var dismiss

    init(vm: TrackerViewModel, entry: TimeEntry) {
        self.vm = vm
        self.entry = entry
        _notes = State(initialValue: entry.notes)
        _tagsText = State(initialValue: entry.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Add a note…", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("work, design, urgent", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func save() {
        vm.updateNotesTags(entry, notes: notes, tags: parseTags(tagsText))
        dismiss()
    }
}
