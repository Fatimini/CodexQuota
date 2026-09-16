import Foundation

/// 数据层抽象：便于测试注入模拟客户端
protocol QuotaClientProtocol: AnyObject {
    var onEvent: ((QuotaEvent) -> Void)? { get set }
    func start()
    func stop()
    func requestRefresh()
}

/// Codex App Server 长连接客户端。
///
/// - 启动时拉起一个长期运行的 `codex app-server` 子进程（stdio JSON-RPC）；
/// - 崩溃后退避重连 1s → 2s → 5s → 30s（之后保持 30s），恢复后立即全量读取；
/// - 收到 account/rateLimits/updated 通知时仅作为触发信号，回源 read 取全量；
/// - 不读取 auth.json / Cookie / Token，认证全部由 Codex CLI 自持。
final class AppServerClient: QuotaClientProtocol {

    var onEvent: ((QuotaEvent) -> Void)?

    private static let backoffSchedule: [TimeInterval] = [1, 2, 5, 30]

    private let queue = DispatchQueue(label: "codexquota.appserver")
    private let executableURL: URL?
    private var process: Process?
    private var outHandle: FileHandle?
    private var inHandle: FileHandle?
    private var errHandle: FileHandle?
    private var readBuffer = Data()
    private var nextRequestId = 1
    private var pendingMethods: [Int: String] = [:]
    private var stopped = true
    private var retryCount = 0
    private var cliVersion: String?
    /// 每个 JSON-RPC 请求的响应超时（秒）；子进程存活但不应答时触发
    private let requestTimeout: TimeInterval

    init(executableURL: URL? = AppServerClient.locateCodex(), requestTimeout: TimeInterval = 10) {
        self.executableURL = executableURL
        self.requestTimeout = requestTimeout
    }

    /// 在常见安装位置与 PATH 中查找 codex CLI（GUI 应用 PATH 受限，须显式探测）
    static func locateCodex(fileManager: FileManager = .default,
                            environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var candidates = [
            NSHomeDirectory() + "/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
        ]
        if let pathEnv = environment["PATH"] {
            candidates += pathEnv.split(separator: ":").map { String($0) + "/codex" }
        }
        for path in candidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    // MARK: - QuotaClientProtocol

    func start() {
        queue.async {
            guard self.stopped else { return }
            self.stopped = false
            self.retryCount = 0
            self.launch()
        }
    }

    func stop() {
        queue.async {
            self.stopped = true
            self.teardown()
        }
    }

    func requestRefresh() {
        queue.async {
            if self.process != nil {
                self.sendRateLimitsRead()
            } else if !self.stopped {
                self.retryCount = 0
                self.launch()
            }
        }
    }

    // MARK: - 进程生命周期

    private func launch() {
        guard !stopped, process == nil else { return }
        guard let executableURL else {
            emit(.disconnected(reason: .cliNotFound))
            scheduleRetry()
            return
        }
        let p = Process()
        p.executableURL = executableURL
        p.arguments = ["app-server"]
        let out = Pipe()
        let input = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardInput = input
        p.standardError = err
        p.terminationHandler = { [weak self] _ in
            self?.queue.async { self?.handleTermination() }
        }
        do {
            try p.run()
        } catch {
            emit(.disconnected(reason: .launchFailed(detail: error.localizedDescription)))
            scheduleRetry()
            return
        }
        process = p
        outHandle = out.fileHandleForReading
        inHandle = input.fileHandleForWriting
        errHandle = err.fileHandleForReading
        readBuffer.removeAll()
        pendingMethods.removeAll()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async { self?.ingest(data) }
        }
        // 必须持续消费 stderr：管道缓冲区写满后子进程会阻塞在写操作上（表现为 App 假死）。
        // CLI 的诊断日志不参与界面展示，读取后即丢弃。
        err.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        readCLIVersion()
        send(method: "initialize", params: ["clientInfo": Self.clientInfo])
    }

    /// initialize 握手用的客户端标识；version 取自 `AppVersion`（单一版本来源，不再写死）
    static var clientInfo: [String: Any] {
        ["name": "codex_quota_menubar",
         "title": "Codex Quota Menu Bar",
         "version": AppVersion.current]
    }

    private func handleTermination() {
        // process 为 nil 说明已由调用方（如请求超时路径）完成清理，避免重复断开/重连
        guard process != nil else { return }
        let wasStopped = stopped
        teardown()
        guard !wasStopped else { return }
        emit(.disconnected(reason: .serverExited))
        scheduleRetry()
    }

    private func teardown() {
        outHandle?.readabilityHandler = nil
        errHandle?.readabilityHandler = nil
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        outHandle = nil
        inHandle = nil
        errHandle = nil
        readBuffer.removeAll()
        pendingMethods.removeAll()
    }

    private func scheduleRetry() {
        let idx = min(retryCount, AppServerClient.backoffSchedule.count - 1)
        let delay = AppServerClient.backoffSchedule[idx]
        retryCount += 1
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped, self.process == nil else { return }
            self.launch()
        }
    }

    // MARK: - JSON-RPC

    private func send(method: String, params: [String: Any] = [:]) {
        guard let inHandle else { return }
        let id = nextRequestId
        nextRequestId += 1
        pendingMethods[id] = method
        write(["method": method, "id": id, "params": params], to: inHandle)
        scheduleRequestTimeout(id: id)
    }

    /// 每请求超时：响应到达时 pending 已移除，超时任务自动失效；
    /// 超时未响应则清理该请求、上报 readFailed，并杀死进程按退避策略重连
    /// （子进程可能存活但 RPC 已卡死，继续复用没有意义）。
    private func scheduleRequestTimeout(id: Int) {
        let timeout = requestTimeout
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, let method = self.pendingMethods.removeValue(forKey: id) else { return }
            self.emit(.readFailed(.requestTimeout(method: method, seconds: Int(timeout))))
            let wasStopped = self.stopped
            self.teardown() // 终止卡死进程；其 terminationHandler 会因 process==nil 自动忽略
            if !wasStopped {
                self.emit(.disconnected(reason: .rpcUnresponsive))
                self.scheduleRetry()
            }
        }
    }

    private func sendNotification(method: String, params: [String: Any] = [:]) {
        guard let inHandle else { return }
        write(["method": method, "params": params], to: inHandle)
    }

    private func write(_ payload: [String: Any], to handle: FileHandle) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var line = data
        line.append(0x0A) // 换行分隔
        try? handle.write(contentsOf: line) // 管道断裂由 terminationHandler 兜底
    }

    private func ingest(_ data: Data) {
        guard !data.isEmpty else { return } // EOF 交给 terminationHandler
        readBuffer.append(data)
        while let nl = readBuffer.firstIndex(of: 0x0A) {
            let lineData = readBuffer.subdata(in: 0..<nl)
            readBuffer.removeSubrange(0...nl)
            guard !lineData.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: lineData),
                  let json = obj as? [String: Any] else { continue }
            handleMessage(json)
        }
    }

    private func handleMessage(_ json: [String: Any]) {
        if let id = RateLimitsParser.intValue(json["id"]) {
            let method = pendingMethods.removeValue(forKey: id)
            if let error = json["error"] as? [String: Any] {
                let msg = error["message"] as? String ?? "未知错误"
                emit(.readFailed(.rpcError(context: method ?? "id \(id)", message: msg)))
                return
            }
            guard let result = json["result"] as? [String: Any] else { return }
            switch method {
            case "initialize":
                sendNotification(method: "initialized")
                retryCount = 0
                emit(.connected(cliVersion: cliVersion))
                send(method: "account/read", params: ["refreshToken": false])
                sendRateLimitsRead()
            case "account/read":
                emit(.account(RateLimitsParser.account(fromResult: result)))
            case "account/rateLimits/read":
                if let snap = RateLimitsParser.snapshot(fromResult: result) {
                    emit(.snapshot(snap))
                } else {
                    emit(.readFailed(.noRateLimitData))
                }
            default:
                break
            }
        } else if let method = json["method"] as? String, method == "account/rateLimits/updated" {
            // 通知载荷为单桶残缺版，仅作为触发信号，回源全量读取
            sendRateLimitsRead()
        }
    }

    private func sendRateLimitsRead() {
        send(method: "account/rateLimits/read")
    }

    private func readCLIVersion() {
        guard let executableURL else { return }
        DispatchQueue.global().async { [weak self] in
            let p = Process()
            p.executableURL = executableURL
            p.arguments = ["--version"]
            let out = Pipe()
            p.standardOutput = out
            // 与主进程同理：stderr 建管道却不消费会阻塞子进程；此处版本日志无用，直接丢弃
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            self?.queue.async {
                self?.cliVersion = text
                self?.emit(.cliVersion(text))
            }
        }
    }

    private func emit(_ event: QuotaEvent) {
        DispatchQueue.main.async { [onEvent] in onEvent?(event) }
    }
}
