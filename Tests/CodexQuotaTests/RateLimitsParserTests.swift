import XCTest
@testable import CodexQuota

final class RateLimitsParserTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = .zh // 断言基于中文文案
    }

    override func tearDown() {
        L10n.forcedLanguage = nil
        super.tearDown()
    }

    private func resultDict(_ json: String) -> [String: Any] {
        let obj = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        return obj["result"] as! [String: Any]
    }

    // 真实账号响应形态：双窗口（5h 97% / 7d 35%）
    func testTwoWindowsRealShape() {
        let result = resultDict("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex","limitName":null,
          "primary":{"usedPercent":97,"windowDurationMins":300,"resetsAt":1788933178},
          "secondary":{"usedPercent":35,"windowDurationMins":10080,"resetsAt":1789452678},
          "planType":"plus"},
          "rateLimitsByLimitId":{"codex":{"limitId":"codex",
            "primary":{"usedPercent":97,"windowDurationMins":300,"resetsAt":1788933178},
            "secondary":{"usedPercent":35,"windowDurationMins":10080,"resetsAt":1789452678},
            "planType":"plus"}}}}
        """)
        let snap = RateLimitsParser.snapshot(fromResult: result)
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.windows.count, 2)
        XCTAssertEqual(snap?.primary?.usedPercent, 97)
        XCTAssertEqual(snap?.primary?.remainingPercent, 3)
        XCTAssertEqual(snap?.secondary?.remainingPercent, 65)
        XCTAssertEqual(snap?.primary?.displayName, "5 小时窗口")
        XCTAssertEqual(snap?.secondary?.displayName, "7 天（周）窗口")
        XCTAssertEqual(snap?.primary?.resetsAt, Date(timeIntervalSince1970: 1788933178))
        XCTAssertEqual(snap?.planType, "plus")
    }

    // 只返回一个窗口：不得编造第二个
    func testOnlyPrimaryWindow() {
        let result = resultDict("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex",
          "primary":{"usedPercent":42,"windowDurationMins":300,"resetsAt":1788933178},
          "secondary":null}}}
        """)
        let snap = RateLimitsParser.snapshot(fromResult: result)
        XCTAssertEqual(snap?.windows.count, 1)
        XCTAssertNil(snap?.secondary)
        XCTAssertEqual(snap?.primary?.remainingPercent, 58)
    }

    // 两个窗口都为 null：快照有效但无窗口（显示「暂未返回」，不得显示 0%）
    func testBothWindowsNull() {
        let result = resultDict("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex","primary":null,"secondary":null}}}
        """)
        let snap = RateLimitsParser.snapshot(fromResult: result)
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.windows.count, 0)
    }

    // 响应里完全没有限额桶：返回 nil，按读取失败处理
    func testNoBucketAtAll() {
        let result = resultDict(#"{"id":3,"result":{}}"#)
        XCTAssertNil(RateLimitsParser.snapshot(fromResult: result))
    }

    // 优先读 rateLimitsByLimitId.codex，回退 rateLimits
    func testPrefersByLimitId() {
        let result = resultDict("""
        {"id":3,"result":{
          "rateLimits":{"limitId":"codex","primary":{"usedPercent":10,"windowDurationMins":300}},
          "rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":99,"windowDurationMins":300}}}}}
        """)
        let snap = RateLimitsParser.snapshot(fromResult: result)
        XCTAssertEqual(snap?.primary?.usedPercent, 99)
    }

    // 未知窗口时长：动态换算，不得错误归类为 5 小时或周
    func testUnknownWindowDurations() {
        XCTAssertEqual(RateWindow(usedPercent: 1, windowDurationMins: 15).displayName, "15 分钟窗口")
        XCTAssertEqual(RateWindow(usedPercent: 1, windowDurationMins: 120).displayName, "2 小时窗口")
        XCTAssertEqual(RateWindow(usedPercent: 1, windowDurationMins: 2880).displayName, "2 天窗口")
        XCTAssertEqual(RateWindow(usedPercent: 1, windowDurationMins: nil).displayName, "未知窗口")
        XCTAssertEqual(RateWindow(usedPercent: 1, windowDurationMins: 15).shortName, "15m")
        XCTAssertEqual(RateWindow(usedPercent: 1, windowDurationMins: 120).shortName, "2h")
    }

    // usedPercent 为 Double 时容错解析
    func testDoubleUsedPercent() {
        let result = resultDict("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex",
          "primary":{"usedPercent":97.0,"windowDurationMins":300}}}}
        """)
        XCTAssertEqual(RateLimitsParser.snapshot(fromResult: result)?.primary?.usedPercent, 97)
    }

    // MARK: - 数值边界（不编造额度：非法值一律不显示，不截断、不猜测）

    // Bool 不得被当成 1：JSON true 是 NSNumber，曾会显示成「已用 1%、剩余 99%」
    func testBoolUsedPercentIsRejected() {
        let result = resultDict("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex",
          "primary":{"usedPercent":true,"windowDurationMins":300,"resetsAt":1788933178}}}}
        """)
        let snap = RateLimitsParser.snapshot(fromResult: result)
        XCTAssertNil(snap?.primary)
        XCTAssertEqual(snap?.windows.count, 0)
    }

    // Bool 同样不得污染 resetsAt / windowDurationMins：按缺失处理（不得出现 1970 年或 1 分钟窗口）
    func testBoolResetsAtAndWindowMinsTreatedAsMissing() {
        let result = resultDict("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex",
          "primary":{"usedPercent":40,"windowDurationMins":true,"resetsAt":true}}}}
        """)
        let snap = RateLimitsParser.snapshot(fromResult: result)
        XCTAssertEqual(snap?.primary?.usedPercent, 40)
        XCTAssertNil(snap?.primary?.resetsAt)
        XCTAssertNil(snap?.primary?.windowDurationMins)
        XCTAssertEqual(snap?.primary?.displayName, "未知窗口")
    }

    // 小数百分比：拒绝，不静默截断为 12
    func testFractionalUsedPercentIsRejected() {
        let result = resultDict("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex",
          "primary":{"usedPercent":12.5,"windowDurationMins":300}}}}
        """)
        XCTAssertNil(RateLimitsParser.snapshot(fromResult: result)?.primary)
    }

    // 整数值的小数写法（25.0）与 25 等价，应接受
    func testIntegralDoubleUsedPercentAccepted() {
        let result = resultDict("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex",
          "primary":{"usedPercent":25.0,"windowDurationMins":300}}}}
        """)
        XCTAssertEqual(RateLimitsParser.snapshot(fromResult: result)?.primary?.usedPercent, 25)
    }

    // 越界：-1 / 101 均拒绝（不得显示 101% 或静默变成 0%）
    func testOutOfRangeUsedPercentRejected() {
        for raw in ["-1", "101"] {
            let result = resultDict("""
            {"id":3,"result":{"rateLimits":{"limitId":"codex",
              "primary":{"usedPercent":\(raw),"windowDurationMins":300}}}}
            """)
            XCTAssertNil(RateLimitsParser.snapshot(fromResult: result)?.primary,
                         "usedPercent=\(raw) 应被拒绝")
        }
    }

    // 窗口时长非正数：按未知窗口处理
    func testNonPositiveWindowDurationTreatedAsUnknown() {
        let result = resultDict("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex",
          "primary":{"usedPercent":40,"windowDurationMins":0}}}}
        """)
        XCTAssertEqual(RateLimitsParser.snapshot(fromResult: result)?.primary?.displayName, "未知窗口")
    }

    // 超大有限数：Int(d) 越界会 trap（菜单栏 App 崩溃），必须拒绝而不是转换
    func testHugeNumberRejectedInsteadOfCrashing() {
        for raw in ["1e30", "9.3e18"] {
            let result = resultDict("""
            {"id":3,"result":{"rateLimits":{"limitId":"codex",
              "primary":{"usedPercent":\(raw),"windowDurationMins":300}}}}
            """)
            XCTAssertNil(RateLimitsParser.snapshot(fromResult: result)?.primary,
                         "\(raw) 应被拒绝，不得触发整数溢出崩溃")
        }
    }

    // 非整数时间戳：按缺失处理
    func testNonIntegerResetsAtTreatedAsMissing() {
        let result = resultDict("""
        {"id":3,"result":{"rateLimits":{"limitId":"codex",
          "primary":{"usedPercent":40,"windowDurationMins":300,"resetsAt":1788933178.5}}}}
        """)
        XCTAssertNil(RateLimitsParser.snapshot(fromResult: result)?.primary?.resetsAt)
    }

    // 已登录账号
    func testAccountLoggedIn() {
        let result = resultDict("""
        {"id":2,"result":{"account":{"type":"chatgpt","email":"abc@example.com","planType":"plus"},
          "requiresOpenaiAuth":true}}
        """)
        let info = RateLimitsParser.account(fromResult: result)
        XCTAssertTrue(info.loggedIn)
        XCTAssertEqual(info.email, "abc@example.com")
        XCTAssertEqual(info.planType, "plus")
        XCTAssertEqual(info.accountType, "chatgpt")
    }

    // 未登录：account 为 null
    func testAccountLoggedOut() {
        let result = resultDict(#"{"id":2,"result":{"account":null,"requiresOpenaiAuth":true}}"#)
        let info = RateLimitsParser.account(fromResult: result)
        XCTAssertFalse(info.loggedIn)
        XCTAssertNil(info.email)
        XCTAssertTrue(info.requiresAuth)
    }
}
