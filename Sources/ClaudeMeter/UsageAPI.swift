import Foundation
import Security

/// 官方用量(权威、账号级,含桌面端)。对应 GET /api/oauth/usage。
struct OfficialUsage {
    struct Window {
        let utilization: Double   // 百分比 0...100
        let resetsAt: Date?
    }
    let fiveHour: Window?
    let sevenDay: Window?
    let extraMonthlyLimit: Int?
    let extraUsedCredits: Double?
}

enum UsageAPIError: Error, CustomStringConvertible {
    case noToken
    case unauthorized
    case rateLimited
    case network(String)
    case decode

    var description: String {
        switch self {
        case .noToken: return "未找到登录凭证,请先在 Claude Code 登录"
        case .unauthorized: return "登录已过期,请在 Claude Code 重新登录"
        case .rateLimited: return "请求过于频繁,稍候会自动恢复"
        case .network(let m): return "网络错误:\(m)"
        case .decode: return "返回数据解析失败"
        }
    }
}

enum UsageAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// 从 macOS Keychain 读取 Claude Code 的 OAuth access token。
    /// 首次访问会弹出钥匙串授权,点「始终允许」即可。
    static func readAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty
        else { return nil }
        return token
    }

    static func fetch() async throws -> OfficialUsage {
        guard let token = readAccessToken() else { throw UsageAPIError.noToken }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw UsageAPIError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw UsageAPIError.unauthorized
            }
            if http.statusCode == 429 {
                throw UsageAPIError.rateLimited
            }
            guard http.statusCode == 200 else {
                throw UsageAPIError.network("HTTP \(http.statusCode)")
            }
        }

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw UsageAPIError.decode }

        func window(_ key: String) -> OfficialUsage.Window? {
            guard let w = obj[key] as? [String: Any],
                  let util = w["utilization"] as? Double else { return nil }
            let reset = (w["resets_at"] as? String).flatMap(parseDate)
            return OfficialUsage.Window(utilization: util, resetsAt: reset)
        }

        let extra = obj["extra_usage"] as? [String: Any]

        return OfficialUsage(
            fiveHour: window("five_hour"),
            sevenDay: window("seven_day"),
            extraMonthlyLimit: extra?["monthly_limit"] as? Int,
            extraUsedCredits: extra?["used_credits"] as? Double
        )
    }

    /// 容错解析 ISO8601(含微秒和时区偏移)。
    private static func parseDate(_ s: String) -> Date? {
        let cleaned = s.replacingOccurrences(
            of: #"\.\d+"#, with: "", options: .regularExpression
        )
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: cleaned)
    }
}
