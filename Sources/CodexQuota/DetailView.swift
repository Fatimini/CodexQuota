import SwiftUI

/// 点击菜单栏图标后的详情面板
struct DetailView: View {
    @ObservedObject var vm: QuotaViewModel
    /// 历史「清除」的确认态：点击面板其他区域即复位
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            windowsSection
            Divider()
            HistoryChartView(store: vm.history, confirmingClear: $confirmingClear)
            Divider()
            infoGrid
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 380)
        // 空白处点击 → 复位历史清除按钮的确认态（放在 background 层，不会拦截按钮本身）
        .background(
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { confirmingClear = false }
        )
    }

    private var header: some View {
        HStack {
            Text(L10n.panelTitle).font(.headline)
            Spacer()
            freshnessView
        }
    }

    /// 右上角：正常时显示数据新鲜度（刚刚更新 / N 分钟前更新），异常时显示警告徽标
    @ViewBuilder
    private var freshnessView: some View {
        switch vm.state.dataStatus {
        case .fresh:
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(L10n.freshnessText(since: vm.state.lastSuccessAt, now: context.date))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .stale:
            warningBadge(L10n.statusStale, color: .orange)
        case .unavailable:
            warningBadge(L10n.statusNoData, color: .secondary)
        }
    }

    private func warningBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var windowsSection: some View {
        if let snap = vm.state.snapshot, !snap.windows.isEmpty {
            ForEach(Array(snap.windows.enumerated()), id: \.offset) { _, window in
                WindowRow(window: window)
            }
        } else {
            Text(L10n.noQuotaData)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var infoGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow { Text(L10n.plan).foregroundStyle(.secondary); Text(planText) }
            GridRow { Text(L10n.account).foregroundStyle(.secondary); Text(accountText) }
            GridRow { Text(L10n.lastSuccess).foregroundStyle(.secondary); Text(lastSuccessText) }
            GridRow { Text(L10n.dataStatus).foregroundStyle(.secondary); Text(QuotaFormatter.dataStatusText(vm.state.dataStatus)) }
            GridRow { Text(L10n.connection).foregroundStyle(.secondary); Text(connectionText) }
            GridRow { Text(L10n.cliVersion).foregroundStyle(.secondary); Text(vm.state.cliVersion ?? L10n.unknown) }
        }
        .font(.callout)
    }

    private var footer: some View {
        HStack {
            Button(L10n.refreshNow) { vm.refresh() }
            Spacer()
            Button(L10n.quit) { vm.quit() }
        }
    }

    // MARK: - 文本拼装

    private var planText: String {
        let plan = vm.state.snapshot?.planType ?? vm.state.account?.planType
        return plan?.capitalized ?? L10n.unknown
    }

    private var accountText: String {
        guard let account = vm.state.account else { return L10n.unknown }
        if !account.loggedIn { return L10n.notSignedIn }
        return QuotaFormatter.maskEmail(account.email) ?? L10n.signedIn
    }

    private var lastSuccessText: String {
        guard let t = vm.state.lastSuccessAt else { return L10n.neverSucceeded }
        return QuotaFormatter.timeText(t)
    }

    private var connectionText: String {
        QuotaFormatter.connectionText(for: vm.state)
    }
}

/// 单个限额窗口展示行
struct WindowRow: View {
    let window: RateWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.displayName).font(.subheadline)
                Spacer()
                Text(L10n.remaining(window.remainingPercent))
                    .font(.subheadline).bold()
                    .foregroundStyle(window.isCritical ? Color.red : Color.primary)
            }
            // 进度条显示「剩余」：与大数字语义一致；告急时变红并带红晕
            ProgressView(value: window.progressValue, total: 100)
                .tint(window.isCritical ? .red : .green)
                .shadow(color: window.isCritical ? .red.opacity(0.6) : .clear, radius: 5)
            HStack {
                Text(L10n.used(window.usedPercent))
                    .font(.footnote).foregroundStyle(.secondary)
                Spacer()
                resetText
            }
        }
        // 告急窗口（剩余 ≤10%）：红边发光卡片告警；常态保持平面
        .padding(window.isCritical ? 10 : 0)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(window.isCritical ? Color.red.opacity(0.06) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(window.isCritical ? Color.red.opacity(0.4) : .clear, lineWidth: 1)
        )
        .shadow(color: window.isCritical ? .red.opacity(0.35) : .clear, radius: 8)
    }

    @ViewBuilder
    private var resetText: some View {
        if let resetsAt = window.resetsAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(L10n.resetLine(
                    countdown: QuotaFormatter.countdownText(to: resetsAt, from: context.date),
                    local: QuotaFormatter.localTimeText(resetsAt)))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            Text(L10n.resetTimeUnavailable)
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
