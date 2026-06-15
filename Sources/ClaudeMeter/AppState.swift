import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // 官方权威用量(账号级,含桌面端)
    @Published private(set) var official: OfficialUsage?
    @Published private(set) var officialError: String?

    @Published private(set) var lastUpdated: Date = .distantPast
    @Published private(set) var now: Date = Date()

    /// 是否在菜单栏百分比旁显示 5 小时窗口重置倒计时(持久化)。
    @Published var showResetInStatusBar: Bool {
        didSet { UserDefaults.standard.set(showResetInStatusBar, forKey: Self.resetKey) }
    }
    private static let resetKey = "showResetInStatusBar"

    private var tickTimer: Timer?
    private var pollTimer: Timer?

    init() {
        showResetInStatusBar = (UserDefaults.standard.object(forKey: Self.resetKey) as? Bool) ?? true
        Task { await refreshOfficial() }
        startTimers()
    }

    // MARK: - 刷新

    private func startTimers() {
        tickTimer?.invalidate()
        // 倒计时 tick(不读盘、不联网)
        tickTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
        pollTimer?.invalidate()
        // 官方用量每 600 秒拉一次(服务器数据本身约分钟级更新);打开面板时也会即时拉一次
        pollTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshOfficial() }
        }
    }

    func refreshOfficial() async {
        do {
            official = try await UsageAPI.fetch()
            officialError = nil
        } catch {
            officialError = (error as? UsageAPIError)?.description ?? error.localizedDescription
        }
        now = Date()
        lastUpdated = now
    }

    func refreshAll() {
        Task { await refreshOfficial() }
    }

    /// 打开面板时调用:60 秒内刚成功刷过就跳过,避免反复开关面板触发限流。
    func refreshOnOpen() {
        if official != nil, now.timeIntervalSince(lastUpdated) < 60 { return }
        Task { await refreshOfficial() }
    }

    // MARK: - 派生值(官方)

    var fiveHourPercent: Double? { official?.fiveHour?.utilization }
    var sevenDayPercent: Double? { official?.sevenDay?.utilization }

    /// 菜单栏文案:5 小时用量百分比 + 窗口重置倒计时(拼成单个字符串,
    /// 因为 MenuBarExtra 的 label 对多个子视图渲染不稳定)。
    var statusBarText: String {
        guard let p = fiveHourPercent else {
            return officialError == nil ? "…" : "!"
        }
        let pct = "\(Int(p.rounded()))%"
        if showResetInStatusBar, let resetsAt = official?.fiveHour?.resetsAt {
            return "\(pct) · \(countdown(to: resetsAt))"
        }
        return pct
    }

    func countdown(to date: Date?) -> String {
        guard let date else { return "—" }
        let secs = Int(max(0, date.timeIntervalSince(now)))
        let h = secs / 3600, m = (secs % 3600) / 60
        if h >= 24 { return "\(h / 24)天 \(h % 24)h" }
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
