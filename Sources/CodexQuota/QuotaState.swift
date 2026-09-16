import Foundation

/// 连接/读取错误的结构化描述。
/// 状态层只存「错误类型＋参数」，不存译文；语言切换后由渲染层重新翻译。
enum QuotaFailure: Equatable {
    case cliNotFound
    case launchFailed(detail: String)
    case serverExited
    case rpcUnresponsive
    case requestTimeout(method: String, seconds: Int)
    case noRateLimitData
    case rpcError(context: String, message: String)
}

/// 客户端 → 视图层的事件
enum QuotaEvent {
    case connected(cliVersion: String?)
    case disconnected(reason: QuotaFailure)
    case cliVersion(String)
    case account(AccountInfo)
    case snapshot(RateLimitSnapshot)
    case readFailed(QuotaFailure)
}

enum ConnectionState: Equatable {
    case connecting
    case connected
    case disconnected(QuotaFailure)
}

enum DataStatus: Equatable {
    case fresh        // 最新
    case stale        // 已过期：保留上次成功数据并明确标注
    case unavailable  // 从未成功读取，显示「暂未返回」
}

struct QuotaState: Equatable {
    var connection: ConnectionState = .connecting
    var snapshot: RateLimitSnapshot?
    var lastSuccessAt: Date?
    var lastFailure: QuotaFailure?
    var account: AccountInfo?
    var cliVersion: String?

    var dataStatus: DataStatus {
        guard snapshot != nil else { return .unavailable }
        if lastFailure != nil { return .stale }
        if case .disconnected = connection { return .stale }
        return .fresh
    }
}

/// 纯函数状态机：失败保留旧快照、成功清除失败标记
enum QuotaStateMachine {
    static func reduce(_ state: QuotaState, _ event: QuotaEvent) -> QuotaState {
        var s = state
        switch event {
        case .connected(let version):
            s.connection = .connected
            if let version { s.cliVersion = version }
        case .cliVersion(let version):
            s.cliVersion = version
        case .disconnected(let reason):
            s.connection = .disconnected(reason)
        case .account(let info):
            s.account = info
        case .snapshot(let snap):
            s.snapshot = snap
            s.lastSuccessAt = snap.fetchedAt
            s.lastFailure = nil
        case .readFailed(let failure):
            s.lastFailure = failure
        }
        return s
    }
}

enum QuotaFormatter {

    /// 菜单栏标题：5h：xx%｜周：xx%（图标为 SF Symbol `timer`，由 label 单独渲染）
    /// 有历史快照时，断连/失败也必须保旧并标注（已过期）；
    /// 只有从未成功读取过才显示「离线」「暂未返回」。文案随系统语言。
    static func menuTitle(for state: QuotaState) -> String {
        guard let snap = state.snapshot, !snap.windows.isEmpty else {
            if case .disconnected = state.connection { return L10n.menuOffline }
            return L10n.menuNoData
        }
        var title = snap.windows
            .map { "\($0.shortName)\(L10n.labelColon)\($0.remainingPercent)%" }
            .joined(separator: L10n.listSeparator)
        if state.dataStatus == .stale { title += L10n.staleSuffix }
        return title
    }

    static func dataStatusText(_ status: DataStatus) -> String {
        switch status {
        case .fresh: return L10n.statusFresh
        case .stale: return L10n.staleDataHint
        case .unavailable: return L10n.statusNoData
        }
    }

    /// 连接状态文案（渲染时翻译，语言切换后已有状态也能完整重译）
    static func connectionText(for state: QuotaState) -> String {
        switch state.connection {
        case .connecting: return L10n.connecting
        case .connected: return L10n.connected
        case .disconnected(let reason): return L10n.disconnectedReconnecting(L10n.text(for: reason))
        }
    }

    /// 邮箱打码：ab***@example.com
    static func maskEmail(_ email: String?) -> String? {
        guard let email, let at = email.firstIndex(of: "@") else { return email }
        let name = email[..<at]
        let domain = email[at...]
        return "\(name.prefix(2))***\(domain)"
    }

    static func countdownText(to date: Date, from now: Date = Date()) -> String {
        L10n.countdownText(to: date, from: now)
    }

    static func localTimeText(_ date: Date) -> String {
        L10n.localTimeText(date)
    }

    static func timeText(_ date: Date) -> String {
        L10n.timeText(date)
    }
}
