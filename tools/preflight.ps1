# =====================================================================
#  推送前本地类型检查（preflight）—— Windows + Swift 6 工具链
#  PowerShell 版（和 preflight.sh 等价）
#
#  前提：winget install --id Swift.Toolchain
#  用法：powershell -ExecutionPolicy Bypass -File tools\preflight.ps1
# =====================================================================
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$Stubs = Join-Path $RepoRoot "tools\swift-stubs"
$Out = Join-Path $RepoRoot "build\preflight-modules"

# ---- 定位 swiftc / SDK ----
$Swiftc = $env:SWIFTC
if (-not $Swiftc) {
    $Swiftc = Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Toolchains\*\usr\bin\swiftc.exe" |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Swiftc) { Write-Error "找不到 swiftc。请先安装：winget install --id Swift.Toolchain"; exit 1 }

$SwiftSdk = $env:SWIFT_SDK
if (-not $SwiftSdk) {
    $SwiftSdk = Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Platforms\*\Windows.platform\Developer\SDKs\Windows.sdk" |
        Select-Object -First 1 -ExpandProperty FullName
}
if (-not $SwiftSdk) { Write-Error "找不到 Windows.sdk（Swift 工具链自带）。"; exit 1 }

# ---- Windows Swift 已知 bug：大小写 proxy 变量同时存在会崩溃 ----
Remove-Item Env:http_proxy -ErrorAction SilentlyContinue
Remove-Item Env:https_proxy -ErrorAction SilentlyContinue

Write-Host "swiftc: $Swiftc"
Write-Host "sdk:    $SwiftSdk"

if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory -Path $Out -Force | Out-Null

# ---- 1. 编译桩模块 ----
$Modules = @("CoreGraphics","CoreMedia","Combine","os","UIKit","Vision",
             "CoreImage","ReplayKit","UserNotifications","SwiftUI","PhotosUI","Network")
foreach ($m in $Modules) {
    & $Swiftc -emit-module -module-name $m -sdk $SwiftSdk -I $Out `
        -emit-module-path "$Out\$m.swiftmodule" "$Stubs\$m.swift"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "桩模块 $m 编译失败（tools/ 自身问题）"; exit 1
    }
}
Write-Host ("桩模块 OK（" + ($Modules -join ", ") + "）")

$Fail = 0

# ---- 2. App 目标 ----
Write-Host "── 类型检查：WeChatOCRAutoReply（App + Shared）"
& $Swiftc -typecheck -swift-version 5 -parse-as-library `
    -module-name WeChatOCRAutoReply -sdk $SwiftSdk -I $Out `
    "$RepoRoot\ios\WeChatOCRAutoReply\App\*.swift" `
    "$RepoRoot\ios\WeChatOCRAutoReply\Shared\*.swift"
if ($LASTEXITCODE -ne 0) { Write-Host "   ✗ 有编译错误（见上方）" -ForegroundColor Red; $Fail = 1 }
else { Write-Host "   OK" -ForegroundColor Green }

# ---- 3. 广播扩展目标 ----
Write-Host "── 类型检查：BroadcastExtension（Broadcast + Shared）"
& $Swiftc -typecheck -swift-version 5 -parse-as-library `
    -module-name BroadcastExtension -sdk $SwiftSdk -I $Out `
    "$RepoRoot\ios\WeChatOCRAutoReply\Broadcast\*.swift" `
    "$RepoRoot\ios\WeChatOCRAutoReply\Shared\*.swift"
if ($LASTEXITCODE -ne 0) { Write-Host "   ✗ 有编译错误（见上方）" -ForegroundColor Red; $Fail = 1 }
else { Write-Host "   OK" -ForegroundColor Green }

if ($Fail -eq 0) { Write-Host "✅ preflight 通过：两个目标均可编译，可以推送" -ForegroundColor Green }
else { Write-Host "❌ preflight 未通过：先修上面的错误再推送" -ForegroundColor Red }
exit $Fail
