import Foundation

/// 单个限额窗口（如 5 小时窗 / 7 天窗）。
/// 窗口时长不做硬编码假设：按 windowDurationMins 动态换算展示名。
struct RateWindow: Equatable {
    var usedPercent: Int
    var windowDurationMins: Int?
    var resetsAt: Date?

    /// 剩余比例 = 100 - usedPercent
    var remainingPercent: Int { max(0, 100 - usedPercent) }

    /// 进度条显示值：与大数字「剩余」语义一致（条越满 = 额度越足）
    var progressValue: Double { Double(remainingPercent) }

    /// 告急阈值：剩余 ≤10% 时文字与进度条变红
    var isCritical: Bool { remainingPercent <= 10 }

    /// 详情面板名称（随系统语言）
    var displayName: String { L10n.windowName(minutes: windowDurationMins) }

    /// 菜单栏短名（随系统语言）
    var shortName: String { L10n.windowShortName(minutes: windowDurationMins) }
}

/// 一次成功读取的限额快照
struct RateLimitSnapshot: Equatable {
    var limitId: String?
    var primary: RateWindow?
    var secondary: RateWindow?
    var planType: String?
    var fetchedAt: Date

    var windows: [RateWindow] { [primary, secondary].compactMap { $0 } }
}

/// account/read 解析结果
struct AccountInfo: Equatable {
    var loggedIn: Bool
    var email: String?
    var planType: String?
    var requiresAuth: Bool
    var accountType: String?
}
