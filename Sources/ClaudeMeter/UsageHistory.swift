import Foundation

/// 一段时间内的 token 计数。
struct TokenCounts: Equatable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheCreation = 0
    var messages = 0

    /// 总量（含缓存）。缓存读取通常占大头且便宜，所以 UI 里会单独再拆开展示。
    var total: Int { input + output + cacheRead + cacheCreation }

    static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: a.input + b.input,
            output: a.output + b.output,
            cacheRead: a.cacheRead + b.cacheRead,
            cacheCreation: a.cacheCreation + b.cacheCreation,
            messages: a.messages + b.messages
        )
    }
    static func += (a: inout TokenCounts, b: TokenCounts) { a = a + b }
}

struct DayUsage: Identifiable, Equatable {
    let day: String          // yyyy-MM-dd（UTC）
    let tokens: TokenCounts
    let cost: Double         // 等效 API 美元成本
    var id: String { day }
}

struct ModelUsage: Identifiable, Equatable {
    let model: String
    let tokens: TokenCounts
    let cost: Double
    var id: String { model }
}

/// 从本地会话日志聚合出的历史用量（纯本地，不上传）。
struct UsageHistory: Equatable {
    let days: Int
    let total: TokenCounts
    let totalCost: Double      // 等效 API 美元成本（订阅用户不按此付费，仅供参考）
    let byDay: [DayUsage]      // 按日期升序，含中间没用的空天
    let byModel: [ModelUsage]  // 按总量降序
    let generatedAt: Date

    static let empty = UsageHistory(days: 0, total: TokenCounts(), totalCost: 0,
                                    byDay: [], byModel: [], generatedAt: .distantPast)
    var isEmpty: Bool { total.messages == 0 }
}

/// 各模型的等效 API 价（USD / 百万 token）。
///
/// 算法对齐 vibe-usage（vibecafe.ai）：只计 未缓存输入 + 输出 + 缓存读(×0.1)，
/// **不计缓存写**——vibe 的解析器根本不上传 `cache_creation_input_tokens`，
/// 服务器据此算钱，所以缓存写成本为 0。我们照此对齐。
enum Pricing {
    /// (输入, 输出) USD / 1M token。未知模型返回 nil（不计入金额）。
    static func rates(for model: String) -> (input: Double, output: Double)? {
        let m = model.lowercased()
        if m.contains("opus")   { return (5.0, 25.0) }
        if m.contains("sonnet") { return (3.0, 15.0) }
        if m.contains("haiku")  { return (1.0, 5.0) }
        // GPT / o 系列 / Codex（近似价；Codex 占比很小，误差可忽略）
        if m.contains("gpt") || m.contains("codex") { return (1.25, 10.0) }
        if m.first == "o", m.dropFirst().first?.isNumber == true { return (1.25, 10.0) }
        if m.contains("kimi") || m.contains("moonshot") { return (0.6, 2.5) }   // 近似
        if m.contains("gemini") { return (1.25, 10.0) }                          // 近似
        // 兜底：Cursor 的 auto / composer 等伪模型。按反推自 vibe 面板的近似价
        // （约 $1.75/$7 每百万 token）计，好让"等效 API 价值"贴近 vibe；非官方价。
        return (1.75, 7.0)
    }

    /// 一组 token 计数的等效美元成本（与 vibe-usage 口径一致，不含缓存写）。
    static func cost(model: String, _ t: TokenCounts) -> Double {
        guard let r = rates(for: model) else { return 0 }
        let per = 1_000_000.0
        return Double(t.input) / per * r.input
            + Double(t.output) / per * r.output
            + Double(t.cacheRead) / per * (r.input * 0.1)
    }
}

/// 把各来源的逐条用量累加进按天 / 按模型 / 总计的桶里（口径对齐 vibe-usage）。
private final class Accumulator {
    var perDay: [String: TokenCounts] = [:]
    var perDayCost: [String: Double] = [:]
    var perModel: [String: TokenCounts] = [:]
    var perModelCost: [String: Double] = [:]
    var total = TokenCounts()
    var totalCost = 0.0

    /// `cost` 为 nil 时按 token 用 Pricing 估算（Claude/Codex）；
    /// 传入显式值时直接采用（Cursor 用 CSV 自带的真实 Cost）。
    func add(dayKey: String, model: String, _ c: TokenCounts, cost: Double? = nil) {
        let cost = cost ?? Pricing.cost(model: model, c)
        perDay[dayKey, default: TokenCounts()] += c
        perDayCost[dayKey, default: 0] += cost
        perModel[model, default: TokenCounts()] += c
        perModelCost[model, default: 0] += cost
        total += c
        totalCost += cost
    }
}

/// 扫描本地各 CLI 工具的会话日志（Claude Code、Codex），按天 + 模型聚合用量。
/// 纯本地、不联网、不上传。
enum UsageHistoryReader {

    private static func home(_ p: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(p)
    }

    private static var claudeProjectsDir: URL {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
                .appendingPathComponent("projects")
        }
        return home(".claude").appendingPathComponent("projects")
    }

    /// 同步扫描——调用方应放到后台线程。
    /// `includeCursor`=true 时会联网拉取 Cursor 云端用量（需用户授权）。
    static func load(days: Int = 30, includeCursor: Bool = false) -> UsageHistory {
        let dayFmt = DateFormatter()
        dayFmt.calendar = Calendar(identifier: .gregorian)
        dayFmt.timeZone = TimeZone(identifier: "UTC")
        dayFmt.dateFormat = "yyyy-MM-dd"
        let cutoffDate = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date()
        let cutoffKey = dayFmt.string(from: cutoffDate)

        let acc = Accumulator()
        scanClaude(cutoffKey: cutoffKey, into: acc)
        scanCodex(cutoffKey: cutoffKey, dayFmt: dayFmt, into: acc)
        if includeCursor {
            for e in CursorReader.entries(cutoffKey: cutoffKey, dayFmt: dayFmt) {
                // vibe 口径：按 token 重算等效 API 价（含 auto/composer 兜底定价）
                acc.add(dayKey: e.dayKey, model: e.model, TokenCounts(
                    input: e.input, output: e.output, cacheRead: e.cacheRead,
                    cacheCreation: 0, messages: 0))
            }
        }

        // 补齐区间内每一天（含 0 用量的天），方便 UI 画连续的柱状图。
        var byDay: [DayUsage] = []
        let cal = Calendar(identifier: .gregorian)
        for offset in stride(from: days - 1, through: 0, by: -1) {
            if let d = cal.date(byAdding: .day, value: -offset, to: Date()) {
                let key = dayFmt.string(from: d)
                byDay.append(DayUsage(day: key,
                                      tokens: acc.perDay[key] ?? TokenCounts(),
                                      cost: acc.perDayCost[key] ?? 0))
            }
        }

        let byModel = acc.perModel
            .map { ModelUsage(model: $0.key, tokens: $0.value,
                              cost: acc.perModelCost[$0.key] ?? 0) }
            .sorted { $0.tokens.total > $1.tokens.total }

        return UsageHistory(days: days, total: acc.total, totalCost: acc.totalCost,
                            byDay: byDay, byModel: byModel, generatedAt: Date())
    }

    private static func jsonlFiles(under dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    private static func intVal(_ d: [String: Any], _ key: String) -> Int {
        if let n = d[key] as? Int { return n }
        if let x = d[key] as? Double { return Int(x) }
        return 0
    }

    // MARK: - Claude Code

    private static func scanClaude(cutoffKey: String, into acc: Accumulator) {
        var seen = Set<String>()    // 按消息 uuid 去重
        for url in jsonlFiles(under: claudeProjectsDir) {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            content.enumerateLines { line, _ in
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let msg = obj["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any],
                      let model = msg["model"] as? String, model != "<synthetic>",
                      let ts = obj["timestamp"] as? String, ts.count >= 10
                else { return }
                let dayKey = String(ts.prefix(10))
                guard dayKey >= cutoffKey else { return }
                if let uuid = obj["uuid"] as? String {
                    if seen.contains(uuid) { return }
                    seen.insert(uuid)
                }
                acc.add(dayKey: dayKey, model: model, TokenCounts(
                    input: intVal(usage, "input_tokens"),
                    output: intVal(usage, "output_tokens"),
                    cacheRead: intVal(usage, "cache_read_input_tokens"),
                    cacheCreation: intVal(usage, "cache_creation_input_tokens"),
                    messages: 1
                ))
            }
        }
    }

    // MARK: - Codex（OpenAI CLI）

    /// 解析 `~/.codex/sessions|archived_sessions/**/*.jsonl` 里的 `token_count` 事件。
    /// OpenAI 口径：input_tokens 含 cached、output_tokens 含 reasoning，这里拆开对齐 vibe。
    /// （未做 fork 重放去重；Codex 占比极小，影响可忽略。）
    private static func scanCodex(cutoffKey: String, dayFmt: DateFormatter, into acc: Accumulator) {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        func parseDay(_ s: String) -> String? {
            guard let d = iso.date(from: s) ?? iso2.date(from: s) else {
                return s.count >= 10 ? String(s.prefix(10)) : nil
            }
            return dayFmt.string(from: d)
        }

        for dir in [home(".codex/sessions"), home(".codex/archived_sessions")] {
            for url in jsonlFiles(under: dir) {
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                var model = "unknown"
                content.enumerateLines { line, _ in
                    guard let data = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    else { return }

                    if obj["type"] as? String == "turn_context",
                       let p = obj["payload"] as? [String: Any], let m = p["model"] as? String {
                        model = m; return
                    }
                    guard obj["type"] as? String == "event_msg",
                          let p = obj["payload"] as? [String: Any],
                          p["type"] as? String == "token_count",
                          let info = p["info"] as? [String: Any],
                          let usage = info["last_token_usage"] as? [String: Any],
                          let ts = obj["timestamp"] as? String,
                          let dayKey = parseDay(ts), dayKey >= cutoffKey
                    else { return }

                    let m = (info["model"] as? String) ?? model
                    let cached = intVal(usage, "cached_input_tokens")
                    acc.add(dayKey: dayKey, model: m, TokenCounts(
                        input: max(0, intVal(usage, "input_tokens") - cached),
                        output: intVal(usage, "output_tokens"),   // 含 reasoning，便于算成本
                        cacheRead: cached,
                        cacheCreation: 0,
                        messages: 1
                    ))
                }
            }
        }
    }
}
