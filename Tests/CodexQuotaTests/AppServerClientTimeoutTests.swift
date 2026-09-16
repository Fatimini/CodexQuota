import XCTest
@testable import CodexQuota

/// 请求超时集成测试：用假 App Server 脚本覆盖
/// 「子进程保持运行但始终不返回 RPC」的场景，不依赖 --probe 的 20s 兜底。
final class AppServerClientTimeoutTests: XCTestCase {

    private var tempScripts: [URL] = []

    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = .zh // 断言基于中文文案
    }

    override func tearDownWithError() throws {
        L10n.forcedLanguage = nil
        for url in tempScripts { try? FileManager.default.removeItem(at: url) }
        tempScripts.removeAll()
    }

    private func makeScript(_ body: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fake-appserver-\(UUID().uuidString).sh")
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        tempScripts.append(url)
        return url
    }

    /// 完全不应答的假 App Server：进程存活，永远不回任何 JSON
    func testAliveButSilentServerTriggersRequestTimeout() throws {
        let script = try makeScript("""
        #!/usr/bin/env python3
        import sys
        for line in sys.stdin:
            pass
        """)
        let client = AppServerClient(executableURL: script, requestTimeout: 2)

        let failedExp = expectation(description: "readFailed（请求超时）")
        failedExp.assertForOverFulfill = false
        let disconnectedExp = expectation(description: "disconnected（RPC 无响应重连）")
        disconnectedExp.assertForOverFulfill = false
        var timeoutFailure: QuotaFailure?

        client.onEvent = { event in
            switch event {
            case .readFailed(let failure):
                if case .requestTimeout = failure {
                    timeoutFailure = failure
                    failedExp.fulfill()
                }
            case .disconnected(let reason):
                if case .rpcUnresponsive = reason {
                    disconnectedExp.fulfill()
                }
            default:
                break
            }
        }
        client.start()
        wait(for: [failedExp, disconnectedExp], timeout: 15, enforceOrder: true)
        client.stop()

        XCTAssertEqual(timeoutFailure, .requestTimeout(method: "initialize", seconds: 2))
        // 渲染层翻译仍正确（中文环境）
        XCTAssertEqual(timeoutFailure.map { L10n.text(for: $0) }, "请求超时（initialize，2s 无响应）")
    }

    /// 应答一次后变哑的假 App Server：
    /// 先拿到新鲜快照，随后刷新请求超时 → 必须保旧并显示（已过期）
    func testServerRespondsOnceThenGoesSilent() throws {
        let script = try makeScript("""
        #!/usr/bin/env python3
        import sys, json
        responded = 0
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except Exception:
                continue
            rid = req.get("id"); m = req.get("method", "")
            if rid is None:
                continue
            if m == "initialize":
                resp = {"id": rid, "result": {"userAgent": "fake"}}
            elif m == "account/read":
                resp = {"id": rid, "result": {"account": {"type": "chatgpt", "email": "t@example.com", "planType": "plus"}, "requiresOpenaiAuth": True}}
            elif m == "account/rateLimits/read":
                responded += 1
                if responded > 1:
                    continue
                resp = {"id": rid, "result": {"rateLimits": {"limitId": "codex", "primary": {"usedPercent": 6, "windowDurationMins": 300, "resetsAt": 2000000000}, "secondary": {"usedPercent": 37, "windowDurationMins": 10080, "resetsAt": 2000000000}, "planType": "plus"}}}
            else:
                continue
            sys.stdout.write(json.dumps(resp) + "\\n")
            sys.stdout.flush()
        """)
        let client = AppServerClient(executableURL: script, requestTimeout: 2)

        var state = QuotaState()
        var freshTitle: String?
        var staleTitleOnTimeout: String?
        var staleTitleOnDisconnect: String?
        let snapshotExp = expectation(description: "拿到首个快照")
        let staleExp = expectation(description: "刷新超时后保旧标过期")
        staleExp.assertForOverFulfill = false
        let disconnectedExp = expectation(description: "随后断连仍保旧")
        disconnectedExp.assertForOverFulfill = false

        client.onEvent = { event in
            state = QuotaStateMachine.reduce(state, event)
            switch event {
            case .snapshot:
                freshTitle = QuotaFormatter.menuTitle(for: state)
                snapshotExp.fulfill()
                client.requestRefresh() // 第二次 read 将永远得不到响应
            case .readFailed(let failure):
                if case .requestTimeout = failure {
                    staleTitleOnTimeout = QuotaFormatter.menuTitle(for: state)
                    staleExp.fulfill()
                }
            case .disconnected(let reason):
                if case .rpcUnresponsive = reason {
                    staleTitleOnDisconnect = QuotaFormatter.menuTitle(for: state)
                    disconnectedExp.fulfill()
                }
            default:
                break
            }
        }
        client.start()
        wait(for: [snapshotExp, staleExp, disconnectedExp], timeout: 20, enforceOrder: true)
        client.stop()

        // 新鲜期：无（已过期）后缀
        XCTAssertEqual(freshTitle, "5h：94%｜周：63%")
        // 请求超时：保留上次成功数据并标注过期，不得显示「最新」或 0%
        XCTAssertEqual(staleTitleOnTimeout, "5h：94%｜周：63%（已过期）")
        // 断连：继续保旧
        XCTAssertEqual(staleTitleOnDisconnect, "5h：94%｜周：63%（已过期）")
        XCTAssertNotNil(state.snapshot)
        XCTAssertNotNil(state.lastSuccessAt)
    }

    /// stderr 压力：假 CLI 先写入远超管道缓冲区（约 512KB）的 stderr。
    /// 客户端必须持续消费，否则子进程阻塞在 stderr 写操作上，额度响应永远拿不到。
    func testHeavyStderrDoesNotBlockQuotaRead() throws {
        let script = try makeScript("""
        #!/usr/bin/env python3
        import sys, json
        chunk = "E" * 8192
        for _ in range(64):  # ≈512KB，远超 64KB 管道缓冲
            sys.stderr.write(chunk)
            sys.stderr.flush()
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                req = json.loads(line)
            except Exception:
                continue
            rid = req.get("id"); m = req.get("method", "")
            if rid is None:
                continue
            if m == "initialize":
                resp = {"id": rid, "result": {"userAgent": "fake"}}
            elif m == "account/read":
                resp = {"id": rid, "result": {"account": {"type": "chatgpt", "email": "t@example.com", "planType": "plus"}, "requiresOpenaiAuth": True}}
            elif m == "account/rateLimits/read":
                resp = {"id": rid, "result": {"rateLimits": {"limitId": "codex", "primary": {"usedPercent": 6, "windowDurationMins": 300, "resetsAt": 2000000000}, "secondary": {"usedPercent": 37, "windowDurationMins": 10080, "resetsAt": 2000000000}, "planType": "plus"}}}
            else:
                continue
            sys.stdout.write(json.dumps(resp) + "\\n")
            sys.stdout.flush()
        """)
        let client = AppServerClient(executableURL: script, requestTimeout: 5)

        let snapshotExp = expectation(description: "stderr 大量输出时仍能拿到快照")
        var state = QuotaState()
        var title: String?

        client.onEvent = { event in
            state = QuotaStateMachine.reduce(state, event)
            if case .snapshot = event {
                title = QuotaFormatter.menuTitle(for: state)
                snapshotExp.fulfill()
            }
        }
        client.start()
        wait(for: [snapshotExp], timeout: 15)
        client.stop()

        XCTAssertEqual(title, "5h：94%｜周：63%")
    }
}
