import SwiftUI

// --probe：无界面探针模式，用于真实账号读取验证（输出已打码）
if CommandLine.arguments.contains("--probe") {
    ProbeRunner.run()
} else {
    CodexQuotaApp.main()
}
