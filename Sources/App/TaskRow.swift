import SwiftUI

/// A single task row: title + elapsed time on the left, controls on the right.
struct TaskRow: View {
    @ObservedObject var vm: TrackerViewModel
    let entry: TimeEntry

    private var running: Bool { vm.isRunning(entry) }
    private var elapsed: String { TimeFormat.string(vm.elapsed(for: entry)) }

    var body: some View {
        HStack(spacing: 10) {
            // Status dot: green pulse when running, gray when stopped.
            Circle()
                .fill(running ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)

            // Title + running indicator
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.title)
                        .font(.body)
                        .lineLimit(1)
                    if running {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
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
