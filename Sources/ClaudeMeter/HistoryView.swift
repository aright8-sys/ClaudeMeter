import SwiftUI

/// "记账"：近 30 天本地用量（纯本地，不上传）。可在 Token / 金额(USD) 间切换。
struct HistoryView: View {
    @ObservedObject var state: AppState

    enum Mode { case token, money }
    @State private var mode: Mode = .token
    @State private var hoveredBar: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            head
            if state.history.isEmpty {
                emptyState
            } else {
                summary
                barChart
                modelBreakdown
            }
        }
    }

    private var head: some View {
        HStack {
            Text("近 30 天用量").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $mode) {
                Text("Token").tag(Mode.token)
                Text("金额").tag(Mode.money)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            if state.historyLoading {
                ProgressView().controlSize(.small)
                Text("正在扫描本地会话日志…").font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
                Text("近 30 天没有找到本地用量记录").font(.callout)
                Text("用 Claude Code 跑几轮对话后再回来看")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
    }

    // 顶部汇总数字
    private var summary: some View {
        let t = state.history.total
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if mode == .token {
                    Text(Format.compact(t.total)).font(.title2.weight(.semibold)).monospacedDigit()
                    Text("tokens").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(Format.money(state.history.totalCost))
                        .font(.title2.weight(.semibold)).monospacedDigit()
                    Text("等效 API 价").font(.caption).foregroundStyle(.secondary)
                }
            }
            if mode == .token {
                HStack(spacing: 14) {
                    stat("输入", Format.compact(t.input))
                    stat("输出", Format.compact(t.output))
                    stat("缓存读", Format.compact(t.cacheRead))
                    stat("消息", Format.compact(t.messages))
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.caption.weight(.medium)).monospacedDigit()
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    // 每日柱状图（鼠标悬停即时显示数据框）
    private var barChart: some View {
        let days = state.history.byDay
        let vals = days.map { mode == .token ? Double($0.tokens.total) : $0.cost }
        let maxVal = max(vals.max() ?? 1, 0.0001)
        return VStack(alignment: .leading, spacing: 4) {
            // 标题 + 悬停信息框（即时出现）。固定高度，避免出现时撑高导致抖动。
            HStack(spacing: 6) {
                Text(mode == .token ? "每日 token" : "每日金额")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let h = hoveredBar, h < days.count {
                    let d = days[h]
                    Text("\(d.day)  ·  \(mode == .token ? Format.compact(d.tokens.total) : Format.money(d.cost))")
                        .font(.caption2.weight(.medium)).monospacedDigit()
                        .padding(.horizontal, 6)
                        .background(RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.08)))
                }
            }
            .frame(height: 18)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(days.enumerated()), id: \.element.id) { i, d in
                    let v = vals[i]
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(value: v, index: i))
                        .frame(height: max(2, CGFloat(v / maxVal) * 44))
                        .contentShape(Rectangle())
                        .onHover { hoveredBar = $0 ? i : (hoveredBar == i ? nil : hoveredBar) }
                }
            }
            .frame(height: 44, alignment: .bottom)
            HStack {
                Text(String(days.first?.day.suffix(5) ?? ""))
                Spacer()
                Text("今天")
            }
            .font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .animation(.easeOut(duration: 0.12), value: hoveredBar)
    }

    private func barColor(value: Double, index: Int) -> Color {
        if index == hoveredBar { return .accentColor }                  // 高亮悬停柱
        return value > 0 ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.12)
    }

    // 分模型明细
    private var modelBreakdown: some View {
        let models = state.history.byModel
        let vals = models.map { mode == .token ? Double($0.tokens.total) : $0.cost }
        let maxVal = max(vals.max() ?? 1, 0.0001)
        return VStack(alignment: .leading, spacing: 5) {
            Text("分模型").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(models.prefix(5).enumerated()), id: \.element.id) { i, m in
                let v = vals[i]
                let label = mode == .token
                    ? Format.compact(m.tokens.total) : Format.money(m.cost)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(Format.shortModel(m.model)).font(.caption)
                        Spacer()
                        Text(label).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.12))
                            Capsule().fill(Color.accentColor.opacity(0.7))
                                .frame(width: max(3, geo.size.width * CGFloat(v / maxVal)))
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
    }
}
