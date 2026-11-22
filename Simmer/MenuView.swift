import ServiceManagement
import SwiftUI

/// What opens when the menu bar icon is clicked.
struct MenuView: View {
    @Environment(SimulatorMonitor.self) private var monitor
    @Environment(Updater.self) private var updater
    @State private var opensAtLogin = SMAppService.mainApp.status == .enabled
    /// Whether simulators have been listed since the menu was opened. When
    /// the last one goes, the gem is shown dimming rather than already dim.
    @State private var sawSimulators = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if monitor.simulators.isEmpty {
                EmptyState(detail: emptyDetail, justEmptied: sawSimulators)
            } else {
                header
                Divider()
                VStack(spacing: 0) {
                    ForEach(monitor.simulators) { simulator in
                        SimulatorRow(simulator: simulator)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            footer
        }
        .frame(width: 350)
        // Rows slide away as their simulators stop, instead of vanishing.
        .animation(.snappy(duration: 0.3), value: monitor.simulators)
        .onChange(of: monitor.simulators.isEmpty) { _, isEmpty in
            if !isEmpty { sawSimulators = true }
        }
        .task {
            // Runs only while the menu is open.
            monitor.refresh()
            sawSimulators = !monitor.simulators.isEmpty
            while !Task.isCancelled {
                monitor.refresh()
                monitor.loadMemory()
                monitor.loadPreviews()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var header: some View {
        HStack {
            Text(title).font(.headline)
            if monitor.memoryInUse > 0 {
                Text(Self.memory(monitor.memoryInUse))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Using \(Self.memory(monitor.memoryInUse)) of memory")
            }
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

    /// "3.1 GB", or "640 MB" below a gigabyte.
    static func memory(_ bytes: UInt64) -> String {
        let megabytes = Double(bytes) / 1_048_576
        if megabytes < 1024 { return "\(Int(megabytes.rounded())) MB" }
        return String(format: "%.1f GB", megabytes / 1024)
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
            Text("Simmer \(Self.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let version = updater.availableVersion {
                Button("Update to \(version)") { updater.checkForUpdates() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
            }
            Menu {
                Toggle("Open at Login", isOn: Binding(
                    get: { opensAtLogin },
                    set: { setOpensAtLogin($0) }
                ))
                Toggle("Notify When Simulators Start", isOn: Binding(
                    get: { monitor.notifiesWhenStarted },
                    set: { monitor.setNotifiesWhenStarted($0) }
                ))
                Toggle("Notify About Forgotten Simulators", isOn: Binding(
                    get: { monitor.notifiesWhenForgotten },
                    set: { monitor.setNotifiesWhenForgotten($0) }
                ))
                Divider()
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.isEnabled)
                Button("About Simmer") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
                Divider()
                Button("Quit Simmer") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .accessibilityLabel("Settings")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // Keeps Command-Q working while the gear menu is closed.
        .background {
            Button("Quit Simmer") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

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

/// The gem, unlit, laid out like one of the simulator rows.
private struct EmptyState: View {
    let detail: String
    /// The last simulator has only just shut down, so the gem starts lit
    /// and dims while the words settle in.
    let justEmptied: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLit: Bool
    @State private var isSettled: Bool

    init(detail: String, justEmptied: Bool) {
        self.detail = detail
        self.justEmptied = justEmptied
        _isLit = State(initialValue: justEmptied)
        _isSettled = State(initialValue: !justEmptied)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                GemOutline()
                    .stroke(.tertiary, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                GemFacets()
                    .opacity(isLit ? 1 : 0)
                    .shadow(color: .green.opacity(isLit ? 0.55 : 0), radius: 6)
            }
            .frame(width: 22, height: 36)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing running")
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(isSettled ? 1 : 0)
            .offset(y: isSettled ? 0 : 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .onAppear {
            guard isLit else { return }
            if reduceMotion {
                isLit = false
                isSettled = true
            } else {
                withAnimation(.easeOut(duration: 0.35).delay(0.15)) { isSettled = true }
                withAnimation(.easeInOut(duration: 0.9).delay(0.4)) { isLit = false }
            }
        }
    }
}

private struct SimulatorRow: View {
    @Environment(SimulatorMonitor.self) private var monitor
    let simulator: Simulator

    private var isShuttingDown: Bool { monitor.shuttingDown.contains(simulator.id) }

    var body: some View {
        HStack(spacing: 12) {
            preview
                .opacity(isShuttingDown ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(simulator.name)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !simulator.runtime.isEmpty || simulator.origin != nil {
                    HStack(spacing: 5) {
                        if !simulator.runtime.isEmpty {
                            Text(simulator.runtime)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let origin = simulator.origin {
                            originChip(origin)
                        }
                    }
                }
                HStack(spacing: 5) {
                    timePill
                    if let bytes = monitor.memory[simulator.id], bytes > 0 {
                        memoryPill(bytes)
                    }
                }
            }
            .opacity(isShuttingDown ? 0.5 : 1)
            // Takes the room it needs before the spacer gets any.
            .layoutPriority(1)
            Spacer(minLength: 4)
            if isShuttingDown {
                Text("Shutting down…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Shut Down") { monitor.shutDown(simulator) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .animation(.default, value: isShuttingDown)
    }

    /// Marks the simulators Xcode started on its own, the easiest to forget.
    private func originChip(_ origin: String) -> some View {
        Text(origin)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.tertiary, lineWidth: 1))
    }

    /// The memory held by everything running inside this simulator.
    private func memoryPill(_ bytes: UInt64) -> some View {
        Text(MenuView.memory(bytes))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .accessibilityLabel("Using \(MenuView.memory(bytes)) of memory")
    }

    /// How long it has been running. Plain while fresh, then filled with
    /// the mood's color, so the warning doesn't rest on text color alone.
    private var timePill: some View {
        let time = Self.runningTime(from: simulator.bootedAt, to: monitor.now)
        let mood = monitor.mood(of: simulator)
        return Text(time)
            .font(.caption.weight(mood == .fresh ? .regular : .semibold))
            // Yellow text is unreadable on a light menu, so that step
            // keeps the regular text color over a yellow fill.
            .foregroundStyle(mood == .fresh ? AnyShapeStyle(.secondary)
                             : mood == .lingering ? AnyShapeStyle(.primary) : AnyShapeStyle(mood.color))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(mood == .fresh ? Color.primary.opacity(0.07)
                                       : mood.color.opacity(mood == .lingering ? 0.35 : 0.18)))
            .accessibilityLabel(time == "Just started" ? time : "Running for \(time), \(mood.spoken)")
    }

    @ViewBuilder
    private var preview: some View {
        Group {
            if let image = monitor.previews[simulator.id] {
                DeviceFrame(screen: image, kind: simulator.kind)
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
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }
}
