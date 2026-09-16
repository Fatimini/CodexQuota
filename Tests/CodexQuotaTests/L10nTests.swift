import XCTest
@testable import CodexQuota

/// 英文文案测试：强制英文，验证菜单栏与窗口名称的英文形态
final class L10nTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = .en
    }

    override func tearDown() {
        L10n.forcedLanguage = nil
        super.tearDown()
    }

    private func makeSnapshot() -> RateLimitSnapshot {
        RateLimitSnapshot(
            limitId: "codex",
            primary: RateWindow(usedPercent: 97, windowDurationMins: 300, resetsAt: nil),
            secondary: RateWindow(usedPercent: 35, windowDurationMins: 10080, resetsAt: nil),
            planType: "plus",
            fetchedAt: Date()
        )
    }

    func testEnglishMenuTitleFresh() {
        var s = QuotaState()
        s = QuotaStateMachine.reduce(s, .connected(cliVersion: nil))
        s = QuotaStateMachine.reduce(s, .snapshot(makeSnapshot()))
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "5h: 3% | wk: 65%")
    }

    func testEnglishMenuTitleStale() {
        var s = QuotaState()
        s = QuotaStateMachine.reduce(s, .connected(cliVersion: nil))
        s = QuotaStateMachine.reduce(s, .snapshot(makeSnapshot()))
        s = QuotaStateMachine.reduce(s, .readFailed(.requestTimeout(method: "test", seconds: 1)))
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "5h: 3% | wk: 65% (stale)")
    }

    func testEnglishOfflineAndNoData() {
        var s = QuotaState()
        s = QuotaStateMachine.reduce(s, .connected(cliVersion: nil))
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "No data")
        s = QuotaStateMachine.reduce(s, .disconnected(reason: .serverExited))
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "Offline")
    }

    func testEnglishWindowNames() {
        XCTAssertEqual(RateWindow(usedPercent: 1, windowDurationMins: 300).displayName, "5-hour window")
        XCTAssertEqual(RateWindow(usedPercent: 1, windowDurationMins: 10080).displayName, "7-day (weekly) window")
        XCTAssertEqual(RateWindow(usedPercent: 1, windowDurationMins: 15).displayName, "15-minute window")
        XCTAssertEqual(RateWindow(usedPercent: 1, windowDurationMins: 10080).shortName, "wk")
        XCTAssertEqual(RateWindow(usedPercent: 1, windowDurationMins: nil).displayName, "Unknown window")
    }

    func testEnglishCountdown() {
        let now = Date()
        XCTAssertEqual(L10n.countdownText(to: now.addingTimeInterval(2 * 3600 + 13 * 60), from: now), "2h 13m")
        XCTAssertEqual(L10n.countdownText(to: now.addingTimeInterval(26 * 3600), from: now), "1d 2h")
        XCTAssertEqual(L10n.countdownText(to: now.addingTimeInterval(-5), from: now), "resetting soon")
    }

    func testEnglishStatusAndReasons() {
        XCTAssertEqual(L10n.statusFresh, "Live")
        XCTAssertEqual(L10n.reasonRequestTimeout(method: "initialize", seconds: 2),
                       "Request timed out (initialize, no response in 2s)")
        XCTAssertEqual(L10n.disconnectedReconnecting("RPC unresponsive; reconnecting"),
                       "Disconnected: RPC unresponsive; reconnecting (reconnecting)")
    }

    // 数据新鲜度文案（英文）
    func testFreshnessTextEn() {
        let now = Date()
        XCTAssertEqual(L10n.freshnessText(since: now.addingTimeInterval(-30), now: now), "Just updated")
        XCTAssertEqual(L10n.freshnessText(since: now.addingTimeInterval(-5 * 60), now: now), "5m ago")
        XCTAssertEqual(L10n.freshnessText(since: now.addingTimeInterval(-2 * 3600), now: now), "2h ago")
        XCTAssertEqual(L10n.freshnessText(since: nil, now: now), "No data")
    }

    /// P2 回归：同一份断连状态，切换语言后连接文案必须完整重译
    func testDisconnectedReasonFollowsLanguageSwitch() {
        var s = QuotaState()

        L10n.forcedLanguage = .zh
        s = QuotaStateMachine.reduce(s, .disconnected(reason: .serverExited))
        XCTAssertEqual(QuotaFormatter.connectionText(for: s),
                       "断开：App Server 已退出，等待重连（退避重连中）")

        L10n.forcedLanguage = .en
        XCTAssertEqual(QuotaFormatter.connectionText(for: s),
                       "Disconnected: App server exited; reconnecting (reconnecting)")

        L10n.forcedLanguage = .zh
        XCTAssertEqual(QuotaFormatter.connectionText(for: s),
                       "断开：App Server 已退出，等待重连（退避重连中）")
    }

    /// P2 回归：读取失败原因同样可重译
    func testReadFailureReasonFollowsLanguageSwitch() {
        let failure = QuotaFailure.requestTimeout(method: "account/rateLimits/read", seconds: 10)
        L10n.forcedLanguage = .zh
        XCTAssertEqual(L10n.text(for: failure), "请求超时（account/rateLimits/read，10s 无响应）")
        L10n.forcedLanguage = .en
        XCTAssertEqual(L10n.text(for: failure), "Request timed out (account/rateLimits/read, no response in 10s)")
    }
}
