import XCTest
@testable import CodexQuota

/// 版本来源验收：打包后 App 的 `clientInfo.version` 必须与注入版本一致，而不是写死的旧值。
final class AppVersionTests: XCTestCase {

    private var tempItems: [URL] = []
    private let originalProvider = AppVersion.bundleProvider

    override func tearDown() {
        AppVersion.bundleProvider = originalProvider
        for url in tempItems { try? FileManager.default.removeItem(at: url) }
        tempItems = []
        super.tearDown()
    }

    // MARK: - Helpers

    /// 构造只含 Info.plist 的临时 bundle，模拟打包后的 .app
    private func makeBundle(version: String) throws -> Bundle {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FakeApp-\(UUID().uuidString).app")
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        tempItems.append(root)
        return try XCTUnwrap(Bundle(path: root.path))
    }

    private func makeScript(_ body: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fake-appserver-\(UUID().uuidString).sh")
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        tempItems.append(url)
        return url
    }

    // MARK: - 版本取值

    func testVersionReadFromBundleInfoPlist() throws {
        AppVersion.bundleProvider = { try! self.makeBundle(version: "1.1.1") }
        XCTAssertEqual(AppVersion.current, "1.1.1")
    }

    func testFallbackWhenBundleHasNoInfoPlist() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Empty-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        tempItems.append(root)
        let bundle = try XCTUnwrap(Bundle(path: root.path))
        AppVersion.bundleProvider = { bundle }
        XCTAssertEqual(AppVersion.current, AppVersion.fallback)
    }

    // MARK: - 端到端：真正发出去的 clientInfo

    /// 用假 App Server 捕获 initialize 请求，断言实际发出的版本号来自 AppVersion
    func testClientInfoVersionSentToAppServer() throws {
        let bundle = try makeBundle(version: "1.1.1")
        AppVersion.bundleProvider = { bundle }

        let logURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("initialize-\(UUID().uuidString).log")
        tempItems.append(logURL)

        let script = try makeScript("""
        #!/usr/bin/env python3
        import sys, json
        log = "\(logURL.path)"
        open(log, "w").close()
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
                with open(log, "a") as f:
                    f.write(line + "\\n")
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
        client.start()

        // 轮询等待 initialize 落盘（假 server 为同步脚本，无需长等待）
        var captured: [String: Any]?
        for _ in 0..<100 {
            if let data = try? Data(contentsOf: logURL), !data.isEmpty,
               let line = String(data: data, encoding: .utf8)?.components(separatedBy: "\n").first,
               !line.isEmpty,
               let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] {
                captured = obj
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        client.stop()

        let request = try XCTUnwrap(captured, "未捕获到 initialize 请求")
        let params = try XCTUnwrap(request["params"] as? [String: Any])
        let clientInfo = try XCTUnwrap(params["clientInfo"] as? [String: Any])
        XCTAssertEqual(clientInfo["version"] as? String, "1.1.1",
                       "App Server 收到的 clientInfo.version 必须来自单一版本来源")
        XCTAssertNotEqual(clientInfo["version"] as? String, "1.0.0")
    }
}
