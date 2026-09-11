import SwiftUI

/// Content of the menu bar popover.
struct UsageView: View {
    let store: UsageStore
    let monitor: IntegrationMonitor
    var onOpenSettings: @MainActor () -> Void
    var onQuit: @MainActor () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content(now: context.date)
        }
        .frame(width: 320)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Claude Usage")
                    .font(.headline)
                Spacer()
                if let snapshot = store.snapshot {
                    Text("Updated \(Formatting.updatedAgo(snapshot.receivedAt, now: now))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let snapshot = store.snapshot {
                if snapshot.hasRateLimits {
                    WindowRow(
                        title: "5-hour window",
                        state: WindowState(window: snapshot.fiveHour, hasRateLimits: true, now: now),
                        now: now,
                        resetStyle: .clock
                    )
                    WindowRow(
                        title: "Weekly window",
                        state: WindowState(window: snapshot.sevenDay, hasRateLimits: true, now: now),
                        now: now,
                        resetStyle: .weekday
                    )
                } else {
                    Notice(
                        symbol: "questionmark.circle",
                        title: "No rate limits reported",
                        detail: "Claude Code only reports usage limits for Pro and Max subscriptions, and only after the first response of a session."
                    )
                }
            } else {
                EmptyStateView(status: monitor.status, onOpenSettings: onOpenSettings)
            }

            Divider()

            HStack {
                Button("Settings…", action: onOpenSettings)
                Spacer()
                Button("Quit", action: onQuit)
            }
            .controlSize(.regular)
        }
        .padding(16)
    }
}

// MARK: - Rows

struct WindowRow: View {
    enum ResetStyle { case clock, weekday }

    let title: String
    let state: WindowState
    let now: Date
    let resetStyle: ResetStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(Formatting.percent(state.percentage))
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                    .foregroundStyle(state.percentage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
            UsageBar(fraction: (state.percentage ?? 0) / 100, color: UsageColor.color(for: state.percentage))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        switch state {
        case .active(let window):
            "Resets in \(Formatting.countdown(to: window.resetsAt, from: now)) · \(time(window.resetsAt))"
        case .reset(let date):
            "Reset at \(time(date)) · 0% until your next message"
        case .idle:
            "No active window · starts with your next message"
        case .unavailable:
            "Not reported by Claude Code"
        }
    }

    private func time(_ date: Date) -> String {
        switch resetStyle {
        case .clock: Formatting.clockTime(date)
        case .weekday: Formatting.weekdayTime(date)
        }
    }
}

struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: fraction > 0 ? max(6, geometry.size.width * min(fraction, 1)) : 0)
            }
        }
        .frame(height: 6)
    }
}

enum UsageColor {
    static func color(for percentage: Double?) -> Color {
        guard let percentage else { return .secondary }
        if percentage >= 80 { return .red }
        if percentage >= 50 { return .orange }
        return .green
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let status: ClaudeCodeIntegration.Status
    var onOpenSettings: @MainActor () -> Void

    var body: some View {
        switch status {
        case .configured:
            Notice(
                symbol: "checkmark.circle.fill",
                symbolColor: .green,
                title: "Connected to Claude Code",
                detail: "Waiting for data. Usage appears after the first response in a Claude Code session."
            )
        case .notConfigured:
            VStack(alignment: .leading, spacing: 10) {
                Notice(
                    symbol: "link.circle",
                    title: "Not connected to Claude Code yet",
                    detail: "CapTrack reads the usage data Claude Code hands to its status line. This is a one-time setup."
                )
                Button("Set Up in Settings…", action: onOpenSettings)
            }
        case .claudeCodeNotFound:
            Notice(
                symbol: "exclamationmark.triangle",
                title: "Claude Code not found",
                detail: "No ~/.claude directory. Install Claude Code and sign in with a Pro or Max subscription."
            )
        case .unreadable(let message):
            Notice(
                symbol: "exclamationmark.triangle",
                title: "Could not read Claude Code settings",
                detail: message
            )
        }
    }
}

struct Notice: View {
    let symbol: String
    var symbolColor: Color = .secondary
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(symbolColor)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
