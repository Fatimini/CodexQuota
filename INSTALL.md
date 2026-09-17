# CodexQuota Mac 试用版 / Mac trial

适用于 Apple Silicon（M 系列）Mac，macOS 13 或更新版本。Intel、Windows 暂不提供安装包。
这是非官方、未获 Apple 公证的试用版，不需要 Xcode 或自行编译。需要你自己的 Codex CLI 和 ChatGPT 登录。

## 安装

1. 从 https://github.com/Fatimini/CodexQuota/releases/tag/v1.3.2 下载带 `macOS-arm64.zip` 的附件，不要选择 Source code。
2. 解压，将 CodexQuota.app 拖到“应用程序”，再打开。更新前先从旧 App 菜单退出。
3. 如果提示无法验证开发者，仅在确认来源可信时，进入“系统设置 → 隐私与安全性”，为此 App 选择“仍要打开”，按提示确认。不要关闭系统整体安全保护。
4. 若显示“将损坏电脑”或“已损坏”，停止安装，重新检查下载来源或反馈问题，不要强行绕过。
5. App 只在屏幕顶部菜单栏显示，不出现在 Dock。点击计时器图标打开详情。

Apple 官方说明：https://support.apple.com/en-gb/102445

## 连接自己的 Codex 账号

1. 按 OpenAI 官方说明安装 Codex CLI：https://learn.chatgpt.com/docs/codex/cli
2. 打开 Mac“终端”，运行 `codex login`，在浏览器中登录自己的 ChatGPT 账号。
3. 退出并重新打开 CodexQuota。安装在非常用位置时，请参照官方安装方法使用标准位置。
4. 读取失败时，先确认 CLI 和网络正常，再点“立即刷新”。缺少某个额度窗口时不补造数值。

无需把密码、Token 或认证文件发给开发者。历史曲线仅保存在本机，可在面板中确认清除。

## English

Apple Silicon Mac, macOS 13+. Unofficial trial, ad-hoc signed and not notarized by Apple.
Extract the ZIP and drag CodexQuota.app into Applications. Quit any previous copy before updating.
If macOS cannot verify the developer, only if you trust the source, use System Settings → Privacy & Security → Open Anyway.
Do not bypass malware or damaged-app warnings. See the Apple guide above.
Install Codex CLI using the official guide above, run `codex login` with your own ChatGPT account, then reopen CodexQuota.
The app lives in the menu bar, not the Dock. No Xcode or compilation is required for the trial ZIP.
