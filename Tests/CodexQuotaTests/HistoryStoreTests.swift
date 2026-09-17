import XCTest
@testable import CodexQuota

/// 历史曲线的采样、持久化、裁剪与抽稀逻辑
final class HistoryStoreTests: XCTestCase {

    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs = []
        super.tearDown()
    }

    private func makeStore(retentionDays: Int = 7,
                           maxEntries: Int = 20_000,
                           minSampleInterval: TimeInterval = 60,
                           replaceWindow: TimeInterval = 10) -> HistoryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexQuotaHistory-\(UUID().uuidString)", isDirectory: true)
        tempDirs.append(dir)
        return HistoryStore(fileURL: dir.appendingPathComponent("history.json"),
                            retentionDays: retentionDays,
                            maxEntries: maxEntries,
                            minSampleInterval: minSampleInterval,
                            replaceWindow: replaceWindow)
    }

    private func points(primary: Int, secondary: Int) -> [HistoryPoint] {
        [HistoryPoint(windowDurationMins: 300, remainingPercent: primary),
         HistoryPoint(windowDurationMins: 10080, remainingPercent: secondary)]
    }

    private var base: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    // MARK: - 采样节流

    func testRecordAndPersistRoundTrip() {
        let store = makeStore()
        store.record(points: points(primary: 90, secondary: 60), at: base)
        store.record(points: points(primary: 80, secondary: 60), at: base.addingTimeInterval(120))
        store.flush()

        let reloaded = HistoryStore(fileURL: store.fileURL)
        XCTAssertEqual(reloaded.entries.count, 2)
        XCTAssertEqual(reloaded.entries.last?.points.first?.remainingPercent, 80)
    }

    func testSameValueWithinMinIntervalIsDropped() {
        let store = makeStore(minSampleInterval: 60)
        store.record(points: points(primary: 90, secondary: 60), at: base)
        store.record(points: points(primary: 90, secondary: 60), at: base.addingTimeInterval(10))
        XCTAssertEqual(store.entries.count, 1)
    }

    func testSameValueAfterMinIntervalAppendsHeartbeat() {
        let store = makeStore(minSampleInterval: 60)
        store.record(points: points(primary: 90, secondary: 60), at: base)
        store.record(points: points(primary: 90, secondary: 60), at: base.addingTimeInterval(61))
        XCTAssertEqual(store.entries.count, 2, "值未变但超过最小间隔时保留心跳，保证曲线连续")
    }

    func testChangeWithinReplaceWindowUpdatesLastEntry() {
        let store = makeStore(minSampleInterval: 60, replaceWindow: 10)
        store.record(points: points(primary: 90, secondary: 60), at: base)
        store.record(points: points(primary: 70, secondary: 60), at: base.addingTimeInterval(5))
        XCTAssertEqual(store.entries.count, 1, "短间隔内的变化就地更新，不堆积")
        XCTAssertEqual(store.entries.last?.points.first?.remainingPercent, 70)
        XCTAssertEqual(store.entries.last?.date, base.addingTimeInterval(5))
    }

    func testChangeAfterReplaceWindowAppends() {
        let store = makeStore(minSampleInterval: 60, replaceWindow: 10)
        store.record(points: points(primary: 90, secondary: 60), at: base)
        store.record(points: points(primary: 70, secondary: 60), at: base.addingTimeInterval(30))
        XCTAssertEqual(store.entries.count, 2)
    }

    func testEmptyPointsAreIgnored() {
        let store = makeStore()
        store.record(points: [], at: base)
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: - 裁剪

    func testRetentionPrunesOldEntries() {
        let store = makeStore(retentionDays: 1)
        store.record(points: points(primary: 90, secondary: 60), at: base.addingTimeInterval(-3 * 86_400))
        store.record(points: points(primary: 50, secondary: 40), at: base)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.points.first?.remainingPercent, 50)
    }

    func testMaxEntriesKeepsNewest() {
        let store = makeStore(maxEntries: 5)
        for i in 0..<10 {
            store.record(points: points(primary: 100 - i, secondary: 60), at: base.addingTimeInterval(Double(i) * 120))
        }
        XCTAssertEqual(store.entries.count, 5)
        XCTAssertEqual(store.entries.last?.points.first?.remainingPercent, 91)
    }

    // MARK: - 持久化边界

    func testCorruptedFileYieldsEmptyHistory() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "not-a-json".data(using: .utf8)?.write(to: store.fileURL)
        let reloaded = HistoryStore(fileURL: store.fileURL)
        XCTAssertTrue(reloaded.entries.isEmpty, "历史损坏应降级为空，不崩溃")
    }

    func testClearRemovesPersistedEntries() {
        let store = makeStore()
        store.record(points: points(primary: 90, secondary: 60), at: base)
        store.clear()
        store.flush()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(HistoryStore(fileURL: store.fileURL).entries.isEmpty)
    }

    // MARK: - 查询

    func testSamplesFilterByWindowAndTime() {
        let store = makeStore()
        store.record(points: points(primary: 90, secondary: 60), at: base)
        store.record(points: points(primary: 80, secondary: 55), at: base.addingTimeInterval(3600))

        let weekly = store.samples(windowDurationMins: 10080, since: base.addingTimeInterval(1800))
        XCTAssertEqual(weekly.count, 1)
        XCTAssertEqual(weekly.first?.remainingPercent, 55)

        let fiveHour = store.samples(windowDurationMins: 300, since: .distantPast)
        XCTAssertEqual(fiveHour.map(\.remainingPercent), [90, 80])
    }

    func testKnownWindowsFromLatestFrame() {
        let store = makeStore()
        store.record(points: points(primary: 90, secondary: 60), at: base)
        XCTAssertEqual(store.knownWindows.count, 2)
        XCTAssertEqual(store.knownWindows.first, 300)
    }

    // MARK: - 抽稀

    func testDownsampleKeepsEndpointsAndCapsCount() {
        let samples = (0..<1000).map { HistorySample(date: base.addingTimeInterval(Double($0)), remainingPercent: $0 % 100) }
        let out = HistoryDownsampler.downsample(samples, maxCount: 100)
        XCTAssertEqual(out.count, 100)
        XCTAssertEqual(out.first?.date, samples.first?.date)
        XCTAssertEqual(out.last?.date, samples.last?.date)
    }

    func testDownsampleReturnsOriginalWhenUnderLimit() {
        let samples = (0..<10).map { HistorySample(date: base.addingTimeInterval(Double($0)), remainingPercent: $0) }
        XCTAssertEqual(HistoryDownsampler.downsample(samples, maxCount: 300).count, 10)
    }

    func testDownsampleKeepsBriefDipAndRecovery() {
        var samples = (0..<1000).map {
            HistorySample(date: base.addingTimeInterval(Double($0) * 60), remainingPercent: 80)
        }
        samples[501].remainingPercent = 2
        samples[502].remainingPercent = 100
        let out = HistoryDownsampler.downsample(samples, maxCount: 100)
        XCTAssertTrue(out.contains(samples[501]), "不能把短暂耗尽的采样跳过去")
        XCTAssertTrue(out.contains(samples[502]), "不能把紧接着的额度恢复跳过去")
    }

    func testDownsampleKeepsRealSamplesInTimeOrderWithIrregularSpacing() {
        let samples = (0..<1000).map {
            HistorySample(date: base.addingTimeInterval(Double($0 * $0)), remainingPercent: ($0 * 7) % 101)
        }
        let out = HistoryDownsampler.downsample(samples, maxCount: 300)
        XCTAssertEqual(out.count, 300)
        XCTAssertTrue(out.allSatisfy { samples.contains($0) }, "绘图不得制造平均值或新采样")
        XCTAssertTrue(zip(out, out.dropFirst()).allSatisfy { $0.date < $1.date })
    }

    func testDownsampleFlatHistoryAndSmallBudgets() {
        let samples = (0..<100).map {
            HistorySample(date: base.addingTimeInterval(Double($0)), remainingPercent: 50)
        }
        for budget in [2, 3, 4, 99] {
            let out = HistoryDownsampler.downsample(samples, maxCount: budget)
            XCTAssertLessThanOrEqual(out.count, budget)
            XCTAssertEqual(out.first, samples.first)
            XCTAssertEqual(out.last, samples.last)
            XCTAssertTrue(out.allSatisfy { $0.remainingPercent == 50 })
            XCTAssertTrue(zip(out, out.dropFirst()).allSatisfy { $0.date < $1.date })
        }
        XCTAssertTrue(HistoryDownsampler.downsample([], maxCount: 300).isEmpty)
        XCTAssertEqual(HistoryDownsampler.downsample(samples, maxCount: 1), samples)
    }

    func testDisplaySimplificationReducesStaircaseWithinHalfPoint() {
        let samples = (0..<300).map {
            HistorySample(date: base.addingTimeInterval(Double($0) * 60), remainingPercent: 100 - $0 / 3)
        }
        let out = HistoryDownsampler.simplify(samples)
        XCTAssertLessThan(out.count, samples.count)
        XCTAssertEqual(out.first, samples.first)
        XCTAssertEqual(out.last, samples.last)
        XCTAssertTrue(out.allSatisfy { samples.contains($0) })
        for (start, end) in zip(out, out.dropFirst()) {
            for point in samples where point.date >= start.date && point.date <= end.date {
                let fraction = point.date.timeIntervalSince(start.date) / end.date.timeIntervalSince(start.date)
                let expected = Double(start.remainingPercent)
                    + fraction * Double(end.remainingPercent - start.remainingPercent)
                XCTAssertLessThanOrEqual(abs(Double(point.remainingPercent) - expected), 0.500_001)
            }
        }
    }

    func testDisplaySimplificationKeepsDropResetAndPlateauBoundaries() {
        let values = [80, 80, 80, 2, 100, 100, 100]
        let samples = values.enumerated().map {
            HistorySample(date: base.addingTimeInterval(Double($0.offset) * 60), remainingPercent: $0.element)
        }
        let out = HistoryDownsampler.simplify(samples)
        for index in [0, 2, 3, 4, 6] { XCTAssertTrue(out.contains(samples[index])) }
        XCTAssertEqual(HistoryDownsampler.simplify(Array(samples.prefix(2))), Array(samples.prefix(2)))
        XCTAssertTrue(HistoryDownsampler.simplify([]).isEmpty)
    }

    // MARK: - 快照记录

    func testSnapshotRecordingExtractsRemainingPercent() {
        let store = makeStore()
        store.record(RateLimitSnapshot(
            limitId: "codex",
            primary: RateWindow(usedPercent: 97, windowDurationMins: 300, resetsAt: nil),
            secondary: RateWindow(usedPercent: 35, windowDurationMins: 10080, resetsAt: nil),
            planType: "plus", fetchedAt: base), at: base)

        XCTAssertEqual(store.samples(windowDurationMins: 300, since: .distantPast).first?.remainingPercent, 3)
        XCTAssertEqual(store.samples(windowDurationMins: 10080, since: .distantPast).first?.remainingPercent, 65)
    }
}
