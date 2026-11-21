import ServiceManagement
import SwiftUI

/// What opens when the menu bar icon is clicked.
struct MenuView: View {
    @Environment(SimulatorMonitor.self) private var monitor
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if monitor.simulators.isEmpty {
                emptyState
            } else {
                header
                Divider()
                VStack(spacing: 0) {
                    ForEach(monitor.simulators) { simulator in
                        SimulatorRow(simulator: simulator)
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
        .frame(width: 350)
        .task {
            // Runs only while the menu is open.
            while !Task.isCancelled {
                monitor.refresh()
                monitor.loadPreviews()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var header: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if monitor.simulators.count > 1 {
                Button("Shut Down All") { monitor.shutDownAll() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var title: String {
        monitor.simulators.count == 1 ? "1 simulator running" : "\(monitor.simulators.count) simulators running"
    }

    /// The gem, unlit, laid out like one of the simulator rows.
    private var emptyState: some View {
        HStack(spacing: 12) {
            GemOutline()
                .stroke(.tertiary, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .frame(width: 22, height: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing running")
                    .font(.body.weight(.medium))
                Text(emptyDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
    }

    private var emptyDetail: String {
        guard let last = monitor.lastShutDown else { return "Simulators you start will show up here." }
        return "Last shut down: \(last.name), \(Self.timeAgo(from: last.date, to: monitor.now))"
    }

    static func timeAgo(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start)) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }
        let hours = minutes / 60
        if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
        let days = hours / 24
        return days == 1 ? "yesterday" : "\(days) days ago"
    }

    private var footer: some View {
        HStack {
            Toggle("Open at Login", isOn: Binding(
                get: { opensAtLogin },
                set: { setOpensAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Simmer couldn't change the login item: \(error.localizedDescription)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct SimulatorRow: View {
    @Environment(SimulatorMonitor.self) private var monitor
    let simulator: Simulator

    private var isShuttingDown: Bool { monitor.shuttingDown.contains(simulator.id) }

    var body: some View {
        HStack(spacing: 12) {
            preview
            VStack(alignment: .leading, spacing: 2) {
                Text(simulator.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(Self.runningTime(from: simulator.bootedAt, to: monitor.now))
                    .font(.caption)
                    .foregroundStyle(isLongRunning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 4)
            if isShuttingDown {
                ProgressView().controlSize(.small)
            } else {
                Button("Shut Down") { monitor.shutDown(simulator) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .opacity(isShuttingDown ? 0.5 : 1)
    }

    private var subtitle: String {
        [simulator.runtime, simulator.origin ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var isLongRunning: Bool { monitor.isForgotten(simulator) }

    @ViewBuilder
    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Group {
            if let image = monitor.previews[simulator.id] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.primary.opacity(0.2), lineWidth: 1))
            } else {
                Image(systemName: simulator.kind.symbol)
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 84)
        .accessibilityHidden(true)
    }

    static func runningTime(from start: Date, to end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start)) / 60)
        if minutes < 1 { return "Just started" }
        if minutes < 60 { return "Running for \(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "Running for \(hours)h \(minutes % 60)m" }
        return "Running for \(hours / 24)d \(hours % 24)h"
    }
}
