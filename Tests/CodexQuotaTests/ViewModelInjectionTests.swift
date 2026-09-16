import XCTest
@testable import CodexQuota

/// 模拟客户端：不碰真实进程，验证 ViewModel 通过依赖注入正确响应事件
final class MockQuotaClient: QuotaClientProtocol {
    var onEvent: ((QuotaEvent) -> Void)?
    private(set) var refreshCount = 0
    private(set) var started = false

    func start() { started = true }
    func stop() {}
    func requestRefresh() { refreshCount += 1 }

    func emit(_ event: QuotaEvent) { onEvent?(event) }
}

@MainActor
final class ViewModelInjectionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.forcedLanguage = .zh // 断言基于中文文案
    }

    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs = []
        L10n.forcedLanguage = nil
        super.tearDown()
    }

    /// 历史落到临时目录，避免单测污染/依赖真实历史文件
    private func makeHistory() -> HistoryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexQuotaVM-\(UUID().uuidString)", isDirectory: true)
        tempDirs.append(dir)
        return HistoryStore(fileURL: dir.appendingPathComponent("history.json"))
    }

    private func makeVM() -> (QuotaViewModel, MockQuotaClient) {
        let mock = MockQuotaClient()
        let vm = QuotaViewModel(client: mock, refreshInterval: 3600, history: makeHistory())
        return (vm, mock)
    }

    private func waitForMainActor() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func testSnapshotFlow() async {
        let (vm, mock) = makeVM()
        vm.start()
        XCTAssertTrue(mock.started)

        mock.emit(.connected(cliVersion: "codex-cli 0.147.0"))
        mock.emit(.account(AccountInfo(loggedIn: true, email: "abc@example.com",
                                       planType: "plus", requiresAuth: true, accountType: "chatgpt")))
        mock.emit(.snapshot(RateLimitSnapshot(
            limitId: "codex",
            primary: RateWindow(usedPercent: 97, windowDurationMins: 300, resetsAt: nil),
            secondary: RateWindow(usedPercent: 35, windowDurationMins: 10080, resetsAt: nil),
            planType: "plus", fetchedAt: Date())))
        await waitForMainActor()

        XCTAssertEqual(vm.menuTitle, "5h：3%｜周：65%")
        XCTAssertEqual(vm.state.cliVersion, "codex-cli 0.147.0")
        XCTAssertEqual(vm.state.account?.loggedIn, true)

        vm.refresh()
        XCTAssertEqual(mock.refreshCount, 1)
    }

    func testSnapshotRecordedIntoHistory() async {
        let (vm, mock) = makeVM()
        mock.emit(.snapshot(RateLimitSnapshot(
            limitId: "codex",
            primary: RateWindow(usedPercent: 97, windowDurationMins: 300, resetsAt: nil),
            secondary: RateWindow(usedPercent: 35, windowDurationMins: 10080, resetsAt: nil),
            planType: "plus", fetchedAt: Date())))
        await waitForMainActor()

        XCTAssertEqual(vm.history.entries.count, 1)
        XCTAssertEqual(vm.history.samples(windowDurationMins: 300, since: .distantPast).first?.remainingPercent, 3)
        XCTAssertEqual(vm.history.samples(windowDurationMins: 10080, since: .distantPast).first?.remainingPercent, 65)
    }

    func testFailureKeepsOldData() async {
        let (vm, mock) = makeVM()
        mock.emit(.connected(cliVersion: nil))
        mock.emit(.snapshot(RateLimitSnapshot(
            limitId: "codex",
            primary: RateWindow(usedPercent: 10, windowDurationMins: 300, resetsAt: nil),
            secondary: nil, planType: nil, fetchedAt: Date())))
        await waitForMainActor()
        XCTAssertEqual(vm.menuTitle, "5h：90%")

        mock.emit(.disconnected(reason: .serverExited))
        await waitForMainActor()
        XCTAssertEqual(vm.menuTitle, "5h：90%（已过期）") // 断连保旧
        XCTAssertEqual(vm.state.dataStatus, .stale)
    }

    func testLoggedOutAccountDisplayed() async {
        let (vm, mock) = makeVM()
        mock.emit(.account(AccountInfo(loggedIn: false, email: nil,
                                       planType: nil, requiresAuth: true, accountType: nil)))
        await waitForMainActor()
        XCTAssertEqual(vm.state.account?.loggedIn, false)
        XCTAssertEqual(vm.state.dataStatus, .unavailable)
        XCTAssertEqual(vm.menuTitle, "暂未返回")
    }
}
