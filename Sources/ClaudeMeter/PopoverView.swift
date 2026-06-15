import SwiftUI

struct PopoverView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            if let err = state.officialError, state.official == nil {
                errorContent(err)
            } else {
                officialContent
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 310)
        .onAppear { state.refreshOnOpen() }   // 打开面板刷新(带节流,防限流)
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .foregroundStyle(.tint)
            Text("Claude 用量")
                .font(.headline)
            Spacer()
            Text("账号级 · 含桌面端")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var officialContent: some View {
        HStack(alignment: .center, spacing: 18) {
            ProgressRing(fraction: (state.fiveHourPercent ?? 0) / 100)

            VStack(alignment: .leading, spacing: 10) {
                metric(
                    title: "5 小时窗口",
                    percent: state.fiveHourPercent,
                    reset: state.countdown(to: state.official?.fiveHour?.resetsAt)
                )
                metric(
                    title: "本周(所有模型)",
                    percent: state.sevenDayPercent,
                    reset: state.countdown(to: state.official?.sevenDay?.resetsAt)
                )
            }
            Spacer()
        }
    }

    private func metric(title: String, percent: Double?, reset: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Text("· \(reset) 后重置")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title).foregroundStyle(.orange)
            Text(message)
                .font(.callout).multilineTextAlignment(.center)
            Button("重试") { state.refreshAll() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            Text("更新于 " + state.lastUpdated.formatted(date: .omitted, time: .standard))
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Toggle(isOn: $state.showResetInStatusBar) {
                Text("显示倒计时").font(.caption)
            }
            .toggleStyle(.switch).controlSize(.mini)
            Button("刷新") { state.refreshAll() }
                .buttonStyle(.borderless).font(.caption)
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless).font(.caption)
        }
    }
}
