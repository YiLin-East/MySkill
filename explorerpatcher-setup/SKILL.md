---
name: explorerpatcher-setup
description: 在 Windows 上下载、校验、安装和配置 ExplorerPatcher，并验证安装与任务栏位置。适用于安装 Windows 增强工具、设置 ExplorerPatcher 或将 Windows 10 主任务栏移到顶部；附带脚本仅支持 Windows 10 原生任务栏。
---

# ExplorerPatcher 安装与任务栏置顶

完成官方安装包下载、完整性校验、安装、主任务栏置顶和持久化验证。默认只调整用户要求的设置；鼠标指针、主按键、开始菜单风格和其他显示器的任务栏不在默认修改范围内。

## 识别环境与来源

1. 读取 Windows 版本、构建号和系统架构，确认当前会话有 `explorer.exe`。不要只根据“Windows 10/11”名称决定兼容性。
2. 如果用户从自己的 fork 指定工具，读取其说明和上游关系。ExplorerPatcher 官方发布源为 [valinet/ExplorerPatcher](https://github.com/valinet/ExplorerPatcher/releases)，不要从第三方下载站获取安装包。
3. 检查是否已经安装；已安装且满足请求时直接配置，避免为复用 skill 无条件重装或升级。
4. 阅读准备安装版本的发布说明，核对系统支持情况和实际兼容限制。Windows 11 的不同任务栏实现不能直接套用本 skill 的 Windows 10 脚本。

```powershell
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' |
    Select-Object ProductName, DisplayVersion, CurrentBuild, UBR
[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
Get-Process explorer -ErrorAction SilentlyContinue
Test-Path 'C:\Program Files\ExplorerPatcher\ep_setup.exe'
```

命令找不到时先检查用户安装目录和当前进程的 `PATH`。不要为此重新索要 GitHub 密码；公开发布可直接访问，GitHub CLI 可复用已有授权。

## 下载与校验

用 GitHub API 动态读取官方最新正式版，或使用用户指定且兼容的版本。优先使用 `gh api`；没有 GitHub CLI 时可用 `Invoke-RestMethod`。API 匿名限流时优先复用已有登录，不把令牌打印出来或写进 skill、日志与仓库。

```powershell
$release = gh api repos/valinet/ExplorerPatcher/releases/latest | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw '获取官方发布信息失败。' }
$architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
$assetName = switch ($architecture) {
    'X64'   { 'ep_setup.exe' }
    'Arm64' { 'ep_setup_arm64.exe' }
    default { throw "尚未确认此架构的安装包：$architecture" }
}
$asset = @($release.assets | Where-Object name -eq $assetName)
if ($asset.Count -ne 1) { throw '未找到唯一匹配的官方安装包。' }
if ($asset[0].browser_download_url -notlike 'https://github.com/valinet/ExplorerPatcher/releases/download/*') {
    throw '安装包地址不是预期的官方发布地址。'
}
$downloadDirectory = Join-Path (Get-Location) 'work\explorerpatcher'
New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null
$installerPath = Join-Path $downloadDirectory $assetName
Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $installerPath
$expectedDigest = [string]$asset[0].digest
if ($expectedDigest -notmatch '^sha256:[a-fA-F0-9]{64}$') {
    throw '官方 API 没有提供可验证的 SHA-256；先寻找官方校验信息，暂不执行安装。'
}
$actualDigest = 'sha256:' + (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualDigest -ne $expectedDigest.ToLowerInvariant()) { throw '安装包校验失败。' }
Get-AuthenticodeSignature -LiteralPath $installerPath | Select-Object Status, SignerCertificate
```

安装包可能没有 Authenticode 签名。必须如实区分“官方文件哈希匹配”和“数字签名有效”，不能把前者称为后者。哈希不匹配或来源不明时停止。不要自动关闭防护、修改防病毒排除项或绕过 Windows 提示。

## 安装与权限

用户已要求安装时继续执行，不重复索要笼统许可。提前说明安装会短暂重启桌面和任务栏。Windows 10 先运行本 skill 脚本的 `-Action Backup`，记录输出的备份目录；脚本置顶时也会再次备份。脚本命令中的路径须替换为当前 skill 实际目录。

```powershell
$process = Start-Process -FilePath $installerPath -Verb RunAs -WindowStyle Hidden -PassThru
```

Windows 的“用户账户控制”需要本人点击“是”。确实出现 `consent.exe` 或安装启动卡在权限确认时，告诉用户需要完成哪一个系统操作；不要代替用户点击安全桌面，也不要连续重复启动安装程序。用户取消后不自动重试，先报告取消状态。

安装器启动或父进程退出不代表安装成功。等待安装进程结束、桌面恢复，然后联合检查：

- 默认安装目录存在 `ep_setup.exe` 和 `ep_gui.dll`，读取实际文件版本。
- “已安装的应用”中有 ExplorerPatcher 项。检查 HKLM/HKCU 及必要的 WOW6432Node 卸载项。
- 当前用户的 `explorer.exe` 正常运行。标准 x64 安装可检查其加载了 `C:\Windows\dxgi.dll`；读取模块被拒绝时如实记录限制，不能因此重复安装。
- 文件位置可能随版本改变，缺少默认路径时先参考当前版本的安装说明与卸载项。

## Windows 10 主任务栏置顶

使用 [scripts/taskbar-position.ps1](scripts/taskbar-position.ps1)。脚本不安装应用、不重启资源管理器；`Inspect` 只读，`Backup` 只导出原始设置，`Top` 修改当前会话主任务栏并保存到存在的 `StuckRects3` 与 `StuckRectsLegacy`。优先在 PowerShell 7 中运行；若系统执行策略阻止脚本，不擅自修改全机执行策略，改用已允许的环境或属性面板。

```powershell
# 用 skill 的实际目录替换此变量，不要照抄他人的用户名或绝对路径。
$skillDirectory = '<此 skill 的实际目录>'
& (Join-Path $skillDirectory 'scripts\taskbar-position.ps1') -Action Inspect
& (Join-Path $skillDirectory 'scripts\taskbar-position.ps1') -Action Top -WhatIf
& (Join-Path $skillDirectory 'scripts\taskbar-position.ps1') -Action Top
```

关键机制：

- 通过 `FindWindow('Shell_TrayWnd')` 找到主任务栏；`SHAppBarMessage(ABM_GETTASKBARPOS)` 返回实际边缘和坐标。
- 采用官方属性面板使用的消息：`WM_USER + 0x1CA`，`wParam=6`，`lParam=1`，其中边缘 `1` 表示顶部。消息带超时；若当前版本不支持，停止并改用 ExplorerPatcher 属性面板，不连续尝试未知消息。
- 先验证注册表二进制格式，再修改。边缘是偏移 `12` 的 DWORD，矩形坐标位于 `24/28/32/36`；屏幕宽度和任务栏高度取实时结果，不写死分辨率。
- 同时保存存在的两个位置项。这次实际安装中，`StuckRects3` 已置顶但 `StuckRectsLegacy` 仍是底部，导致安装器重启桌面后位置恢复；不能只改一个项。
- 仅修改注册表不等于当前桌面生效；仅移动当前窗口也不等于重登后保留。两者都要检查。

## 验证与失败处理

再次运行 `-Action Inspect`。成功需要实际 `Edge=1`，存在的位置项均为 `Persisted[].Edge=1`，并确认安装文件与版本。重启后验证只有在真正重启后才能声称完成，不为验证擅自重启电脑。

脚本输出 `BackupDirectory`，其中包含变更前的注册表导出和 `before.json`。失败时脚本会尝试恢复本次原始位置与二进制数据；如果恢复失败，应同时报告两项错误。不要无界重试安装、重启桌面或重发消息。

需要人工恢复时，参考备份中的原始边缘，在 ExplorerPatcher“属性 → 任务栏 → 屏幕上的主任务栏位置”恢复；也可导入备份 `.reg` 后，通过属性面板应用，或在用户同意的合适时机重启资源管理器。导入注册表本身不会保证当前窗口立即移动。卸载使用 Windows“已安装的应用”或官方 `ep_setup.exe /uninstall`，仅在用户要求时执行。

完成后用中文简述应用版本、安装状态、当前任务栏位置、设置已保存，以及确有其事的待办或限制。更多配置入口：右键任务栏“属性”，或开始菜单搜索 ExplorerPatcher。

## 已验证实例

在 Windows 10 Pro 22H2、构建 `19045.6456`、x64 环境验证过 `26100.8457.70.3`：官方哈希匹配、安装成功、外壳加载补丁、主任务栏移到顶部，且两个位置项均保存为顶部。此记录是复现依据，不是固定版本要求或对其他构建的兼容承诺。
