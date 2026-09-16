import Foundation

/// App Server 协议解析层。
/// 所有字段按可选值解析（实验性协议，字段可能缺失或变更）；
/// 优先读 rateLimitsByLimitId.codex，缺失时回退 rateLimits。
enum RateLimitsParser {

    /// 解析 account/rateLimits/read 响应的 result 对象。
    /// 返回 nil 表示响应中没有任何限额桶（调用方应视为读取失败，不得显示 0%）。
    static func snapshot(fromResult result: [String: Any], now: Date = Date()) -> RateLimitSnapshot? {
        var bucket: [String: Any]?
        if let byId = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byId["codex"] as? [String: Any] {
            bucket = codex
        } else if let rl = result["rateLimits"] as? [String: Any] {
            bucket = rl
        }
        guard let bucket else { return nil }
        return RateLimitSnapshot(
            limitId: bucket["limitId"] as? String,
            primary: window(bucket["primary"]),
            secondary: window(bucket["secondary"]),
            planType: bucket["planType"] as? String,
            fetchedAt: now
        )
    }

    /// 解析单个窗口。
    /// 字段规则（不编造额度，宁可显示「未返回」）：
    /// - `usedPercent`：必须是 0～100 的整数，否则整个窗口视为未返回；
    /// - `windowDurationMins`：必须为正整数，否则按「未知窗口」处理；
    /// - `resetsAt`：必须为正整数 Unix 秒，否则按「重置时间暂未返回」处理。
    static func window(_ any: Any?) -> RateWindow? {
        guard let dict = any as? [String: Any],
              let used = intValue(dict["usedPercent"]),
              (0...100).contains(used) else { return nil }
        var resetsAt: Date?
        if let ts = intValue(dict["resetsAt"]), ts > 0 {
            resetsAt = Date(timeIntervalSince1970: TimeInterval(ts))
        }
        let mins = intValue(dict["windowDurationMins"]).flatMap { $0 > 0 ? $0 : nil }
        return RateWindow(
            usedPercent: used,
            windowDurationMins: mins,
            resetsAt: resetsAt
        )
    }

    /// 解析 account/read 响应的 result 对象
    static func account(fromResult result: [String: Any]) -> AccountInfo {
        let requiresAuth = (result["requiresOpenaiAuth"] as? Bool) ?? false
        guard let account = result["account"] as? [String: Any],
              let type = account["type"] as? String else {
            return AccountInfo(loggedIn: false, email: nil, planType: nil,
                               requiresAuth: requiresAuth, accountType: nil)
        }
        return AccountInfo(
            loggedIn: true,
            email: account["email"] as? String,
            planType: account["planType"] as? String,
            requiresAuth: requiresAuth,
            accountType: type
        )
    }

    /// JSON 整数解析：只接受「非 Bool 的完整整数值」。
    ///
    /// 两个必须处理的坑：
    /// 1. Foundation 把 JSON 的 `true` / `false` 解析为 `NSNumber`（`__NSCFBoolean`），
    ///    它同时满足 `is Int` / `is Double` / `is NSNumber`，若不先拦截会被当成 1 / 0；
    /// 2. `12.5` 这类小数不得静默截断为 12——调用方只接受整数，故此处直接拒绝。
    ///
    /// 接受：`25`、`25.0`；拒绝：`true`、`false`、`12.5`、`NaN`、`Infinity`、非数值。
    static func intValue(_ any: Any?) -> Int? {
        guard let any else { return nil }
        if let n = any as? NSNumber {
            // 注意：不能用 `any is Bool` 判断——NSNumber 可桥接成 Bool，会把 6 也当成 true 而误拒。
            // 只能用 CFGetTypeID 精确识别 JSON 布尔（__NSCFBoolean）。
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
            let d = n.doubleValue
            // 超大有限数：Int(d) 越界会直接 trap（菜单栏 App 崩溃），外部 JSON 必须先挡住
            guard d.isFinite, d == d.rounded(),
                  d >= Double(Int.min), d < Double(Int.max) else { return nil }
            return Int(d)
        }
        if let i = any as? Int { return i }
        if let d = any as? Double {
            guard d.isFinite, d == d.rounded() else { return nil }
            return Int(d)
        }
        return nil // 含原生 Bool、字符串、null 等
    }
}
