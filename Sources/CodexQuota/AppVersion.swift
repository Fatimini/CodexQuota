import Foundation

/// 应用版本的单一来源。
///
/// - 打包为 `.app` 时：读取 Info.plist 的 `CFBundleShortVersionString`
///   （由 `build_app.sh` 在构建时注入 `VERSION` 文件内容）；
/// - 命令行直跑（无 bundle，如 `swift run`、探针模式）：回退到 `fallback`。
///
/// 这样 `VERSION`、Info.plist、App Server `clientInfo.version`、Release Notes 同源，
/// 不再出现代码里写死版本号导致的漂移。
enum AppVersion {

    /// 无 bundle 时的回退值（明确标记为开发态，避免与发布版本号混淆）
    static let fallback = "0.0.0-dev"

    /// 版本读取来源；默认主 bundle，测试可注入临时 bundle 验证打包后取值
    static var bundleProvider: () -> Bundle = { Bundle.main }

    static var current: String {
        if let v = bundleProvider().infoDictionary?["CFBundleShortVersionString"] as? String, !v.isEmpty {
            return v
        }
        return fallback
    }
}
