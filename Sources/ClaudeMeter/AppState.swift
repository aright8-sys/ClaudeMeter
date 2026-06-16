import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    // 额度快照(来自 statusline 截获文件,无网络)
    @Published private(set) var snapshot: RateLimitSnapshot = .disabled

    // 历史用量(来自本地会话日志,纯本地)
    @Published private(set) var history: UsageHistory = .empty
    @Published private(set) var historyLoading = false

    @Published private(set) var lastUpdated: Date = .distantPast
    @Published private(set) var now: Date = Date()

    /// 是否已启用 statusline 截获(持久化)。
    @Published var captureEnabled: Bool {
        didSet {
            UserDefaults.standard.set(captureEnabled, forKey: Self.captureKey)
            if captureEnabled { _ = StatuslineHook.install() }
            else { _ = StatuslineHook.uninstall() }
            refreshAll()
        }
    }
    private static let captureKey = "captureEnabled"

    /// 是否在菜单栏百分比旁显示 5 小时窗口重置倒计时(持久化)。
    @Published var showResetInStatusBar: Bool {
        didSet { UserDefaults.standard.set(showResetInStatusBar, forKey: Self.resetKey) }
    }
    private static let resetKey = "showResetInStatusBar"

    private var tickTimer: Timer?
    private var pollTimer: Timer?

    init() {
        captureEnabled = (UserDefaults.standard.object(forKey: Self.captureKey) as? Bool) ?? false
        showResetInStatusBar = (UserDefaults.standard.object(forKey: Self.resetKey) as? Bool) ?? true
        // 启用过就自愈(别的工具可能覆盖了 statusLine 命令)。
        StatuslineHook.verifyAndRepair(enabled: captureEnabled)
        refreshAll()
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
        // 每 60 秒重读截获文件(文件由 Claude Code 渲染状态栏时更新)。
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshRateLimit() }
        }
    }

    /// 重读额度截获文件(快、纯本地)。
    func refreshRateLimit() {
        if captureEnabled {
            StatuslineHook.verifyAndRepair(enabled: true)
        }
        snapshot = RateLimitReader.read()
        now = Date()
        lastUpdated = now
    }

    /// 后台扫描本地日志,重算历史用量。
    func refreshHistory(days: Int = 30) {
        guard !historyLoading else { return }
        historyLoading = true
        let includeCursor = true   // Cursor 始终后台联网拉
        Task.detached(priority: .userInitiated) {
            // 先出本地（Claude+Codex，瞬间），UI 立刻有数据
            let local = UsageHistoryReader.load(days: days, includeCursor: false)
            await MainActor.run {
                self.history = local
                if !includeCursor { self.historyLoading = false }
            }
            // 再补 Cursor（联网，可能几秒），完成后再刷新一次
            if includeCursor {
                let full = UsageHistoryReader.load(days: days, includeCursor: true)
                await MainActor.run {
                    self.history = full
                    self.historyLoading = false
                }
            }
        }
    }

    func refreshAll() {
        refreshRateLimit()
        refreshHistory()
    }

    /// 打开面板时调用:60 秒内刚刷过额度就跳过,但历史每次都后台重算(扫盘也很快)。
    func refreshOnOpen() {
        if snapshot.status == .ok, now.timeIntervalSince(lastUpdated) < 60 {
            refreshHistory()
            return
        }
        refreshAll()
    }

    // MARK: - 派生值(额度)

    var fiveHourPercent: Double? { snapshot.fiveHour?.usedPercent }
    var sevenDayPercent: Double? { snapshot.sevenDay?.usedPercent }

    /// 菜单栏文案:5 小时用量百分比 + 窗口重置倒计时(拼成单个字符串,
    /// 因为 MenuBarExtra 的 label 对多个子视图渲染不稳定)。
    var statusBarText: String {
        guard let p = fiveHourPercent else {
            switch snapshot.status {
            case .disabled, .waiting: return "—"
            case .error: return "!"
            default: return "…"
            }
        }
        let pct = "\(Int(p.rounded()))%"
        if showResetInStatusBar, let resetsAt = snapshot.fiveHour?.resetsAt {
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
