[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Inspect', 'Backup', 'Top')]
    [string]$Action = 'Inspect',
    [string]$BackupDirectory
)

$ErrorActionPreference = 'Stop'
$build = [int](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuild
if ($build -lt 10240 -or $build -ge 22000) {
    throw '此脚本仅支持 Windows 10 原生主任务栏；其他系统请使用对应版本的属性面板。'
}

if (-not ('ExplorerPatcherSkill.TaskbarNative' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace ExplorerPatcherSkill {
    public static class TaskbarNative {
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)]
        public struct APPBARDATA {
            public uint Size;
            public IntPtr Window;
            public uint CallbackMessage;
            public uint Edge;
            public RECT Rectangle;
            public IntPtr Parameter;
        }
        [DllImport("user32.dll", CharSet=CharSet.Unicode)]
        public static extern IntPtr FindWindow(string className, string title);
        [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wparam, IntPtr lparam, uint flags, uint timeout, out UIntPtr result);
        [DllImport("shell32.dll", SetLastError=true)]
        public static extern UIntPtr SHAppBarMessage(uint message, ref APPBARDATA data);
    }
}
'@
}

function Get-TaskbarState {
    $window = [ExplorerPatcherSkill.TaskbarNative]::FindWindow('Shell_TrayWnd', $null)
    if ($window -eq [IntPtr]::Zero) { throw '当前会话没有可操作的主任务栏。' }
    $data = New-Object ExplorerPatcherSkill.TaskbarNative+APPBARDATA
    $data.Size = [Runtime.InteropServices.Marshal]::SizeOf($data)
    $data.Window = $window
    if ([ExplorerPatcherSkill.TaskbarNative]::SHAppBarMessage(5, [ref]$data) -eq [UIntPtr]::Zero) {
        throw '无法读取任务栏的实际位置。'
    }
    return $data
}

function Set-TaskbarEdge([uint32]$Edge) {
    $window = [ExplorerPatcherSkill.TaskbarNative]::FindWindow('Shell_TrayWnd', $null)
    $messageResult = [UIntPtr]::Zero
    $result = [ExplorerPatcherSkill.TaskbarNative]::SendMessageTimeout(
        $window, 0x400 + 0x1CA, [UIntPtr]6, [IntPtr]([int]$Edge), 2, 10000, [ref]$messageResult)
    if ($result -eq [IntPtr]::Zero) { throw '任务栏未响应位置设置；请改用属性面板，不要连续重试。' }
    $state = Get-TaskbarState
    if ($state.Edge -ne $Edge) { throw "任务栏位置验证失败，实际边缘为 $($state.Edge)。" }
    return $state
}

function Get-SavedPositions {
    foreach ($name in @('StuckRects3', 'StuckRectsLegacy')) {
        $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\' + $name
        if (-not (Test-Path -LiteralPath $path)) { continue }
        [byte[]]$bytes = (Get-ItemProperty -LiteralPath $path -Name Settings).Settings
        if ($bytes.Length -lt 40 -or [BitConverter]::ToInt32($bytes, 0) -ne $bytes.Length -or
            [BitConverter]::ToInt32($bytes, 4) -ne -2 -or [BitConverter]::ToUInt32($bytes, 12) -gt 3) {
            throw "注册表格式不符合预期，未修改：$name"
        }
        [PSCustomObject]@{Name=$name;Path=$path;Bytes=$bytes;Edge=[BitConverter]::ToUInt32($bytes, 12)}
    }
}

$before = Get-TaskbarState
$originals = @(Get-SavedPositions)
if ($originals.Count -eq 0) { throw '没有找到可验证的任务栏位置记录。' }
$positionNames = @('Left', 'Top', 'Right', 'Bottom')
$backupUsed = $null

if ($Action -in @('Backup', 'Top') -and $PSCmdlet.ShouldProcess('当前用户的主任务栏和位置记录', $(if ($Action -eq 'Backup') {'备份设置'} else {'备份后置顶并保存'}))) {
    if ([string]::IsNullOrWhiteSpace($BackupDirectory)) {
        $BackupDirectory = Join-Path $env:LOCALAPPDATA ('ExplorerPatcher\SkillBackups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N'))
    }
    # 单次备份使用独立目录，已有备份不能被覆盖。
    if (Test-Path -LiteralPath $BackupDirectory) { throw '备份目录已存在，请指定新的空路径。' }
    $backupUsed = (New-Item -ItemType Directory -Path $BackupDirectory).FullName
    foreach ($original in $originals) {
        $nativeKey = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\' + $original.Name
        & reg.exe export $nativeKey (Join-Path $backupUsed ($original.Name + '.reg')) /y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "备份失败，未移动任务栏：$($original.Name)" }
    }
    [PSCustomObject]@{Edge=$before.Edge;Position=$positionNames[$before.Edge];Bounds=$before.Rectangle} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backupUsed 'before.json') -Encoding UTF8

    if ($Action -eq 'Top') { try {
        $topState = Set-TaskbarEdge 1
        foreach ($original in $originals) {
            [byte[]]$updated = $original.Bytes.Clone()
            [BitConverter]::GetBytes([uint32]1).CopyTo($updated, 12)
            [BitConverter]::GetBytes($topState.Rectangle.Left).CopyTo($updated, 24)
            [BitConverter]::GetBytes($topState.Rectangle.Top).CopyTo($updated, 28)
            [BitConverter]::GetBytes($topState.Rectangle.Right).CopyTo($updated, 32)
            [BitConverter]::GetBytes($topState.Rectangle.Bottom).CopyTo($updated, 36)
            Set-ItemProperty -LiteralPath $original.Path -Name Settings -Value $updated -Type Binary
        }
        $saved = @(Get-SavedPositions)
        if (@($saved | Where-Object Edge -ne 1).Count -gt 0 -or (Get-TaskbarState).Edge -ne 1) {
            throw '任务栏实际位置或保存结果不符合顶部设置。'
        }
    } catch {
        $failure = $_.Exception.Message
        $rollbackErrors = @()
        try { $null = Set-TaskbarEdge $before.Edge } catch { $rollbackErrors += $_.Exception.Message }
        foreach ($original in $originals) {
            try { Set-ItemProperty -LiteralPath $original.Path -Name Settings -Value $original.Bytes -Type Binary }
            catch { $rollbackErrors += $_.Exception.Message }
        }
        if ($rollbackErrors.Count -gt 0) { throw ($failure + '；恢复时遇到：' + ($rollbackErrors -join '；')) }
        throw ($failure + '；已恢复本次原始位置和记录。')
    } }
}

$final = Get-TaskbarState
[PSCustomObject]@{
    Action=$Action
    Edge=$final.Edge
    Position=$positionNames[$final.Edge]
    Bounds=$final.Rectangle
    Persisted=@(Get-SavedPositions | Select-Object Name, Edge)
    BackupDirectory=$backupUsed
} | ConvertTo-Json -Depth 5 -Compress
