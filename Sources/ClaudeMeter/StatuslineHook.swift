import Foundation

/// 把一个透明的包装脚本装进 Claude Code 的 `statusLine.command`，
/// 从而截获 Claude Code 每次渲染状态栏时通过 stdin 喂过来的 `rate_limits`。
///
/// 包装脚本（见下方内嵌的 `wrapperScriptBody`）做两件事：
///   1. 把 payload 里的 `rate_limits` 切片写到 `~/.claudemeter/claude-rate-limits.json`
///   2. 用**原封不动**的 stdin 调用用户原来的 statusLine 命令，
///      所以现有的状态栏 / 其它工具（含 vibe-usage）照常工作、无感知。
///
/// 安装是幂等且自愈的：`verifyAndRepair()` 会在别的工具
/// （或用户跑 `/statusline`）覆盖了命令时重新把自己包进去。
enum StatuslineHook {

    enum HookError: LocalizedError {
        case settingsUnreadable(String)
        case settingsUnwritable(String)

        var errorDescription: String? {
            switch self {
            case .settingsUnreadable(let m): "无法读取 Claude 配置: \(m)"
            case .settingsUnwritable(let m): "无法写入 Claude 配置: \(m)"
            }
        }
    }

    // MARK: - 路径

    /// 尊重 CLAUDE_CONFIG_DIR（部分用户把 ~/.claude 挪了位置），否则用默认。
    private static var claudeDir: URL {
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"],
           !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    private static var settingsURL: URL { claudeDir.appendingPathComponent("settings.json") }

    /// ClaudeMeter 自己的工作目录（与 vibe-usage 的 ~/.vibe-usage 分开）。
    static var workDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claudemeter")
    }

    private static var wrapperURL: URL { workDir.appendingPathComponent("claudemeter-statusline.sh") }
    private static var sidecarURL: URL { workDir.appendingPathComponent("statusline-original") }
    private static var backupURL: URL { workDir.appendingPathComponent("settings.json.cm-bak") }

    /// 写进 settings.json 的命令。其余一切由包装脚本运行时从 sidecar 解析。
    private static var wrapperCommand: String { "bash \"\(wrapperURL.path)\"" }

    /// 截获到的额度文件路径（RateLimitReader 读它）。
    static var rateLimitFileURL: URL {
        workDir.appendingPathComponent("claude-rate-limits.json")
    }

    // MARK: - 状态

    /// settings.json 当前是否把状态栏路由到了我们的包装脚本。
    static var isInstalled: Bool {
        currentStatuslineCommand() == wrapperCommand
    }

    // MARK: - 安装 / 卸载

    /// 幂等安装（或重新断言）包装脚本。可反复调用。
    @discardableResult
    static func install() -> Result<Void, HookError> {
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            try writeWrapperScript()

            let settings = try loadSettings()
            let existing = (settings["statusLine"] as? [String: Any])?["command"] as? String

            // 把用户原来的命令存进 sidecar——但绝不把我们自己的命令存进去
            //（那会让包装脚本调用它自己，形成死循环）。
            if let existing, existing != wrapperCommand {
                backupSettingsIfNeeded()
                try existing.write(to: sidecarURL, atomically: true, encoding: .utf8)
            } else if existing == nil && !FileManager.default.fileExists(atPath: sidecarURL.path) {
                // 之前完全没有 statusLine：sidecar 留空，包装脚本不向下游转发。
            }

            var newSettings = settings
            newSettings["statusLine"] = ["type": "command", "command": wrapperCommand]
            try saveSettings(newSettings)
            return .success(())
        } catch let e as HookError {
            return .failure(e)
        } catch {
            return .failure(.settingsUnwritable(error.localizedDescription))
        }
    }

    /// 恢复用户原来的 statusLine 命令（从 sidecar）。
    @discardableResult
    static func uninstall() -> Result<Void, HookError> {
        do {
            var settings = try loadSettings()
            if let original = try? String(contentsOf: sidecarURL, encoding: .utf8),
               !original.isEmpty {
                settings["statusLine"] = ["type": "command", "command": original]
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            try saveSettings(settings)
            return .success(())
        } catch let e as HookError {
            return .failure(e)
        } catch {
            return .failure(.settingsUnwritable(error.localizedDescription))
        }
    }

    /// 用户启用过、但被外部工具覆盖了命令时，静默重新包裹：
    /// 那个替换命令会成为我们转发的新"原始命令"。已安装或未启用时是 no-op。
    static func verifyAndRepair(enabled: Bool) {
        guard enabled, !isInstalled else { return }
        _ = install()
    }

    // MARK: - 辅助

    private static func currentStatuslineCommand() -> String? {
        guard let settings = try? loadSettings() else { return nil }
        return (settings["statusLine"] as? [String: Any])?["command"] as? String
    }

    private static func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else {
            return [:] // 还没有配置文件——从空开始。
        }
        do {
            let data = try Data(contentsOf: settingsURL)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw HookError.settingsUnreadable("settings.json 不是一个 JSON 对象")
            }
            return obj
        } catch let e as HookError {
            throw e
        } catch {
            throw HookError.settingsUnreadable(error.localizedDescription)
        }
    }

    private static func saveSettings(_ obj: [String: Any]) throws {
        do {
            try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: obj,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            // 原子写，避免 Claude Code 并发读到写了一半的文件。
            try data.write(to: settingsURL, options: .atomic)
        } catch {
            throw HookError.settingsUnwritable(error.localizedDescription)
        }
    }

    /// 第一次改动前，对用户 settings.json 做一次性安全备份。
    private static func backupSettingsIfNeeded() {
        guard !FileManager.default.fileExists(atPath: backupURL.path),
              FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        try? FileManager.default.copyItem(at: settingsURL, to: backupURL)
    }

    private static func writeWrapperScript() throws {
        try wrapperScriptBody.write(to: wrapperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: wrapperURL.path
        )
    }

    /// 内嵌的包装脚本。tee 出 rate_limits，再把原始 stdin 转发给原命令。
    private static let wrapperScriptBody = #"""
    #!/bin/bash
    # ClaudeMeter statusline 包装脚本——由 ClaudeMeter.app 生成，请勿手改；
    # 下次安装/修复时会被覆盖。
    set -euo pipefail

    CM_DIR="${HOME}/.claudemeter"
    OUT="${CM_DIR}/claude-rate-limits.json"
    SIDECAR="${CM_DIR}/statusline-original"

    payload="$(cat)"

    emit() {
      local tmp
      tmp="$(mktemp "${CM_DIR}/.claude-rate-limits.XXXXXX")" || return 0
      printf '%s' "$1" > "$tmp" 2>/dev/null && mv -f "$tmp" "$OUT" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    }

    mkdir -p "$CM_DIR" 2>/dev/null || true

    JS='
    let raw = "";
    process.stdin.on("data", d => raw += d);
    process.stdin.on("end", () => {
      try {
        const o = JSON.parse(raw);
        const rl = o && o.rate_limits;
        if (!rl || (rl.five_hour == null && rl.seven_day == null)) { process.exit(2); }
        const out = {
          five_hour: rl.five_hour ?? null,
          seven_day: rl.seven_day ?? null,
          model_id: (o.model && o.model.id) || null,
          captured_at: Math.floor(Date.now() / 1000),
        };
        process.stdout.write(JSON.stringify(out));
        process.exit(0);
      } catch (e) { process.exit(3); }
    });
    '

    RUNTIME=""
    if command -v bun >/dev/null 2>&1; then
      RUNTIME="bun"
    elif command -v node >/dev/null 2>&1; then
      RUNTIME="node"
    fi

    if [ -n "$RUNTIME" ]; then
      if parsed="$(printf '%s' "$payload" | "$RUNTIME" -e "$JS" 2>/dev/null)"; then
        [ -n "$parsed" ] && emit "$parsed"
      fi
    fi

    if [ -s "$SIDECAR" ]; then
      ORIGINAL="$(cat "$SIDECAR")"
      printf '%s' "$payload" | exec sh -c "$ORIGINAL"
    fi

    exit 0
    """#
}
