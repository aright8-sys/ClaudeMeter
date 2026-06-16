import Foundation

enum Format {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// 紧凑 token 数：1234 → "1.2K"，1_500_000 → "1.5M"。
    static func compact(_ n: Int) -> String {
        let v = Double(n)
        switch n {
        case 1_000_000...:
            return String(format: "%.1fM", v / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", v / 1_000)
        default:
            return "\(n)"
        }
    }

    /// 美元金额：12.3 → "$12.34"，1234 → "$1.2K"。
    static func money(_ usd: Double) -> String {
        if usd >= 1000 {
            return String(format: "$%.1fK", usd / 1000)
        }
        return String(format: "$%.2f", usd)
    }

    /// 模型名简短显示：claude-opus-4-8 → "Opus 4.8"，claude-sonnet-4-6 → "Sonnet 4.6"。
    static func shortModel(_ id: String) -> String {
        var s = id
        if let slash = s.lastIndex(of: "/") { s = String(s[s.index(after: slash)...]) }
        let lower = s.lowercased()
        func tier(_ name: String, _ label: String) -> String? {
            guard lower.contains(name) else { return nil }
            // 抓取末尾的版本数字，如 "4-8" → "4.8"
            let parts = lower.split(separator: "-").compactMap { Int($0) }
            if parts.count >= 2 { return "\(label) \(parts[parts.count - 2]).\(parts[parts.count - 1])" }
            if let v = parts.last { return "\(label) \(v)" }
            return label
        }
        return tier("opus", "Opus") ?? tier("sonnet", "Sonnet")
            ?? tier("haiku", "Haiku") ?? s
    }
}
