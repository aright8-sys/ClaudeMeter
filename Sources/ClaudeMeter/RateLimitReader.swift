import Foundation

/// 额度窗口（5 小时 / 7 天）。
struct UsageWindow: Equatable {
    let usedPercent: Double   // 0...100
    let resetsAt: Date?
}

/// 一次额度快照的整体状态。
enum RateLimitStatus: Equatable {
    case disabled            // 还没装 statusline 钩子
    case waiting             // 装了钩子，但 Claude Code 还没渲染过状态栏（暂无数据）
    case ok                  // 有数据
    case noData              // 有文件但没有可用窗口（如 API/Bedrock 会话，无订阅额度）
    case error(String)
}

/// 从 statusline 截获文件读出的额度快照。
struct RateLimitSnapshot: Equatable {
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?
    var modelId: String?
    var capturedAt: Date?
    var status: RateLimitStatus

    static let disabled = RateLimitSnapshot(status: .disabled)

    init(fiveHour: UsageWindow? = nil, sevenDay: UsageWindow? = nil,
         modelId: String? = nil, capturedAt: Date? = nil, status: RateLimitStatus) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.modelId = modelId
        self.capturedAt = capturedAt
        self.status = status
    }

    /// 快照超过这个时长就算"陈旧"（Claude Code 可能正空闲）。
    static let stalenessThreshold: TimeInterval = 30 * 60

    var isStale: Bool {
        guard let capturedAt else { return false }
        return Date().timeIntervalSince(capturedAt) > Self.stalenessThreshold
    }
}

/// 读取 statusline 钩子写下的本地额度文件——无网络、无 token、无钥匙串。
enum RateLimitReader {

    static func read() -> RateLimitSnapshot {
        let url = StatuslineHook.rateLimitFileURL

        guard FileManager.default.fileExists(atPath: url.path) else {
            // 没有截获文件：要么没启用钩子，要么 Claude Code 还没渲染过状态栏。
            return .init(status: StatuslineHook.isInstalled ? .waiting : .disabled)
        }
        guard let data = try? Data(contentsOf: url) else {
            return .init(status: .error("无法读取额度缓存"))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .init(status: .error("额度缓存格式错误"))
        }

        let fiveHour = parseWindow(obj["five_hour"])
        let sevenDay = parseWindow(obj["seven_day"])

        guard fiveHour != nil || sevenDay != nil else {
            // 文件在但没有可用窗口——例如 API/Bedrock 会话（无订阅额度）。
            return .init(status: .noData)
        }

        let capturedAt = (obj["captured_at"] as? Double).map { Date(timeIntervalSince1970: $0) }

        return .init(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            modelId: obj["model_id"] as? String,
            capturedAt: capturedAt,
            status: .ok
        )
    }

    /// 解析一个 `{ used_percentage, resets_at }` 窗口。容忍 used_percentage / utilization
    /// 两种 key，以及 resets_at 为 epoch 秒（Number）或 ISO-8601（String）——
    /// Claude Code 的字段是逆向出来的、随版本会变，所以多防一手。
    private static func parseWindow(_ raw: Any?) -> UsageWindow? {
        guard let dict = raw as? [String: Any] else { return nil }

        let percent: Double
        if let v = dict["used_percentage"] as? Double {
            percent = v
        } else if let v = dict["utilization"] as? Double {
            percent = v
        } else {
            return nil
        }

        var resetsAt: Date?
        if let secs = dict["resets_at"] as? Double, secs > 0 {
            resetsAt = Date(timeIntervalSince1970: secs)
        } else if let str = dict["resets_at"] as? String, !str.isEmpty {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetsAt = iso.date(from: str) ?? ISO8601DateFormatter().date(from: str)
        }

        return UsageWindow(usedPercent: percent, resetsAt: resetsAt)
    }
}
