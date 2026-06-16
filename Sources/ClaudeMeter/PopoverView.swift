import SwiftUI

struct PopoverView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            limitTab
            Divider()
            HistoryView(state: state)
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 330)
        .onAppear { state.refreshOnOpen() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .foregroundStyle(.tint)
            Text("ClaudeMeter")
                .font(.headline)
            Spacer()
            Text("本地数据 · 不上传")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - 额度标签页

    @ViewBuilder
    private var limitTab: some View {
        switch state.snapshot.status {
        case .disabled:           enableAffordance
        case .waiting:            waitingAffordance
        case .noData:             noDataAffordance
        case .error(let msg):     errorContent(msg)
        case .ok:                 limitContent
        }
    }

    private var limitContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 18) {
                ProgressRing(fraction: (state.fiveHourPercent ?? 0) / 100)
                VStack(alignment: .leading, spacing: 10) {
                    metric(title: "5 小时窗口",
                           percent: state.fiveHourPercent,
                           reset: state.countdown(to: state.snapshot.fiveHour?.resetsAt))
                    metric(title: "本周(所有模型)",
                           percent: state.sevenDayPercent,
                           reset: state.countdown(to: state.snapshot.sevenDay?.resetsAt))
                }
                Spacer()
            }
            if state.snapshot.isStale {
                Label("数据可能已过期 · 打开 Claude Code 干活后会自动刷新",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func metric(title: String, percent: Double?, reset: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
                    .font(.title3.weight(.semibold)).monospacedDigit()
                Text("· \(reset) 后重置")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // 还没启用截获钩子
    private var enableAffordance: some View {
        VStack(spacing: 10) {
            Image(systemName: "powerplug").font(.title).foregroundStyle(.tint)
            Text("启用额度监测").font(.callout.weight(.medium))
            Text("会在 Claude Code 的状态栏命令上装一个透明钩子，截获额度数据。不联网、不读取 token，随时可关闭恢复。")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Button("启用") { state.captureEnabled = true }
                .controlSize(.small).buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
    }

    // 已启用但还没截到数据
    private var waitingAffordance: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("等待 Claude Code 渲染状态栏…").font(.callout)
            Text("在 Claude Code 里发一条消息触发状态栏刷新，这里就会出现数据。")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    private var noDataAffordance: some View {
        VStack(spacing: 6) {
            Image(systemName: "minus.circle").font(.title2).foregroundStyle(.secondary)
            Text("当前会话没有订阅额度数据").font(.callout)
            Text("（API/Bedrock 会话不返回额度窗口）")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title).foregroundStyle(.orange)
            Text(message).font(.callout).multilineTextAlignment(.center)
            Button("重试") { state.refreshAll() }.controlSize(.small)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack(spacing: 10) {
            Text("更新于 " + state.lastUpdated.formatted(date: .omitted, time: .standard))
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            if state.captureEnabled {
                Toggle(isOn: $state.showResetInStatusBar) {
                    Text("倒计时").font(.caption)
                }
                .toggleStyle(.switch).controlSize(.mini)
            }
            Button("刷新") { state.refreshAll() }
                .buttonStyle(.borderless).font(.caption)
            Button("退出") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless).font(.caption)
        }
    }
}
