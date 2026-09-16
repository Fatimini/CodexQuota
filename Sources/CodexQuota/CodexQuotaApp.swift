import SwiftUI

struct CodexQuotaApp: App {
    @StateObject private var vm: QuotaViewModel

    init() {
        let model = QuotaViewModel(client: AppServerClient())
        _vm = StateObject(wrappedValue: model)
        Task { @MainActor in model.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            DetailView(vm: vm)
        } label: {
            // 注意：MenuBarExtra 的 label 不支持 Label 视图（只渲染图标），须用 HStack 拼接
            HStack(spacing: 3) {
                Image(systemName: "timer")
                Text(vm.menuTitle)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
