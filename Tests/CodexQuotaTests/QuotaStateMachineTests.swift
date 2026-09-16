import XCTest
@testable import CodexQuota

final class QuotaStateMachineTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = .zh // 断言基于中文文案
    }

    override func tearDown() {
        L10n.forcedLanguage = nil
        super.tearDown()
    }

    private func makeSnapshot(primaryUsed: Int = 97, secondaryUsed: Int = 35) -> RateLimitSnapshot {
        RateLimitSnapshot(
            limitId: "codex",
            primary: RateWindow(usedPercent: primaryUsed, windowDurationMins: 300,
                                resetsAt: Date().addingTimeInterval(3600)),
            secondary: RateWindow(usedPercent: secondaryUsed, windowDurationMins: 10080,
                                  resetsAt: Date().addingTimeInterval(86400)),
            planType: "plus",
            fetchedAt: Date()
        )
    }

    // 菜单栏标题：5h：3%｜周：65%
    func testMenuTitleNormal() {
        var s = QuotaState()
        s = QuotaStateMachine.reduce(s, .connected(cliVersion: "codex-cli 0.147.0"))
        s = QuotaStateMachine.reduce(s, .snapshot(makeSnapshot()))
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "5h：3%｜周：65%")
        XCTAssertEqual(s.dataStatus, .fresh)
    }

    // 读取失败：保留上次数据并标注过期，不得清零
    func testReadFailedKeepsSnapshotAndMarksStale() {
        var s = QuotaState()
        s = QuotaStateMachine.reduce(s, .connected(cliVersion: nil))
        s = QuotaStateMachine.reduce(s, .snapshot(makeSnapshot()))
        s = QuotaStateMachine.reduce(s, .readFailed(.rpcError(context: "test", message: "timeout")))
        XCTAssertNotNil(s.snapshot)
        XCTAssertEqual(s.dataStatus, .stale)
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "5h：3%｜周：65%（已过期）")
    }

    // 断连：保留旧数据标过期；恢复 + 新快照后回到最新
    func testDisconnectStaleThenRecover() {
        var s = QuotaState()
        s = QuotaStateMachine.reduce(s, .connected(cliVersion: nil))
        s = QuotaStateMachine.reduce(s, .snapshot(makeSnapshot()))
        s = QuotaStateMachine.reduce(s, .disconnected(reason: .serverExited))
        XCTAssertEqual(s.dataStatus, .stale)
        // 断连必须保旧：显示旧值 + （已过期），不得显示「离线」丢数据
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "5h：3%｜周：65%（已过期）")

        s = QuotaStateMachine.reduce(s, .connected(cliVersion: nil))
        s = QuotaStateMachine.reduce(s, .snapshot(makeSnapshot(primaryUsed: 50, secondaryUsed: 10)))
        XCTAssertEqual(s.dataStatus, .fresh)
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "5h：50%｜周：90%")
    }

    // 从未成功：显示「暂未返回」，不得显示 0%
    func testUnavailableWhenNoSnapshot() {
        var s = QuotaState()
        s = QuotaStateMachine.reduce(s, .connected(cliVersion: nil))
        XCTAssertEqual(s.dataStatus, .unavailable)
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "暂未返回")

        s = QuotaStateMachine.reduce(s, .readFailed(.noRateLimitData))
        XCTAssertEqual(s.dataStatus, .unavailable) // 没有旧数据可保
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "暂未返回")

        // 从未成功 + 断连：才显示「离线」
        s = QuotaStateMachine.reduce(s, .disconnected(reason: .serverExited))
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "离线")
    }

    // 空窗口快照（桶存在但窗口全 null）：显示「暂未返回」
    func testEmptyWindowsSnapshot() {
        var s = QuotaState()
        s = QuotaStateMachine.reduce(s, .connected(cliVersion: nil))
        let empty = RateLimitSnapshot(limitId: "codex", primary: nil, secondary: nil,
                                      planType: nil, fetchedAt: Date())
        s = QuotaStateMachine.reduce(s, .snapshot(empty))
        XCTAssertEqual(QuotaFormatter.menuTitle(for: s), "暂未返回")
    }

    // 邮箱打码
    func testMaskEmail() {
        XCTAssertEqual(QuotaFormatter.maskEmail("abcdef@example.com"), "ab***@example.com")
        XCTAssertEqual(QuotaFormatter.maskEmail("ab@x.com"), "ab***@x.com")
        XCTAssertNil(QuotaFormatter.maskEmail(nil))
    }

    // 倒计时文本
    func testCountdownText() {
        let now = Date()
        XCTAssertEqual(QuotaFormatter.countdownText(to: now.addingTimeInterval(2 * 3600 + 13 * 60), from: now), "2 小时 13 分后")
        XCTAssertEqual(QuotaFormatter.countdownText(to: now.addingTimeInterval(26 * 3600), from: now), "1 天 2 小时后")
        XCTAssertEqual(QuotaFormatter.countdownText(to: now.addingTimeInterval(-5), from: now), "即将重置")
    }

    // 进度条显示「剩余」，与大数字语义一致；告急阈值 ≤10%
    func testProgressValueMatchesRemaining() {
        let w = RateWindow(usedPercent: 14, windowDurationMins: 300, resetsAt: nil)
        XCTAssertEqual(w.remainingPercent, 86)
        XCTAssertEqual(w.progressValue, 86)
        XCTAssertFalse(w.isCritical)

        XCTAssertTrue(RateWindow(usedPercent: 90, windowDurationMins: 300).isCritical)  // 剩 10%
        XCTAssertTrue(RateWindow(usedPercent: 97, windowDurationMins: 300).isCritical)  // 剩 3%
        XCTAssertFalse(RateWindow(usedPercent: 89, windowDurationMins: 300).isCritical) // 剩 11%
    }

    // 数据新鲜度文案（中文）
    func testFreshnessTextZh() {
        let now = Date()
        XCTAssertEqual(L10n.freshnessText(since: now.addingTimeInterval(-30), now: now), "刚刚更新")
        XCTAssertEqual(L10n.freshnessText(since: now.addingTimeInterval(-59), now: now), "刚刚更新")
        XCTAssertEqual(L10n.freshnessText(since: now.addingTimeInterval(-60), now: now), "1 分钟前更新")
        XCTAssertEqual(L10n.freshnessText(since: now.addingTimeInterval(-5 * 60), now: now), "5 分钟前更新")
        XCTAssertEqual(L10n.freshnessText(since: now.addingTimeInterval(-2 * 3600), now: now), "2 小时前更新")
        XCTAssertEqual(L10n.freshnessText(since: nil, now: now), "暂未返回")
    }

    // 套餐信息可从快照回填
    func testPlanFromSnapshot() {
        var s = QuotaState()
        s = QuotaStateMachine.reduce(s, .snapshot(makeSnapshot()))
        XCTAssertEqual(s.snapshot?.planType, "plus")
        XCTAssertEqual(s.lastFailure, nil)
        XCTAssertNotNil(s.lastSuccessAt)
    }
}
