[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Inspect', 'ValidateSource', 'Install', 'Restore')]
    [string]$Action = 'Inspect',
    [string]$SourceDirectory,
    [ValidateSet('Standard', 'Large', 'ExtraLarge')]
    [string]$Size = 'Standard',
    [string]$BackupDirectory
)

$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw '此脚本仅支持 Windows。' }
$installDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Cursors\Windows XI Aero Left Handed'
$roles = @('Arrow','Help','AppStarting','Wait','Crosshair','IBeam','NWPen','No','SizeNS','SizeWE','SizeNWSE','SizeNESW','SizeAll','UpArrow','Hand','Pin','Person')
$files = @('aero_arrow.cur','aero_helpsel.cur','aero_working.ani','aero_busy.ani','','','aero_pen.cur','aero_unavail.cur','aero_ns.cur','aero_ew.cur','aero_nwse.cur','aero_nesw.cur','aero_move.cur','aero_up.cur','aero_link.cur','aero_pin.cur','aero_person.cur')
$variants = @(
    @{Size='Standard';Name='Windows XI Aero Left Handed';Suffix=''},
    @{Size='Large';Name='Windows XI Aero Left Handed (Large)';Suffix='_l'},
    @{Size='ExtraLarge';Name='Windows XI Aero Left Handed (Extra Large)';Suffix='_xl'}
)

if (-not ('LeftCursorSkill.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace LeftCursorSkill {
    public static class Native {
        [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern IntPtr LoadImageW(IntPtr instance, string name, uint type, int width, int height, uint flags);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool DestroyCursor(IntPtr cursor);
        [DllImport("user32.dll", SetLastError=true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool SystemParametersInfoW(uint action, uint parameter, IntPtr value, uint flags);
    }
}
'@
}

function Assert-CursorFile([string]$Path) {
    $handle = [LeftCursorSkill.Native]::LoadImageW([IntPtr]::Zero, $Path, 2, 0, 0, 0x10)
    if ($handle -eq [IntPtr]::Zero) { throw "Windows 无法加载指针：$Path" }
    [void][LeftCursorSkill.Native]::DestroyCursor($handle)
}

function Update-Cursors {
    if (-not [LeftCursorSkill.Native]::SystemParametersInfoW(0x57, 0, [IntPtr]::Zero, 2)) {
        throw ('刷新指针失败，Windows 错误码：' + [Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
}

function Get-SchemeValues([string]$Directory, [string]$Suffix) {
    foreach ($file in $files) {
        if (-not $file) { ''; continue }
        $name = [IO.Path]::GetFileNameWithoutExtension($file) + $Suffix + [IO.Path]::GetExtension($file)
        Join-Path $Directory $name
    }
}

function Get-ConfigurationSnapshot {
    $records = @()
    foreach ($group in @('Cursors','Schemes')) {
        $relative = if ($group -eq 'Cursors') { 'Control Panel\Cursors' } else { 'Control Panel\Cursors\Schemes' }
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($relative)
        $names = if ($group -eq 'Cursors') { @('','Scheme Source') + $roles } else { @($variants | ForEach-Object { $_.Name }) }
        try {
            foreach ($name in $names) {
                $exists = $null -ne $key -and $key.GetValueNames() -contains $name
                $records += [PSCustomObject]@{
                    Group=$group;Name=$name;Exists=$exists
                    Kind=$(if ($exists) { $key.GetValueKind($name).ToString() } else { $null })
                    Value=$(if ($exists) { $key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null })
                }
            }
        } finally { if ($key) { $key.Dispose() } }
    }
    [PSCustomObject]@{Schema=1;Records=$records}
}

function New-ConfigurationBackup {
    $directory = Join-Path $installDirectory ('Backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $snapshot = Get-ConfigurationSnapshot
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $directory 'snapshot.json') -Encoding UTF8
    & reg.exe export 'HKCU\Control Panel\Cursors' (Join-Path $directory 'cursors.reg') /y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw '指针配置导出失败，未应用新方案。' }
    [PSCustomObject]@{Directory=$directory;Snapshot=$snapshot}
}

function Restore-Configuration($Snapshot) {
    if ($Snapshot.Schema -ne 1 -or @($Snapshot.Records).Count -ne 22) { throw '备份结构无效。' }
    $seen = @{}
    foreach ($record in $Snapshot.Records) {
        $allowed = if ($record.Group -eq 'Cursors') { @('','Scheme Source') + $roles } elseif ($record.Group -eq 'Schemes') { @($variants | ForEach-Object { $_.Name }) } else { @() }
        $identity = $record.Group + ':' + $record.Name
        if ($allowed -notcontains $record.Name -or $seen.ContainsKey($identity)) { throw '备份包含非预期字段。' }
        $seen[$identity] = $true
        if ($record.Exists -and $record.Kind -notin @('String','ExpandString','DWord')) { throw '备份含不支持的值类型。' }
    }
    foreach ($record in $Snapshot.Records) {
        $relative = if ($record.Group -eq 'Cursors') { 'Control Panel\Cursors' } else { 'Control Panel\Cursors\Schemes' }
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($relative)
        try {
            if ($record.Exists) {
                $kind = [Enum]::Parse([Microsoft.Win32.RegistryValueKind], $record.Kind)
                $value = if ($record.Kind -eq 'DWord') { [int]$record.Value } else { [string]$record.Value }
                $key.SetValue($record.Name, $value, $kind)
            } else { $key.DeleteValue($record.Name, $false) }
        } finally { $key.Dispose() }
    }
    Update-Cursors
}

if ($Action -eq 'ValidateSource' -or $Action -eq 'Install') {
    if (-not $SourceDirectory) { throw '请指定 SourceDirectory。' }
    $SourceDirectory = (Resolve-Path -LiteralPath $SourceDirectory).Path
    $count = 0
    foreach ($variant in $variants) {
        foreach ($path in @(Get-SchemeValues $SourceDirectory $variant.Suffix | Where-Object { $_ })) {
            Assert-CursorFile $path
            $count++
        }
    }
    if ($Action -eq 'ValidateSource') {
        [PSCustomObject]@{Valid=$true;ValidatedCursorFiles=$count} | ConvertTo-Json -Compress
        return
    }
    if (-not $PSCmdlet.ShouldProcess('当前用户的指针文件与方案', "备份、安装三种尺寸并应用 $Size")) { return }
    $backup = New-ConfigurationBackup
    try {
        foreach ($variant in $variants) {
            foreach ($sourceFile in @(Get-SchemeValues $SourceDirectory $variant.Suffix | Where-Object { $_ })) {
                $target = Join-Path $installDirectory (Split-Path $sourceFile -Leaf)
                $sourceHash = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash
                if (Test-Path -LiteralPath $target) {
                    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $sourceHash) { throw "同名文件内容不同，未覆盖：$target" }
                } else { Copy-Item -LiteralPath $sourceFile -Destination $target }
                if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $sourceHash) { throw '文件复制校验失败。' }
            }
        }
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Control Panel\Cursors\Schemes')
        try {
            foreach ($variant in $variants) {
                $values = @(Get-SchemeValues $installDirectory $variant.Suffix)
                $key.SetValue($variant.Name, ($values -join ','), [Microsoft.Win32.RegistryValueKind]::String)
            }
        } finally { $key.Dispose() }
        $selected = $variants | Where-Object { $_.Size -eq $Size }
        $activeValues = @(Get-SchemeValues $installDirectory $selected.Suffix)
        $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Control Panel\Cursors')
        try {
            for ($index=0; $index -lt $roles.Count; $index++) {
                $key.SetValue($roles[$index], $activeValues[$index], [Microsoft.Win32.RegistryValueKind]::ExpandString)
            }
            $key.SetValue('', $selected.Name, [Microsoft.Win32.RegistryValueKind]::String)
            $key.SetValue('Scheme Source', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
        } finally { $key.Dispose() }
        Update-Cursors
        $current = Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Cursors'
        for ($index=0; $index -lt $roles.Count; $index++) {
            if ($current.($roles[$index]) -cne $activeValues[$index]) { throw '应用后的指针角色验证失败。' }
        }
    } catch {
        $failure = $_.Exception.Message
        try { Restore-Configuration $backup.Snapshot }
        catch { throw ($failure + '；恢复失败：' + $_.Exception.Message + '；备份：' + $backup.Directory) }
        throw ($failure + '；原配置已恢复，备份：' + $backup.Directory)
    }
    [PSCustomObject]@{Installed=$true;ActiveScheme=$selected.Name;RegisteredSchemes=3;ValidatedCursorFiles=$count;RefreshSucceeded=$true;BackupDirectory=$backup.Directory} | ConvertTo-Json -Compress
    return
}

if ($Action -eq 'Restore') {
    if (-not $BackupDirectory) { throw '请指定 BackupDirectory。' }
    $snapshot = Get-Content -LiteralPath (Join-Path $BackupDirectory 'snapshot.json') -Raw | ConvertFrom-Json
    if (-not $PSCmdlet.ShouldProcess('当前用户的指针配置', '备份当前状态并恢复指定备份')) { return }
    $backup = New-ConfigurationBackup
    try { Restore-Configuration $snapshot }
    catch {
        $failure = $_.Exception.Message
        try { Restore-Configuration $backup.Snapshot }
        catch { throw ($failure + '；恢复操作回退失败：' + $_.Exception.Message) }
        throw ($failure + '；恢复操作已回退。')
    }
    [PSCustomObject]@{Restored=$true;RefreshSucceeded=$true;BackupDirectory=$backup.Directory} | ConvertTo-Json -Compress
    return
}

$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Control Panel\Cursors\Schemes')
$count = 0
try {
    foreach ($variant in $variants) {
        if (-not $key) { throw '左手指针方案尚未安装。' }
        $scheme = [string]$key.GetValue($variant.Name)
        $expected = @(Get-SchemeValues $installDirectory $variant.Suffix)
        if ($scheme -cne ($expected -join ',')) { throw "指针方案不存在或路径不符合预期：$($variant.Name)" }
        foreach ($path in @($expected | Where-Object { $_ })) { Assert-CursorFile $path; $count++ }
    }
} finally { if ($key) { $key.Dispose() } }
$current = Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Cursors'
$activeName = (Get-Item -LiteralPath 'HKCU:\Control Panel\Cursors').GetValue('')
$activeVariant = $variants | Where-Object { $_.Name -eq $activeName }
if ($activeVariant) {
    $expected = @(Get-SchemeValues $installDirectory $activeVariant.Suffix)
    for ($index=0; $index -lt $roles.Count; $index++) {
        if ($current.($roles[$index]) -cne $expected[$index]) { throw '当前角色配置与方案名称不一致。' }
    }
}
[PSCustomObject]@{Valid=$true;ActiveScheme=$activeName;LeftHandedActive=[bool]$activeVariant;RegisteredSchemes=3;ValidatedCursorFiles=$count} | ConvertTo-Json -Compress
