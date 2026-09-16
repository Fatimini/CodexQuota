import Foundation

/// 探针模式状态收集
private final class ProbeBox {
    var done = false
    var exitCode: Int32 = 1
    var account: AccountInfo?
    var cliVersion: String?
}

/// `--probe` 无界面探针：走与 App 完全相同的数据链路读取一次限额，
/// 输出打码后的 JSON 摘要，作为真实账号读取的可复现验证记录。
enum ProbeRunner {

    static func run() -> Never {
        fputs("CodexQuota probe：正在通过 codex app-server 读取限额…\n", stderr)

        // 支持 CODEXQUOTA_CODEX_PATH 覆盖路径，用于异常场景验证（伪造无效/会崩溃的 CLI）
        let url: URL
        if let override = ProcessInfo.processInfo.environment["CODEXQUOTA_CODEX_PATH"], !override.isEmpty {
            url = URL(fileURLWithPath: override)
        } else if let located = AppServerClient.locateCodex() {
            url = located
        } else {
            fputs("ERROR: 未找到 codex CLI\n", stderr)
            exit(2)
        }

        let box = ProbeBox()
        let client = AppServerClient(executableURL: url)

        client.onEvent = { event in
            switch event {
            case .connected(let version):
                box.cliVersion = version
            case .cliVersion(let version):
                box.cliVersion = version
            case .account(let info):
                box.account = info
            case .snapshot(let snap):
                printReport(path: url.path, box: box, snapshot: snap)
                box.done = true
                box.exitCode = 0
            case .disconnected(let reason):
                fputs("ERROR: \(L10n.text(for: reason))\n", stderr)
                box.done = true
            case .readFailed(let failure):
                fputs("ERROR: \(L10n.text(for: failure))\n", stderr)
                box.done = true
            }
        }

        client.start()

        let deadline = Date().addingTimeInterval(20)
        while !box.done && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        if !box.done {
            fputs("ERROR: 读取超时（20s）\n", stderr)
        }
        client.stop()
        exit(box.exitCode)
    }

    /// 生成探针报告（抽成可测函数）。
    /// **隐私收口**：只保留 codex 可执行文件名，不输出完整本机路径——
    /// 探针输出常被贴进 Issue 或聊天记录，不应暴露用户名与目录结构。
    static func makeReport(codexPath: String,
                           cliVersion: String?,
                           account: AccountInfo?,
                           snapshot: RateLimitSnapshot) -> [String: Any] {
        var windows: [[String: Any]] = []
        for w in snapshot.windows {
            var item: [String: Any] = [
                "窗口": w.displayName,
                "windowDurationMins": w.windowDurationMins as Any,
                "已用%": w.usedPercent,
                "剩余%": w.remainingPercent,
            ]
            if let resetsAt = w.resetsAt {
                item["重置本地时间"] = QuotaFormatter.localTimeText(resetsAt)
            }
            windows.append(item)
        }
        let report: [String: Any] = [
            "codex可执行文件": URL(fileURLWithPath: codexPath).lastPathComponent,
            "CLI版本": cliVersion ?? "未知",
            "账号": QuotaFormatter.maskEmail(account?.email) ?? (account?.loggedIn == false ? "未登录" : "未知"),
            "套餐": snapshot.planType ?? account?.planType ?? "未知",
            "读取时间": QuotaFormatter.timeText(snapshot.fetchedAt),
            "窗口": windows,
        ]
        return report
    }

    private static func printReport(path: String, box: ProbeBox, snapshot: RateLimitSnapshot) {
        let report = makeReport(codexPath: path,
                                cliVersion: box.cliVersion,
                                account: box.account,
                                snapshot: snapshot)
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }
}
