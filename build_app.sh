#!/bin/bash
# 构建 CodexQuota.app（release）→ 注入版本号 → ad-hoc 签名 → 归档到 releases/
#
# 用法：
#   ./build_app.sh "本次改动摘要"
#
# 版本号不接受命令行覆盖 —— VERSION 文件是唯一的发布版本来源
# （升版本请先修改 VERSION 并提交，避免产物版本与仓库版本分叉）。
#
# 归档目录 releases/v<版本>-<日期>/ 内含 App 与 RELEASE_NOTES.md；
# 已存在同名归档时拒绝覆盖（历史版本只读，保证升级路程可追溯）。
set -euo pipefail
cd "$(dirname "$0")"

# VERSION 文件为唯一版本来源：缺失或为空即中止，不回退到任何默认值
VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || true)"
if [ -z "$VERSION" ]; then
    echo "!! VERSION 文件缺失或为空；请先在 VERSION 中写入版本号再构建" >&2
    exit 1
fi
NOTES="${1:-见 CHANGELOG.md}"
DATE=$(date +%Y%m%d)
APP="CodexQuota.app"
RELEASE_DIR="releases/v${VERSION}-${DATE}"

if [ -d "$RELEASE_DIR" ]; then
    echo "!! 归档已存在，拒绝覆盖：${RELEASE_DIR}（同一天重复构建请先删除该目录或升版本号）" >&2
    exit 1
fi

echo "==> swift build -c release (v${VERSION})"
swift build -c release

echo "==> 打包 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/CodexQuota "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"

echo "==> 注入版本号 ${VERSION}（仓库内 Info.plist 保持模板不变）"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$APP/Contents/Info.plist"

# 注入校验：确认版本号确实写入了 Info.plist（来源校验在归档后重新读 VERSION 比对）
INJECTED=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
if [ "$INJECTED" != "$VERSION" ]; then
    echo "!! 版本不一致：VERSION=${VERSION}，Info.plist=${INJECTED}" >&2
    exit 1
fi

echo "==> ad-hoc 签名"
# 不再吞掉失败：签名失败即中止，避免产出「看似成功、实际未签名」的包
codesign --force --sign - "$APP"

echo "==> 签名验证"
# 命令返回成功 ≠ 产物可验证；显式校验签名链
# 注意：ad-hoc 签名通过校验 ≠ 公证，Gatekeeper 仍会拒绝该包，不能作正式分发
codesign --verify --deep --strict "$APP"

echo "==> 归档 $RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
cp -R "$APP" "$RELEASE_DIR/"
SHA=$(shasum -a 256 "$RELEASE_DIR/$APP/Contents/MacOS/CodexQuota" | awk '{print $1}')
{
    echo "# CodexQuota v${VERSION}（构建日期 $(date +%Y-%m-%d)）"
    echo
    echo "- 产物：\`$RELEASE_DIR/CodexQuota.app\`"
    echo "- 可执行文件 SHA-256：\`$SHA\`"
    echo "- 构建方式：\`swift build -c release\` + ad-hoc 签名（仅本机运行，非公证分发版）"
    echo
    echo "## 本次改动"
    echo
    echo "$NOTES"
} > "$RELEASE_DIR/RELEASE_NOTES.md"

# 版本一致性终检（非自证）：重新从磁盘读取 VERSION 文件，
# 与产物 Info.plist、Release Notes 标题三方比对；校验值不复用脚本变量，
# 才能发现「VERSION 文件与产物版本」的真实漂移。
FILE_VERSION="$(tr -d '[:space:]' < VERSION)"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$RELEASE_DIR/$APP/Contents/Info.plist")"
if ! grep -q "^# CodexQuota v${FILE_VERSION}" "$RELEASE_DIR/RELEASE_NOTES.md"; then
    echo "!! Release Notes 版本号与 VERSION 文件不一致（VERSION=${FILE_VERSION}）" >&2
    exit 1
fi
if [ "$PLIST_VERSION" != "$FILE_VERSION" ]; then
    echo "!! 产物 Info.plist 版本与 VERSION 文件不一致：VERSION=${FILE_VERSION}，Info.plist=${PLIST_VERSION}" >&2
    exit 1
fi
echo "==> 版本一致性校验通过（VERSION / Info.plist / Release Notes = ${FILE_VERSION}）"

echo "==> 完成: $(pwd)/$APP"
echo "==> 归档: $(pwd)/$RELEASE_DIR"
