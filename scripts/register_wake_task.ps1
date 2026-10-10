<#
.SYNOPSIS
    毎日決まった時刻に PC をスリープから復帰させ、指定時刻まで起こしておくタスク "SolarWake" を登録します。

.DESCRIPTION
    - トリガー      : 毎日 -WakeTime の時刻
    - スリープ解除  : 有効（「タスクを実行するためにスリープを解除する」）
    - 実行内容      : powershell.exe -File "<作業フォルダ>\stay_awake.ps1" -Until <AwakeUntil>
                      → start_solar.bat を起動し、AwakeUntil まで PC のスリープを抑止
    - 電源プラン    : 現在のプランで「スリープ解除タイマーの許可」を AC / バッテリーとも有効化
    - バッテリー駆動時も開始・継続する
    - 実行が遅れた場合（電源オフ中だった等）は可能になり次第実行
    - 同名タスクがあれば上書き
    管理者権限が無い場合は UAC 昇格して自分自身を再実行します。

.PARAMETER WorkDir
    start_solar.bat と stay_awake.ps1 があるフォルダ。省略時は C:\Users\<ユーザー>\OneDrive\パワコンデータ取得

.PARAMETER WakeTime
    スリープ解除する時刻 (HH:mm)。既定は 05:00。

.PARAMETER AwakeUntil
    この時刻 (HH:mm) までスリープさせない。既定は 19:00。WakeTime より後である必要があります。

.PARAMETER RunNow
    登録後すぐにタスクを 1 回起動します。

.PARAMETER Unregister
    タスクを削除します（電源プランの設定は元に戻しません）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\register_wake_task.ps1
    powershell -ExecutionPolicy Bypass -File .\register_wake_task.ps1 -WakeTime 04:30 -AwakeUntil 19:30
    powershell -ExecutionPolicy Bypass -File .\register_wake_task.ps1 -Unregister
#>
[CmdletBinding()]
param(
    [string]$WorkDir = (Join-Path $env:USERPROFILE 'OneDrive\パワコンデータ取得'),
    [string]$UserId = "$env:USERDOMAIN\$env:USERNAME",
    [string]$TaskName = 'SolarWake',
    [string]$WakeTime = '05:00',
    [string]$AwakeUntil = '19:00',
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
        '-TaskName', "`"$TaskName`"",
        '-WakeTime', $WakeTime,
        '-AwakeUntil', $AwakeUntil
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
$wake = [datetime]::ParseExact($WakeTime, 'HH:mm', $null)
$until = [datetime]::ParseExact($AwakeUntil, 'HH:mm', $null)
if ($until -le $wake) {
    throw "AwakeUntil ($AwakeUntil) は WakeTime ($WakeTime) より後の時刻にしてください。"
}
foreach ($name in 'start_solar.bat', 'stay_awake.ps1') {
    $path = Join-Path $WorkDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "$name が見つかりません: $path"
    }
}
$scriptPath = Join-Path $WorkDir 'stay_awake.ps1'

# --- 電源プラン: スリープ解除タイマーを許可 (0=無効, 1=有効, 2=重要なものだけ) ---
# これが無効だと WakeToRun を付けてもタスクで復帰しない
& powercfg.exe /SETACVALUEINDEX SCHEME_CURRENT SUB_SLEEP RTCWAKE 1
& powercfg.exe /SETDCVALUEINDEX SCHEME_CURRENT SUB_SLEEP RTCWAKE 1
& powercfg.exe /SETACTIVE SCHEME_CURRENT
Write-Host '電源プラン: スリープ解除タイマーを許可しました（AC / バッテリー）。'

# --- タスク定義 ---
$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Until $AwakeUntil" `
    -WorkingDirectory $WorkDir

$trigger = New-ScheduledTaskTrigger -Daily -At $wake

$settings = New-ScheduledTaskSettingsSet `
    -WakeToRun `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 23) `
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
    -Description "毎日 $WakeTime にスリープ解除し、$AwakeUntil まで太陽光発電モニタリングを動かし続ける"

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
    Trigger                    = $registered.Triggers[0].StartBoundary
    WakeToRun                  = $s.WakeToRun
    Execute                    = $registered.Actions[0].Execute
    Arguments                  = $registered.Actions[0].Arguments
    DisallowStartIfOnBatteries = $s.DisallowStartIfOnBatteries
    StopIfGoingOnBatteries     = $s.StopIfGoingOnBatteries
    ExecutionTimeLimit         = $s.ExecutionTimeLimit
} | Format-List

Write-Host '有効なスリープ解除タイマー (powercfg /waketimers):'
& powercfg.exe /waketimers

if ($RunNow) {
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 5
    Write-Host '起動中の pythonw プロセス:'
    Get-Process pythonw -ErrorAction SilentlyContinue | Format-Table Id, StartTime, Path -AutoSize
}
