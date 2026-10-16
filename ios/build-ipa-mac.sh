#!/bin/bash
# =====================================================================
#  Mac 上一键构建 IPA（需要 Xcode 15+ 与 XcodeGen）
#
#  用法：
#    ./build-ipa-mac.sh                        # 无签名 IPA（配 AltStore 用）
#    TEAM_ID=XXXXXXXXXX ./build-ipa-mac.sh     # 用你的开发者账号签名并导出 IPA
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"

SCHEME="WeChatOCRAutoReply"
CONFIGURATION="${CONFIGURATION:-Release}"

echo "==> 1/3 生成 Xcode 工程"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "未安装 XcodeGen：brew install xcodegen"
  exit 1
fi
xcodegen generate

echo "==> 2/3 Archive"
if [ -n "${TEAM_ID:-}" ]; then
  # 自动签名（个人/公司开发者账号均可）
  xcodebuild \
    -project "${SCHEME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -archivePath "build/${SCHEME}.xcarchive" \
    archive \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -allowProvisioningUpdates
else
  # 无签名（CI / AltStore 重签名用）
  xcodebuild \
    -project "${SCHEME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -archivePath "build/${SCHEME}.xcarchive" \
    archive \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM=""
fi

echo "==> 3/3 导出 IPA"
if [ -n "${TEAM_ID:-}" ]; then
  cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "build/${SCHEME}.xcarchive" \
    -exportPath "build/ipa" \
    -exportOptionsPlist build/ExportOptions.plist
  echo "完成：build/ipa/${SCHEME}.ipa"
else
  rm -rf Payload
  mkdir -p Payload
  cp -R "build/${SCHEME}.xcarchive/Products/Applications/${SCHEME}.app" Payload/
  zip -qry "build/${SCHEME}-unsigned.ipa" Payload
  rm -rf Payload
  echo "完成：build/${SCHEME}-unsigned.ipa（无签名，用 AltStore 安装）"
fi
