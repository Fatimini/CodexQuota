import AppKit
import Foundation

/// 视图层状态持有者：近实时刷新策略
/// 启动读一次 → updated 通知回源 read → 定时兜底刷新（默认 3 分钟）→ 休眠唤醒即刷
@MainActor
final class QuotaViewModel: ObservableObject {

    @Published private(set) var state = QuotaState()

    /// 历史曲线数据源（本机持久化，仅存时间戳与剩余百分比）
    let history: HistoryStore

    private let client: QuotaClientProtocol
    private let refreshInterval: TimeInterval
    private var refreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var localeObserver: NSObjectProtocol?
    private var started = false

    init(client: QuotaClientProtocol,
         refreshInterval: TimeInterval = 180,
         history: HistoryStore = HistoryStore()) {
        self.client = client
        self.refreshInterval = refreshInterval
        self.history = history
        client.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.state = QuotaStateMachine.reduce(self.state, event)
                if case .snapshot(let snap) = event { self.history.record(snap) }
            }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        client.start()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        // 系统语言变更时立即重渲染界面文案（无需重启 App）
        localeObserver = NotificationCenter.default.addObserver(
            forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }
    }

    func refresh() {
        client.requestRefresh()
    }

    func quit() {
        history.flush() // 退出前等待历史落盘
        client.stop()
        NSApplication.shared.terminate(nil)
    }

    var menuTitle: String { QuotaFormatter.menuTitle(for: state) }

    deinit {
        refreshTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let localeObserver {
            NotificationCenter.default.removeObserver(localeObserver)
        }
    }
}
