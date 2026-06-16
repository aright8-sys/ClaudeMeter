import Foundation
import SQLite3

/// 读取 Cursor 用量——**这是 ClaudeMeter 唯一会联网的数据源**，经用户明确授权。
///
/// 流程对齐 vibe-usage 的 `cursor.js`：
///   1. 从 Cursor 的本地数据库 `state.vscdb` 读出登录 token（`cursorAuth/accessToken`）。
///   2. 拿 token 联网请求 `cursor.com` 的私有 dashboard 接口，下载用量 CSV。
///   3. 解析 CSV，按天 + 模型给出 token 用量。
///
/// 数据本身在 Cursor 云端、不在本地，所以必须联网才能拿到。结果在内存缓存 10 分钟，
/// 避免反复打开面板时频繁请求。
enum CursorReader {

    /// `cost` 直接取自 CSV 的 Cost 列（Cursor 实际计的费），不再按 token 重算。
    struct Entry { let dayKey: String; let model: String; let input: Int; let output: Int; let cacheRead: Int; let cost: Double }

    private static var stateDbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
            .path
    }

    // 原始 CSV 缓存（10 分钟）
    private static var cachedCSV: String?
    private static var cachedAt: Date = .distantPast
    private static let ttl: TimeInterval = 10 * 60

    /// 取近 `cutoffKey` 起的 Cursor 用量条目。无 token / 网络失败时返回空数组（静默跳过）。
    static func entries(cutoffKey: String, dayFmt: DateFormatter) -> [Entry] {
        guard let csv = fetchCSV() else { return [] }
        return parse(csv: csv, cutoffKey: cutoffKey, dayFmt: dayFmt)
    }

    // MARK: - 取 CSV（带缓存）

    private static func fetchCSV() -> String? {
        if let c = cachedCSV, Date().timeIntervalSince(cachedAt) < ttl { return c }
        guard let token = readAccessToken(), let csv = download(token: token) else { return nil }
        cachedCSV = csv
        cachedAt = Date()
        return csv
    }

    // MARK: - 读 token（SQLite）

    private static func readAccessToken() -> String? {
        if let t = query(dbPath: stateDbPath) { return t }
        // Cursor 正在运行可能持有写锁——把库连同 -wal/-shm 复制到临时目录再读。
        let tmpDir = NSTemporaryDirectory() + "claudemeter-cursor-\(UUID().uuidString)"
        let fm = FileManager.default
        try? fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }
        let tmpDb = tmpDir + "/state.vscdb"
        guard (try? fm.copyItem(atPath: stateDbPath, toPath: tmpDb)) != nil else { return nil }
        for suffix in ["-wal", "-shm"] {
            let src = stateDbPath + suffix
            if fm.fileExists(atPath: src) { try? fm.copyItem(atPath: src, toPath: tmpDb + suffix) }
        }
        return query(dbPath: tmpDb)
    }

    private static func query(dbPath: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db); return nil
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { return nil }
        let v = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    // MARK: - 联网下载（同步，调用方在后台线程）

    private static func download(token: String) -> String? {
        let base = "https://cursor.com"
        guard let url = URL(string: "\(base)/api/dashboard/export-usage-events-csv?strategy=tokens")
        else { return nil }

        let cookie = "WorkosCursorSessionToken"
        let sub = jwtSub(token)
        // 只保留实测能成的两种：Bearer，以及 Cookie=sub::token（纯 token / 纯 Cookie 会 403，不试）。
        var attempts: [[String: String]] = [["Authorization": "Bearer \(token)"]]
        if let sub {
            attempts.append(["Cookie": "\(cookie)=\(sub)::\(token)"])
            attempts.append(["Authorization": "Bearer \(token)", "Cookie": "\(cookie)=\(sub)::\(token)"])
        }

        for headers in attempts {
            var req = URLRequest(url: url)
            req.timeoutInterval = 20    // 冷启动首个请求可能较慢
            req.setValue("text/csv,*/*;q=0.8", forHTTPHeaderField: "Accept")
            for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

            var result: String?
            let sema = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                defer { sema.signal() }
                guard (resp as? HTTPURLResponse)?.statusCode == 200,
                      let data, let text = String(data: data, encoding: .utf8) else { return }
                // cursor.com 对未鉴权请求返回 200 + 登录页 HTML，必须校验确实是 CSV。
                let head = text.prefix(200)
                guard head.contains("Date"), head.contains("Model"),
                      !head.contains("<!DOCTYPE"), !head.contains("<html") else { return }
                result = text
            }.resume()
            _ = sema.wait(timeout: .now() + 22)
            if let result { return result }
        }
        return nil
    }

    private static func jwtSub(_ token: String) -> String? {
        let parts = token.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = obj["sub"] as? String else { return nil }
        return sub.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - CSV 解析

    private static func parse(csv: String, cutoffKey: String, dayFmt: DateFormatter) -> [Entry] {
        let rows = parseCSVRows(csv)
        guard rows.count >= 2 else { return [] }
        let header = rows[0].map { $0.trimmingCharacters(in: .whitespaces) }
        func idx(_ n: String) -> Int { header.firstIndex(of: n) ?? -1 }
        let dateI = idx("Date"), modelI = idx("Model")
        let inCacheWriteI = idx("Input (w/ Cache Write)")
        let inNoCacheI = idx("Input (w/o Cache Write)")
        let cacheReadI = idx("Cache Read"), outputI = idx("Output Tokens")
        let costI = idx("Cost")
        guard dateI >= 0, modelI >= 0 else { return [] }

        let iso = ISO8601DateFormatter()
        func dayKey(_ raw: String) -> String? {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.count >= 10, t.prefix(10).allSatisfy({ $0.isNumber || $0 == "-" }) {
                return String(t.prefix(10))    // 已是 yyyy-MM-dd（UTC）
            }
            guard let d = iso.date(from: t) else { return nil }
            return dayFmt.string(from: d)
        }
        func int0(_ row: [String], _ i: Int) -> Int {
            guard i >= 0, i < row.count else { return 0 }
            let n = Int(Double(row[i].replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespaces)) ?? 0)
            return max(0, n)
        }

        var out: [Entry] = []
        for r in 1..<rows.count {
            let row = rows[r]
            if row.count == 1, row[0].trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard dateI < row.count, modelI < row.count,
                  let dk = dayKey(row[dateI]), dk >= cutoffKey else { continue }
            let model = row[modelI].trimmingCharacters(in: .whitespaces)
            guard !model.isEmpty else { continue }
            let input = int0(row, inCacheWriteI) + int0(row, inNoCacheI)
            let output = int0(row, outputI)
            let cacheRead = int0(row, cacheReadI)
            if input + output + cacheRead == 0 { continue }
            var cost = 0.0
            if costI >= 0, costI < row.count {
                let s = row[costI].replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                cost = Double(s) ?? 0
            }
            out.append(Entry(dayKey: dk, model: model, input: input, output: output,
                             cacheRead: cacheRead, cost: cost))
        }
        return out
    }

    /// 最小 CSV 状态机（支持引号、转义引号、跨行字段）。
    private static func parseCSVRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = "", row: [String] = []
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field += "\""; i += 2; continue }
                    inQuotes = false; i += 1; continue
                }
                field.append(c); i += 1; continue
            }
            switch c {
            case "\"": inQuotes = true; i += 1
            case ",":  row.append(field); field = ""; i += 1
            case "\r": i += 1
            case "\n": row.append(field); rows.append(row); field = ""; row = []; i += 1
            default:   field.append(c); i += 1
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
