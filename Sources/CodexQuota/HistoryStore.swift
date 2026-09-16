import Foundation

/// 历史采样点：某个窗口在某一时刻的剩余百分比。
/// 只保存「窗口时长 + 剩余百分比」，不落盘邮箱、账号或任何凭据字段。
struct HistoryPoint: Codable, Equatable {
    var windowDurationMins: Int?
    var remainingPercent: Int
}

/// 一次成功读取留下的历史记录（一帧可含多个窗口）
struct HistoryEntry: Codable, Equatable {
    var date: Date
    var points: [HistoryPoint]
}

/// 曲线绘制用的单个数据点
struct HistorySample: Equatable {
    var date: Date
    var remainingPercent: Int
}

/// 历史存储：采样节流 + 本机持久化 + 保留期裁剪。
///
/// 采样规则（避免高频写入、又不在额度快耗光时丢细节）：
/// 1. 数值未变化且距上次采样不足 `minSampleInterval` → 丢弃；
/// 2. 数值变化但距上次采样不足 `replaceWindow` → 就地更新最后一条（不堆积）；
/// 3. 其余情况追加一条。
///
/// 落盘位置：`~/Library/Application Support/CodexQuota/history.json`（仅本机，不外发）。
final class HistoryStore: ObservableObject {

    @Published private(set) var entries: [HistoryEntry] = []

    let fileURL: URL
    private let retention: TimeInterval
    private let maxEntries: Int
    private let minSampleInterval: TimeInterval
    private let replaceWindow: TimeInterval
    private let now: () -> Date
    private let ioQueue = DispatchQueue(label: "codexquota.history.io")

    init(fileURL: URL = HistoryStore.defaultFileURL,
         retentionDays: Int = 7,
         maxEntries: Int = 20_000,
         minSampleInterval: TimeInterval = 60,
         replaceWindow: TimeInterval = 10,
         now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.retention = TimeInterval(retentionDays) * 86_400
        self.maxEntries = maxEntries
        self.minSampleInterval = minSampleInterval
        self.replaceWindow = replaceWindow
        self.now = now
        self.entries = Self.load(from: fileURL)
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("CodexQuota", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    // MARK: - 采样

    /// 记录一次成功读取的快照
    func record(_ snapshot: RateLimitSnapshot, at date: Date? = nil) {
        let points = snapshot.windows.map {
            HistoryPoint(windowDurationMins: $0.windowDurationMins, remainingPercent: $0.remainingPercent)
        }
        record(points: points, at: date)
    }

    func record(points: [HistoryPoint], at date: Date? = nil) {
        guard !points.isEmpty else { return }
        let t = date ?? now()
        if let last = entries.last {
            let gap = t.timeIntervalSince(last.date)
            let sameValues = last.points == points
            if sameValues && gap < minSampleInterval { return }        // 值未变且间隔太短
            if !sameValues && gap < replaceWindow {                    // 短间隔内变化：就地更新
                entries[entries.count - 1] = HistoryEntry(date: t, points: points)
                save()
                return
            }
        }
        entries.append(HistoryEntry(date: t, points: points))
        prune(now: t)
        save()
    }

    /// 指定窗口在 `since` 之后的采样，按时间升序
    func samples(windowDurationMins: Int?, since: Date) -> [HistorySample] {
        entries.compactMap { entry in
            guard entry.date >= since else { return nil }
            guard let point = entry.points.first(where: { $0.windowDurationMins == windowDurationMins }) else { return nil }
            return HistorySample(date: entry.date, remainingPercent: point.remainingPercent)
        }
    }

    /// 最近一帧记录里出现过的窗口时长（曲线按这些窗口分线）
    var knownWindows: [Int?] {
        entries.last?.points.map { $0.windowDurationMins } ?? []
    }

    func clear() {
        entries = []
        save()
    }

    /// 等待后台落盘完成（测试用）
    func flush() { ioQueue.sync {} }

    // MARK: - 持久化

    private func prune(now t: Date) {
        if retention > 0 {
            let cutoff = t.addingTimeInterval(-retention)
            if let idx = entries.lastIndex(where: { $0.date < cutoff }) {
                entries.removeSubrange(0...idx)
            }
        }
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    private func save() {
        let snapshot = entries
        let url = fileURL
        ioQueue.async {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 文件缺失或损坏时返回空历史，不抛错、不崩溃（历史只用于展示）
    private static func load(from url: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let list = try? decoder.decode([HistoryEntry].self, from: data) else { return [] }
        return list.sorted { $0.date < $1.date }
    }
}

/// 抽稀：曲线点数过多会拖慢渲染，均匀取样到上限内并固定保留首尾点
enum HistoryDownsampler {
    static func downsample(_ samples: [HistorySample], maxCount: Int) -> [HistorySample] {
        guard maxCount >= 2, samples.count > maxCount else { return samples }
        let step = Double(samples.count - 1) / Double(maxCount - 1)
        var out: [HistorySample] = []
        out.reserveCapacity(maxCount)
        for i in 0..<maxCount {
            var idx = Int((Double(i) * step).rounded())
            idx = min(max(idx, 0), samples.count - 1)
            out.append(samples[idx])
        }
        if let last = samples.last { out[maxCount - 1] = last }
        return out
    }
}
