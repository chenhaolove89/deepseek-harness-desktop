# release.ps1 — 自建更新渠道发版脚本（fork: chenhaolove89/deepseek-harness-desktop）
#
# 用法（在仓库根目录 E:\DeepSeekHarness\deepseek-harness-desktop 下执行）：
#   powershell -ExecutionPolicy Bypass -File .\release.ps1 2.0.2
#   powershell -ExecutionPolicy Bypass -File .\release.ps1 2.0.2 -SkipBuild   # 跳过构建，仅发版（构建已做过）
#
# 流程：
#   1. 校验版本号 x.y.z
#   2. 同步提升根 package.json 与 dsh-plugin-desktop/package.json 的 version
#   3. 运行 `corepack yarn workspace dsh-plugin-desktop dist:win` 构建未签名 NSIS 安装包
#   4. 提交、打 tag v<version>、推送 origin（master + tag）
#   5. `gh release create v<version>` 上传安装包到你的 fork Releases
#
# 之后你机器上已安装的本 fork 版本会自动检测到新版本（走 GitHub API），
# 托盘「检查更新」即可下载安装。构建产物未签名，安装时可能提示 SmartScreen。

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Version,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

# ---- 0. 定位仓库根目录 ----
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot
Write-Host "==> 仓库根目录: $repoRoot"

# ---- 1. 校验版本号 ----
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    throw "版本号必须是 x.y.z 格式（如 2.0.2），收到: $Version"
}
Write-Host "==> 发布版本: v$Version"

# ---- 2. 同步版本号（保留原文件格式，仅替换首个 "version" 字段） ----
function Set-VersionField([string]$file, [string]$version) {
    if (-not (Test-Path $file)) { throw "找不到文件: $file" }
    $text = [System.IO.File]::ReadAllText($file)
    $new = [regex]::Replace($text, '"version"\s*:\s*"[^"]*"', "`"version`": `"$version`"", 1)
    if ($new -eq $text) { throw "未能替换 $file 中的 version 字段" }
    [System.IO.File]::WriteAllText($file, $new, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "==> 已更新 $file -> $version"
}
Set-VersionField "$repoRoot\package.json" $Version
Set-VersionField "$repoRoot\dsh-plugin-desktop\package.json" $Version

# ---- 3. 构建安装包（跳过则要求产物已存在） ----
$asset = "$repoRoot\dsh-plugin-desktop\dist\DSH-Desktop-$Version-x64-Setup.exe"
if (-not $SkipBuild) {
    Write-Host "==> 构建中（corepack yarn workspace dsh-plugin-desktop dist:win），耗时较长请耐心等待 ..."
    & corepack yarn workspace dsh-plugin-desktop dist:win
    if ($LASTEXITCODE -ne 0) { throw "dist:win 构建失败（exit $LASTEXITCODE）" }
} else {
    Write-Host "==> -SkipBuild：跳过构建"
}
if (-not (Test-Path $asset)) {
    throw "找不到安装包: $asset（请先构建或检查版本号是否与 package.json 一致）"
}
Write-Host "==> 安装包就绪: $asset"

# ---- 4. 提交 + 打 tag + 推送 ----
git add package.json dsh-plugin-desktop/package.json
git commit -m "release: v$Version"
git tag "v$Version"
# 只推 master 和本次新 tag；不要用 --tags 整批推送（fork 会继承上游旧 tag，导致整批推送失败）
git push origin master
if ($LASTEXITCODE -ne 0) { throw "git push master 失败" }
git push origin "v$Version"
if ($LASTEXITCODE -ne 0) { throw "git push tag 失败" }
Write-Host "==> 已推送 master 与 tag v$Version"

# ---- 5. 创建 GitHub Release 并上传安装包（分两步，避免大文件上传超时） ----
gh release create "v$Version" --title "DSH Desktop v$Version" --generate-notes
if ($LASTEXITCODE -ne 0) { throw "gh release create 失败" }
gh release upload "v$Version" $asset
if ($LASTEXITCODE -ne 0) { throw "gh release upload 失败" }
Write-Host "==> Release v$Version 已发布：https://github.com/chenhaolove89/deepseek-harness-desktop/releases"
Write-Host "==> 已安装的 DSH Desktop（本 fork 构建）将自动检测到该版本。完成！"
