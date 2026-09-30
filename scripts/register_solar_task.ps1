<#
.SYNOPSIS
    start_solar.bat をログオン時に自動実行するタスク "SolarMonitor" を登録します。

.DESCRIPTION
    - トリガー      : 現在のユーザーのログオン時
    - 実行内容      : cmd.exe /c "<作業フォルダ>\start_solar.bat"
    - 作業フォルダ  : start_solar.bat のあるフォルダ
    - バッテリー駆動時も開始・継続する（AC電源判定なし）
    - 実行時間制限なし（既定の 3 日で停止しない）
    - 同名タスクがあれば上書き
    管理者権限が無い場合は UAC 昇格して自分自身を再実行します。

.PARAMETER WorkDir
    start_solar.bat があるフォルダ。省略時は C:\Users\<ユーザー>\OneDrive\パワコンデータ取得

.PARAMETER RunNow
    登録後すぐにタスクを 1 回起動します。

.PARAMETER Unregister
    タスクを削除します。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\register_solar_task.ps1
    powershell -ExecutionPolicy Bypass -File .\register_solar_task.ps1 -RunNow
    powershell -ExecutionPolicy Bypass -File .\register_solar_task.ps1 -Unregister
#>
[CmdletBinding()]
param(
    [string]$WorkDir = (Join-Path $env:USERPROFILE 'OneDrive\パワコンデータ取得'),
    [string]$UserId = "$env:USERDOMAIN\$env:USERNAME",
    [string]$TaskName = 'SolarMonitor',
    [switch]$RunNow,
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'

# --- 管理者権限チェック（無ければ昇格して再実行） ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '管理者権限で再実行します（UAC の確認が表示されます）...'
    # 昇格後も元のユーザー・フォルダを使うよう明示的に引き継ぐ
    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit',
        '-File', "`"$PSCommandPath`"",
        '-WorkDir', "`"$WorkDir`"",
        '-UserId', "`"$UserId`"",
        '-TaskName', "`"$TaskName`""
    )
    if ($RunNow) { $argList += '-RunNow' }
    if ($Unregister) { $argList += '-Unregister' }
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    return
}

# --- 削除モード ---
if ($Unregister) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "タスク '$TaskName' を削除しました。"
    } else {
        Write-Host "タスク '$TaskName' は登録されていません。"
    }
    return
}

# --- 入力チェック ---
$batPath = Join-Path $WorkDir 'start_solar.bat'
if (-not (Test-Path -LiteralPath $batPath)) {
    throw "start_solar.bat が見つかりません: $batPath"
}

# --- タスク定義 ---
$action = New-ScheduledTaskAction `
    -Execute 'cmd.exe' `
    -Argument "/c `"$batPath`"" `
    -WorkingDirectory $WorkDir

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserId
# ログオン直後はネットワーク/OneDrive の準備が整っていないことがあるので少し待つ
$trigger.Delay = 'PT1M'

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal `
    -UserId $UserId `
    -LogonType Interactive `
    -RunLevel Limited

$task = New-ScheduledTask `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description '太陽光発電モニタリング (solar_logger.py / smart_notifier.py) をログオン時に起動'

# --- 登録（同名タスクは上書き） ---
Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
Write-Host "タスク '$TaskName' を登録しました。" -ForegroundColor Green

# --- 確認表示 ---
$registered = Get-ScheduledTask -TaskName $TaskName
$s = $registered.Settings
[pscustomobject]@{
    TaskName                   = $registered.TaskName
    State                      = $registered.State
    User                       = $registered.Principal.UserId
    Execute                    = $registered.Actions[0].Execute
    Arguments                  = $registered.Actions[0].Arguments
    WorkingDirectory           = $registered.Actions[0].WorkingDirectory
    DisallowStartIfOnBatteries = $s.DisallowStartIfOnBatteries
    StopIfGoingOnBatteries     = $s.StopIfGoingOnBatteries
    ExecutionTimeLimit         = $s.ExecutionTimeLimit
} | Format-List

if ($RunNow) {
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 5
    Write-Host '起動中の pythonw プロセス:'
    Get-Process pythonw -ErrorAction SilentlyContinue | Format-Table Id, StartTime, Path -AutoSize
}
