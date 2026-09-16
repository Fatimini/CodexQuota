import Foundation

/// 轻量国际化：跟随系统首选语言——中文（简/繁）显示中文，其他语言显示英文。
/// 系统语言变更通过 NSLocale.currentLocaleDidChangeNotification 实时生效，无需重启。
enum L10n {

    enum Language {
        case zh, en
    }

    /// 测试用强制语言；nil = 跟随系统
    static var forcedLanguage: Language?

    static var current: Language {
        if let forcedLanguage { return forcedLanguage }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("zh") ? .zh : .en
    }

    static var isZh: Bool { current == .zh }

    static var setupHelp: String { isZh ? "安装帮助" : "Setup help" }
    static var cliGuide: String { isZh ? "打开 Codex 官方安装说明" : "Open official Codex setup guide" }
    static var setupMissingCLI: String { isZh ? "需要先安装 Codex CLI。安装并登录后，请退出并重新打开本工具。无需编译本工具。" : "Install Codex CLI and sign in, then quit and reopen this app. No app compilation is needed." }
    static var setupLogin: String { isZh ? "请在终端运行 codex login，使用自己的 ChatGPT 账号登录，然后退出并重新打开本工具。" : "Run codex login in Terminal with your own ChatGPT account, then quit and reopen this app." }
    static var setupReadFailed: String { isZh ? "暂时无法读取额度。请检查网络，并确认 Codex CLI 可以正常使用，再点“立即刷新”。已有数据会保留并标记为已过期。" : "Quota could not be read. Check your network and that Codex CLI works, then refresh. Previous readings remain marked as stale." }

    // MARK: - 菜单栏

    static var menuOffline: String { isZh ? "离线" : "Offline" }
    static var menuNoData: String { isZh ? "暂未返回" : "No data" }
    static var staleSuffix: String { isZh ? "（已过期）" : " (stale)" }
    static var listSeparator: String { isZh ? "｜" : " | " }
    static var labelColon: String { isZh ? "：" : ": " }

    // MARK: - 窗口名称

    static func windowName(minutes: Int?) -> String {
        guard let m = minutes else { return isZh ? "未知窗口" : "Unknown window" }
        switch m {
        case 300: return isZh ? "5 小时窗口" : "5-hour window"
        case 10080: return isZh ? "7 天（周）窗口" : "7-day (weekly) window"
        case 60: return isZh ? "1 小时窗口" : "1-hour window"
        default:
            if m % 1440 == 0 { return isZh ? "\(m / 1440) 天窗口" : "\(m / 1440)-day window" }
            if m % 60 == 0 { return isZh ? "\(m / 60) 小时窗口" : "\(m / 60)-hour window" }
            return isZh ? "\(m) 分钟窗口" : "\(m)-minute window"
        }
    }

    static func windowShortName(minutes: Int?) -> String {
        guard let m = minutes else { return isZh ? "未知" : "?" }
        switch m {
        case 300: return "5h"
        case 10080: return isZh ? "周" : "wk"
        case 60: return "1h"
        default:
            if m % 1440 == 0 { return "\(m / 1440)d" }
            if m % 60 == 0 { return "\(m / 60)h" }
            return "\(m)m"
        }
    }

    // MARK: - 状态徽标

    static var statusFresh: String { isZh ? "最新" : "Live" }
    static var statusStale: String { isZh ? "已过期" : "Stale" }
    static var statusNoData: String { isZh ? "暂未返回" : "No data" }
    static var staleDataHint: String { isZh ? "数据已过期（展示上次成功结果）" : "Stale (showing last successful reading)" }

    /// 数据新鲜度：刚刚更新 / N 分钟前更新 / N 小时前更新（分钟粒度，避免每秒跳动）
    static func freshnessText(since date: Date?, now: Date = Date()) -> String {
        guard let date else { return statusNoData }
        let secs = max(0, Int(now.timeIntervalSince(date)))
        if secs < 60 { return isZh ? "刚刚更新" : "Just updated" }
        let m = secs / 60
        if m < 60 { return isZh ? "\(m) 分钟前更新" : "\(m)m ago" }
        return isZh ? "\(m / 60) 小时前更新" : "\(m / 60)h ago"
    }

    // MARK: - 详情面板

    static var panelTitle: String { isZh ? "Codex 额度" : "Codex Quota" }
    static var noQuotaData: String { isZh ? "限额数据暂未返回" : "Quota data not available yet" }
    static var plan: String { isZh ? "套餐" : "Plan" }
    static var account: String { isZh ? "账号" : "Account" }
    static var lastSuccess: String { isZh ? "最后成功刷新" : "Last updated" }
    static var dataStatus: String { isZh ? "数据状态" : "Data status" }
    static var connection: String { isZh ? "连接" : "Connection" }
    static var cliVersion: String { isZh ? "CLI 版本" : "CLI version" }
    static var refreshNow: String { isZh ? "立即刷新" : "Refresh now" }
    static var quit: String { isZh ? "退出" : "Quit" }
    static var unknown: String { isZh ? "未知" : "Unknown" }
    static var notSignedIn: String { isZh ? "未登录" : "Not signed in" }
    static var signedIn: String { isZh ? "已登录" : "Signed in" }
    static var neverSucceeded: String { isZh ? "从未成功" : "Never" }
    static var connecting: String { isZh ? "连接中…" : "Connecting…" }
    static var connected: String { isZh ? "已连接" : "Connected" }

    static func disconnectedReconnecting(_ reason: String) -> String {
        isZh ? "断开：\(reason)（退避重连中）" : "Disconnected: \(reason) (reconnecting)"
    }

    static func remaining(_ pct: Int) -> String { isZh ? "剩余 \(pct)%" : "\(pct)% left" }
    static func used(_ pct: Int) -> String { isZh ? "已用 \(pct)%" : "\(pct)% used" }

    static func resetLine(countdown: String, local: String) -> String {
        isZh ? "重置：\(countdown)（\(local)）" : "Resets in \(countdown) (\(local))"
    }

    static var resetTimeUnavailable: String { isZh ? "重置时间暂未返回" : "Reset time unavailable" }

    // MARK: - 历史曲线

    static var historyTitle: String { isZh ? "历史曲线" : "History" }
    static var historyEmpty: String {
        isZh ? "暂无足够历史数据，App 运行后自动记录" : "Not enough history yet — samples are recorded automatically"
    }
    static var historyFooterHint: String {
        isZh ? "每 60 秒记录一次，数值变化立即记录（仅存本机）"
             : "Sampled every 60s, immediately on change (local only)"
    }
    static var range6Hours: String { isZh ? "6 小时" : "6h" }
    static var range24Hours: String { isZh ? "24 小时" : "24h" }
    static var range7Days: String { isZh ? "7 天" : "7d" }
    static var clearHistory: String { isZh ? "清除历史" : "Clear" }
    static var clearConfirm: String { isZh ? "确认清除？" : "Confirm?" }

    static func sampleCount(_ n: Int) -> String { isZh ? "\(n) 个采样点" : "\(n) samples" }

    /// 图表内部维度名（不直接显示，供无障碍与图例分组使用）
    static var chartPlotTime: String { isZh ? "时间" : "Time" }
    static var chartPlotRemaining: String { isZh ? "剩余" : "Remaining" }
    static var chartPlotWindow: String { isZh ? "窗口" : "Window" }

    /// X 轴时间标签：跨度 >1 天显示月/日，否则显示时:分
    static func chartAxisTime(_ date: Date, spanHours: Int) -> String {
        let f = DateFormatter()
        f.locale = isZh ? Locale(identifier: "zh_CN") : Locale(identifier: "en_US_POSIX")
        f.dateFormat = spanHours > 24 ? (isZh ? "M/d" : "MMM d") : "HH:mm"
        return f.string(from: date)
    }

    // MARK: - 时间

    static func countdownText(to date: Date, from now: Date = Date()) -> String {
        let secs = Int(date.timeIntervalSince(now))
        if secs <= 0 { return isZh ? "即将重置" : "resetting soon" }
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        if isZh {
            if h >= 24 { return "\(h / 24) 天 \(h % 24) 小时后" }
            if h > 0 { return "\(h) 小时 \(m) 分后" }
            if m > 0 { return "\(m) 分 \(s) 秒后" }
            return "\(s) 秒后"
        } else {
            if h >= 24 { return "\(h / 24)d \(h % 24)h" }
            if h > 0 { return "\(h)h \(m)m" }
            if m > 0 { return "\(m)m \(s)s" }
            return "\(s)s"
        }
    }

    static func localTimeText(_ date: Date) -> String {
        let f = DateFormatter()
        if isZh {
            f.locale = Locale(identifier: "zh_CN")
            f.dateFormat = "M月d日 HH:mm"
        } else {
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "MMM d, HH:mm"
        }
        return f.string(from: date)
    }

    static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    // MARK: - 客户端断连原因 / 错误

    static var reasonCLINotFound: String {
        isZh ? "未找到 codex CLI，请先安装并登录 Codex" : "codex CLI not found. Install Codex and sign in first."
    }

    static func reasonLaunchFailed(_ detail: String) -> String {
        isZh ? "App Server 启动失败：\(detail)" : "Failed to start app server: \(detail)"
    }

    static var reasonServerExited: String {
        isZh ? "App Server 已退出，等待重连" : "App server exited; reconnecting"
    }

    static var reasonRPCUnresponsive: String {
        isZh ? "RPC 无响应，重连中" : "RPC unresponsive; reconnecting"
    }

    static func reasonRequestTimeout(method: String, seconds: Int) -> String {
        isZh ? "请求超时（\(method)，\(seconds)s 无响应）" : "Request timed out (\(method), no response in \(seconds)s)"
    }

    static var reasonNoRateLimitData: String {
        isZh ? "响应中无限额数据" : "No rate-limit data in response"
    }

    static func reasonRPCError(context: String, message: String) -> String {
        isZh ? "RPC 错误（\(context)）：\(message)" : "RPC error (\(context)): \(message)"
    }

    /// 结构化错误 → 当前语言文案（渲染时调用，保证语言切换后可重译）
    static func text(for failure: QuotaFailure) -> String {
        switch failure {
        case .cliNotFound: return reasonCLINotFound
        case .launchFailed(let detail): return reasonLaunchFailed(detail)
        case .serverExited: return reasonServerExited
        case .rpcUnresponsive: return reasonRPCUnresponsive
        case .requestTimeout(let method, let seconds): return reasonRequestTimeout(method: method, seconds: seconds)
        case .noRateLimitData: return reasonNoRateLimitData
        case .rpcError(let context, let message): return reasonRPCError(context: context, message: message)
        }
    }
}
