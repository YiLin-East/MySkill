---
name: left-handed-cursors-setup
description: 在 Windows 上从 win11-aero-left-cursors 仓库下载、校验、安装并应用左手鼠标指针，支持标准、大号、特大号以及原始配置备份与恢复。适用于左撇子镜像指针安装或切换；不默认交换鼠标左右键或安装快捷键服务。
---

# 左手鼠标指针安装与配置

把 Windows Aero 镜像指针安装到当前用户目录，注册三种尺寸，并立即应用用户选择的方案。默认标准尺寸，保留鼠标主按键和其他系统设置。全程用中文说明结果。

## 获取与核对来源

- 用户指定自己的仓库时优先使用该仓库；本次来源是 [YiLin-East/win11-aero-left-cursors](https://github.com/YiLin-East/win11-aero-left-cursors)，上游是 [Microtribute/win11-aero-left-cursors](https://github.com/Microtribute/win11-aero-left-cursors)。在其他用户环境不要把此账号当作他们的账号。
- 先阅读所选仓库的 README、三个 `.inf` 和适用的 `AGENTS.md`。项目声明支持 Windows 7、8、10、11；本 skill 实测环境是 Windows 10，不能声称其他系统也已实测。
- 源仓库的三种方案为 `Windows XI Aero Left Handed`、`Windows XI Aero Left Handed (Large)`、`Windows XI Aero Left Handed (Extra Large)`。分别对应空后缀、`_l`、`_xl`。
- 通过 HTTPS 克隆或下载官方源码包，不从不明下载站获取。记录实际提交号；没有 GitHub CLI 也可使用 Git。公开仓库不需要索要账户密码。

```powershell
$sourceDirectory = Join-Path (Get-Location) 'work\win11-aero-left-cursors'
git clone --depth 1 https://github.com/YiLin-East/win11-aero-left-cursors.git $sourceDirectory
if ($LASTEXITCODE -ne 0) { throw '下载左手指针仓库失败。' }
git -C $sourceDirectory rev-parse HEAD
```

目录已存在时先检查其远端和修改状态，不覆盖用户工作。仅需更新时按当前授权处理。

## 安装方式

推荐使用附带的 [scripts/left-cursors.ps1](scripts/left-cursors.ps1)，在 PowerShell 7 的当前用户会话运行。脚本不需要管理员权限，将文件保存到 `%LOCALAPPDATA%\Microsoft\Windows\Cursors\Windows XI Aero Left Handed`，等效注册 INF 中的用户方案，但不写入 Windows 系统目录。

```powershell
$skillDirectory = '<此 skill 的实际目录>'
$helper = Join-Path $skillDirectory 'scripts\left-cursors.ps1'
& $helper -Action ValidateSource -SourceDirectory $sourceDirectory
& $helper -Action Install -SourceDirectory $sourceDirectory -Size Standard -WhatIf
& $helper -Action Install -SourceDirectory $sourceDirectory -Size Standard
& $helper -Action Inspect
```

`Size` 可选 `Standard`、`Large`、`ExtraLarge`。安装总是注册全部三种尺寸，应用其中一种。再次切换尺寸可复用同一来源执行 `Install`；同名文件内容不同时脚本会停止，避免覆盖影响已有方案，更新版本应先安排文件备份或使用独立目录，而非直接强制覆盖。

安装前备份当前指针注册表，并单独记录本脚本会修改的值是否原本存在及其类型，避免用 `reg import` 误以为能删除后来新增的值。脚本输出 `BackupDirectory`，备份位于用户本机，不上传到技能仓库。不能覆盖最早备份，尤其不能把再次安装前的左手方案当作第一次安装前的系统方案。

若用户偏好项目原始安装方式，可右键三个 INF 分别选择“安装”，再到“控制面板 → 鼠标 → 指针”选择方案并应用；按系统提示处理权限确认。此方式无需再运行脚本重复安装。

## 必须保留的细节

- 方案按 17 个槽位排列：`Arrow, Help, AppStarting, Wait, Crosshair, IBeam, NWPen, No, SizeNS, SizeWE, SizeNWSE, SizeNESW, SizeAll, UpArrow, Hand, Pin, Person`。
- `Crosshair`、`IBeam` 使用空字符串，让 Windows 使用默认资源；不能少掉槽位造成后续角色错位。
- 注册表 `Hand` 对应 `aero_link`，`NWPen` 对应 `aero_pen`。INF 内字符串变量 `%Hand%` 指的是笔，不应按同名直接映射注册表 `Hand`。
- 当前方案名称写入 `HKCU\Control Panel\Cursors` 默认值，方案来源写入 `Scheme Source=1`，三个方案注册到其 `Schemes` 子项。角色路径使用 `REG_EXPAND_SZ`。
- 先使用 `LoadImageW(IMAGE_CURSOR, LR_LOADFROMFILE)` 验证全部 45 个文件能被 Windows 加载，复制后再比对 SHA-256。复制哈希一致只验证复制过程，不能宣称文件带数字签名。
- 应用时调用 `SystemParametersInfoW(SPI_SETCURSORS=0x57, 0, NULL, SPIF_SENDCHANGE=2)`。本次环境传 `3` 返回失败，`2` 成功；注册表已写入仍需检查刷新调用返回值，不能只凭路径宣称当前桌面已刷新。
- 脚本输出刷新成功及配置检查结果；没有重新登录或重启就不能声称已验证重登后的外观。

## 验证、恢复与边界

`ValidateSource` 仅验证源文件能否加载，`Inspect` 仅检查当前注册配置、三种方案和文件，不更改设置。`Inspect` 成功应显示 `Valid=true`、`RegisteredSchemes=3`、`ValidatedCursorFiles=45`；确认当前方案名称符合用户选择，刷新调用成功后可请用户观察箭头方向。

恢复到某一次安装之前的设置：

```powershell
& $helper -Action Restore -BackupDirectory '<需要恢复的那次备份目录>' -WhatIf
& $helper -Action Restore -BackupDirectory '<需要恢复的那次备份目录>'
```

恢复会先备份当前配置，再还原目标备份中记录的值，删除目标时点不存在而由安装添加的值，并刷新指针。安装失败时脚本尝试同样恢复，失败则报告原始错误与恢复错误。备份只覆盖指针配置，不涉及鼠标速度、主按键和任务栏。恢复后保留指针文件，以免其他方案或备份仍引用这些路径；只有用户要求卸载并确认无引用后才清理。

只更换左手指针不等于交换左右键。仓库中的 `swap_primary_button.ahk` 会同时交换主按键和方案，仅在用户要求快捷切换时再处理 AutoHotkey 版本、快捷键与启动方式。本次仓库 README 写的是 `Win+F12`，实际脚本绑定 `!^+F12`，即 **Alt+Ctrl+Shift+F12**，应以实际源码为准，不能未经核对就承诺快捷键可用或安装开机服务。

## 已验证实例

Windows 10 Pro 22H2、x64 上，仓库提交 `f61d3528496ff68116b766e57d4731eb582c98e0` 的全部 45 个文件可被 Windows 加载；三个方案注册成功，标准尺寸立即应用。此记录不固定未来下载版本，也不包含 AutoHotkey 快捷切换的验证。
