# 贡献指南

## 开发环境

- macOS 13+，Swift 5.9+（Xcode 或 Command Line Tools）
- Apple Silicon（Intel 可编译，但当前未发布 Universal 产物）
- 本机已安装并登录 Codex CLI（仅真实数据验证时需要，跑单测不需要）

## 常用命令

```bash
swift build                    # 编译
swift test                     # 单元测试（当前 61 例）
./build_app.sh "改动摘要"       # 打包 + ad-hoc 签名 + 本机归档
.build/release/CodexQuota --probe   # 真实读取一次（输出打码）
```

## 提交前检查

1. `swift test` 全绿；
2. **不提交构建产物**：`.build/`、`*.app/`、`releases/` 已在 `.gitignore` 中；
3. 不在 Issue / PR 中贴本机绝对路径、邮箱、额度原始响应；
4. 版本号不写在代码里：`VERSION` 是唯一来源，升版本请改 `VERSION` 文件。

## 代码约定

- **文案**统一放 `Sources/CodexQuota/L10n.swift`；状态层只存结构化错误（`QuotaFailure`），不存译文，保证语言切换后能重译。
- **不编造数值**：解析层对外部字段做严格校验（类型、范围、整数性），非法值一律视为未返回。新增外部输入必须配套边界测试，参考 `RateLimitsParser.intValue` 的用例。
- **子进程**：任何 `Process` 只要建了 stderr 管道就必须持续消费（或指向 `FileHandle.nullDevice`），否则缓冲区写满会阻塞子进程。
- **写盘**：除 `HistoryStore` 的历史文件外，不新增落盘；涉及隐私边界变化的改动必须在 README 隐私章节同步说明。

## 提交信息

简短说明改动与动机；若涉及口径、规则或隐私边界变化，请注明依据与影响面。
