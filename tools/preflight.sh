#!/usr/bin/env bash
# =====================================================================
#  推送前本地类型检查（preflight）—— Windows + Swift 6 工具链
#
#  做什么：
#    1. 把 tools/swift-stubs/ 下的 iOS SDK 桩模块编译成 .swiftmodule
#    2. 用 swiftc -typecheck 分别检查两个 Xcode 目标：
#         - WeChatOCRAutoReply（App/*.swift + Shared/*.swift）
#         - BroadcastExtension（Broadcast/*.swift + Shared/*.swift）
#    3. 有 error 就非零退出 —— 推送前先跑它，CI 就不会再当第一个编译器
#
#  前提：已安装 Swift for Windows（winget install Swift.Toolchain）
#  用法：bash tools/preflight.sh
# =====================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STUBS="$REPO_ROOT/tools/swift-stubs"
OUT="$REPO_ROOT/build/preflight-modules"

# ---- 定位 swiftc / SDK（winget 默认安装位置） --------------------------
LOCAL_APPDATA="${LOCALAPPDATA:-$USERPROFILE/AppData/Local}"
if [ -z "${SWIFTC:-}" ]; then
  for cand in "$LOCAL_APPDATA/Programs/Swift/Toolchains/"*/usr/bin/swiftc.exe; do
    [ -x "$cand" ] && SWIFTC="$cand" && break
  done
fi
if [ -z "${SWIFTC:-}" ] || [ ! -f "$SWIFTC" ]; then
  echo "找不到 swiftc。请先安装：winget install --id Swift.Toolchain" >&2
  exit 1
fi
if [ -z "${SWIFT_SDK:-}" ]; then
  for cand in "$LOCAL_APPDATA/Programs/Swift/Platforms/"*/Windows.platform/Developer/SDKs/Windows.sdk; do
    [ -d "$cand" ] && SWIFT_SDK="$cand" && break
  done
fi
if [ -z "${SWIFT_SDK:-}" ] || [ ! -d "$SWIFT_SDK" ]; then
  echo "找不到 Windows.sdk（Swift 工具链自带）。" >&2
  exit 1
fi

# ---- Windows Swift 的已知 bug：大小写 proxy 变量同时存在会直接崩溃 ----
unset http_proxy https_proxy 2>/dev/null || true

echo "swiftc: $SWIFTC"
echo "sdk:    $SWIFT_SDK"

rm -rf "$OUT"
mkdir -p "$OUT"

# ---- 1. 编译桩模块（顺序即依赖顺序） -----------------------------------
MODULES="CoreGraphics CoreMedia Combine os UIKit Vision CoreImage ReplayKit UserNotifications SwiftUI PhotosUI Network"
for m in $MODULES; do
  if ! "$SWIFTC" -emit-module -module-name "$m" -sdk "$SWIFT_SDK" -I "$OUT" \
       -emit-module-path "$OUT/$m.swiftmodule" "$STUBS/$m.swift" 2>&1; then
    echo "桩模块 $m 编译失败（这是 tools/ 自身的问题，不是 App 代码的问题）" >&2
    exit 1
  fi
done
echo "桩模块 OK（${MODULES// /, }）"

FAIL=0

# ---- 2. 类型检查：App 目标 ---------------------------------------------
echo "── 类型检查：WeChatOCRAutoReply（App + Shared）"
if "$SWIFTC" -typecheck -swift-version 5 -parse-as-library \
     -module-name WeChatOCRAutoReply -sdk "$SWIFT_SDK" -I "$OUT" \
     "$REPO_ROOT/ios/WeChatOCRAutoReply/App/"*.swift \
     "$REPO_ROOT/ios/WeChatOCRAutoReply/Shared/"*.swift 2>&1; then
  echo "   OK"
else
  echo "   ✗ 有编译错误（见上方）" >&2
  FAIL=1
fi

# ---- 3. 类型检查：广播扩展目标 ------------------------------------------
echo "── 类型检查：BroadcastExtension（Broadcast + Shared）"
if "$SWIFTC" -typecheck -swift-version 5 -parse-as-library \
     -module-name BroadcastExtension -sdk "$SWIFT_SDK" -I "$OUT" \
     "$REPO_ROOT/ios/WeChatOCRAutoReply/Broadcast/"*.swift \
     "$REPO_ROOT/ios/WeChatOCRAutoReply/Shared/"*.swift 2>&1; then
  echo "   OK"
else
  echo "   ✗ 有编译错误（见上方）" >&2
  FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo "✅ preflight 通过：两个目标均可编译，可以推送"
else
  echo "❌ preflight 未通过：先修上面的错误再推送" >&2
fi
exit $FAIL
