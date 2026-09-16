import XCTest
@testable import CodexQuota

/// 探针输出的隐私收口：探针结果常被贴进 Issue 或聊天记录，
/// 不得包含本机绝对路径、用户名或完整邮箱。
final class ProbeRunnerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = .zh // 断言基于中文文案
    }

    override func tearDown() {
        L10n.forcedLanguage = nil
        super.tearDown()
    }

    private func makeSnapshot() -> RateLimitSnapshot {
        RateLimitSnapshot(
            limitId: "codex",
            primary: RateWindow(usedPercent: 90, windowDurationMins: 300, resetsAt: Date(timeIntervalSince1970: 1_800_000_000)),
            secondary: RateWindow(usedPercent: 79, windowDurationMins: 10080, resetsAt: nil),
            planType: "plus",
            fetchedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func text(of report: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    func testReportOnlyKeepsExecutableName() {
        let report = ProbeRunner.makeReport(
            codexPath: "/Users/someone/.local/bin/codex",
            cliVersion: "codex-cli 0.147.0",
            account: nil,
            snapshot: makeSnapshot())

        XCTAssertEqual(report["codex可执行文件"] as? String, "codex")

        let text = text(of: report)
        XCTAssertFalse(text.contains("/Users/"), "探针输出不得包含绝对路径：\(text)")
        XCTAssertFalse(text.contains("someone"), "探针输出不得包含用户名：\(text)")
    }

    func testReportKeepsFileNameForOtherLocations() {
        let report = ProbeRunner.makeReport(
            codexPath: "/opt/homebrew/bin/codex",
            cliVersion: nil,
            account: nil,
            snapshot: makeSnapshot())
        XCTAssertEqual(report["codex可执行文件"] as? String, "codex")
        XCTAssertFalse(text(of: report).contains("/opt/"))
    }

    func testReportMasksAccountEmail() {
        let report = ProbeRunner.makeReport(
            codexPath: "/usr/local/bin/codex",
            cliVersion: nil,
            account: AccountInfo(loggedIn: true, email: "abcdef@example.com", planType: "plus",
                                 requiresAuth: true, accountType: "chatgpt"),
            snapshot: makeSnapshot())

        XCTAssertEqual(report["账号"] as? String, "ab***@example.com")
        let text = text(of: report)
        XCTAssertFalse(text.contains("abcdef@"), "探针输出不得包含完整邮箱：\(text)")
    }
}
