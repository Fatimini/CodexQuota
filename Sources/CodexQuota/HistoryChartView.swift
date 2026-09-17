import Charts
import SwiftUI

/// 曲线时间范围
enum HistoryRange: String, CaseIterable, Identifiable {
    case sixHours
    case oneDay
    case sevenDays

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .sixHours: return 6 * 3600
        case .oneDay: return 24 * 3600
        case .sevenDays: return 7 * 86_400
        }
    }

    /// X 轴按跨度决定显示「时:分」还是「月/日」
    var axisSpanHours: Int { Int(duration / 3600) }

    var title: String {
        switch self {
        case .sixHours: return L10n.range6Hours
        case .oneDay: return L10n.range24Hours
        case .sevenDays: return L10n.range7Days
        }
    }
}

/// 一条曲线（一个限额窗口）
struct HistorySeries: Identifiable {
    var windowDurationMins: Int?
    var samples: [HistorySample]
    var color: Color

    var id: String { windowDurationMins.map(String.init) ?? "unknown" }
    var name: String { L10n.windowName(minutes: windowDurationMins) }
}

/// 详情面板内的历史曲线：按窗口分线绘制剩余额度走势
struct HistoryChartView: View {
    @ObservedObject var store: HistoryStore
    /// 由面板层持有：点击面板其他区域时复位，避免确认态一直停留
    @Binding var confirmingClear: Bool
    @State private var range: HistoryRange = .oneDay

    private static let palette: [Color] = [.green, .orange, .blue, .purple, .pink]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chartArea
            footer
        }
        .onChange(of: range) { _ in confirmingClear = false }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.historyTitle).font(.subheadline)
            Spacer()
            Picker("", selection: $range) {
                ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 176)
        }
    }

    @ViewBuilder
    private var chartArea: some View {
        if seriesList.isEmpty {
            placeholder
        } else {
            chart
            legend
        }
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(L10n.historyEmpty).font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 152)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }

    private var chart: some View {
        HistoryPlot(series: seriesList, range: range)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(seriesList) { series in
                HStack(spacing: 4) {
                    Circle().fill(series.color).frame(width: 7, height: 7)
                    Text(series.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Text(footerText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            clearButton
        }
    }

    /// 常态为带边框的常规按钮；进入确认态后转为红色醒目按钮（再点一次才真正清除）
    @ViewBuilder
    private var clearButton: some View {
        if confirmingClear {
            Button {
                store.clear()
                confirmingClear = false
            } label: {
                Label(L10n.clearConfirm, systemImage: "trash.fill")
                    .font(.footnote)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        } else {
            Button {
                confirmingClear = true
            } label: {
                Label(L10n.clearHistory, systemImage: "trash")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - 数据

    /// 按最近一帧的窗口顺序取各窗口在选定范围内的采样（点数不足 2 不画线）
    private var seriesList: [HistorySeries] {
        let since = Date().addingTimeInterval(-range.duration)
        var result: [HistorySeries] = []
        for (idx, mins) in store.knownWindows.enumerated() {
            let raw = store.samples(windowDurationMins: mins, since: since)
            guard raw.count >= 2 else { continue }
            result.append(HistorySeries(
                windowDurationMins: mins,
                samples: HistoryDownsampler.simplify(
                    HistoryDownsampler.downsample(raw, maxCount: 300)),
                color: Self.palette[idx % Self.palette.count]))
        }
        return result
    }

    private var sampleCount: Int {
        let since = Date().addingTimeInterval(-range.duration)
        return store.entries.filter { $0.date >= since }.count
    }

    private var footerText: String {
        sampleCount > 0 ? L10n.sampleCount(sampleCount) : L10n.historyFooterHint
    }
}

/// Shared by the panel and native rendering checks; contains no account information.
struct HistoryPlot: View {
    let series: [HistorySeries]
    let range: HistoryRange

    var body: some View {
        Chart {
            ForEach(series) { series in
                ForEach(series.samples, id: \.date) { sample in
                    LineMark(
                        x: .value(L10n.chartPlotTime, sample.date),
                        y: .value(L10n.chartPlotRemaining, sample.remainingPercent),
                        series: .value(L10n.chartPlotWindow, series.name)
                    )
                    .foregroundStyle(series.color)
                    // Monotone cubic interpolation rounds turns without overshooting quota values.
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
        // Leave room for the full stroke at 0% and 100%, including rounded ends.
        .chartYScale(domain: 0...100, range: .plotDimension(padding: 3))
        .chartXScale(range: .plotDimension(padding: 3))
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel {
                    if let pct = value.as(Int.self) { Text("\(pct)") }
                }
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(L10n.chartAxisTime(date, spanHours: range.axisSpanHours))
                            .fixedSize()
                    }
                }
            }
        }
        .frame(height: 132)
        // Composite the chart at the display's native scale with antialiased edges.
        .drawingGroup(opaque: false, colorMode: .linear)
    }
}
