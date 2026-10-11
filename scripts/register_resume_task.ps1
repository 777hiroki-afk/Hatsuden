<#
.SYNOPSIS
    スリープから復帰するたびに、一定時間 PC を起こしておくタスク "SolarResume" を登録します。

.DESCRIPTION
    スマホから Wake-on-LAN で起こした PC は、操作が無いと約 2 分で再スリープする。
    復帰時に必ず記録されるイベント（システムログ / Microsoft-Windows-Power-Troubleshooter / ID 1）を
    トリガーにして stay_awake.ps1 -Minutes <分> を実行し、その間スリープを抑止する。
    - 復帰の原因（WoL / キーボード / タイマー）は区別しない
    - 実行内容      : powershell.exe -File "<作業フォルダ>\stay_awake.ps1" -Minutes <AwakeMinutes>
    - バッテリー駆動時も開始・継続する
    - 実行中に再度復帰した場合は新しいインスタンスを起動しない（IgnoreNew）
    - 同名タスクがあれば上書き
    管理者権限が無い場合は UAC 昇格して自分自身を再実行します。

.PARAMETER WorkDir
    start_solar.bat と stay_awake.ps1 があるフォルダ。省略時は C:\Users\<ユーザー>\OneDrive\パワコンデータ取得

.PARAMETER AwakeMinutes
    復帰後にスリープを抑止する分数。既定は 20（復帰後に Claude などの定期タスクが動く時間を確保できればよい）。

.PARAMETER RunNow
    登録後すぐにタスクを 1 回起動します（動作確認用）。

.PARAMETER Unregister
    タスクを削除します。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\register_resume_task.ps1
    powershell -ExecutionPolicy Bypass -File .\register_resume_task.ps1 -AwakeMinutes 60
    powershell -ExecutionPolicy Bypass -File .\register_resume_task.ps1 -Unregister
#>
[CmdletBinding()]
param(
    [string]$WorkDir = (Join-Path $env:USERPROFILE 'OneDrive\パワコンデータ取得'),
    [string]$UserId = "$env:USERDOMAIN\$env:USERNAME",
    [string]$TaskName = 'SolarResume',
    [ValidateRange(1, 1440)]
    [int]$AwakeMinutes = 20,
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
        '-AwakeMinutes', $AwakeMinutes
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
foreach ($name in 'start_solar.bat', 'stay_awake.ps1') {
    $path = Join-Path $WorkDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "$name が見つかりません: $path"
    }
}
$scriptPath = Join-Path $WorkDir 'stay_awake.ps1'

# --- タスク定義 ---
$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Minutes $AwakeMinutes" `
    -WorkingDirectory $WorkDir

# New-ScheduledTaskTrigger はイベントトリガーを作れないので CIM で直接作る
$triggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace 'Root/Microsoft/Windows/TaskScheduler'
$trigger = New-CimInstance -CimClass $triggerClass -ClientOnly
$trigger.Subscription = @'
<QueryList><Query Id="0" Path="System"><Select Path="System">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]</Select></Query></QueryList>
'@
$trigger.Enabled = $true

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes ($AwakeMinutes + 10)) `
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
    -Description "スリープ復帰時に $AwakeMinutes 分間スリープを抑止し、太陽光発電モニタリングを動かす"

# --- 登録（同名タスクは上書き） ---
Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
Write-Host "タスク '$TaskName' を登録しました。" -ForegroundColor Green

# --- 確認表示 ---
$registered = Get-ScheduledTask -TaskName $TaskName
$s = $registered.Settings
[pscustomobject]@{
    TaskName           = $registered.TaskName
    State              = $registered.State
    User               = $registered.Principal.UserId
    Trigger            = $registered.Triggers[0].Subscription
    Execute            = $registered.Actions[0].Execute
    Arguments          = $registered.Actions[0].Arguments
    ExecutionTimeLimit = $s.ExecutionTimeLimit
} | Format-List

Write-Host '直近のスリープ復帰イベント:'
Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Power-Troubleshooter'; Id = 1 } `
    -MaxEvents 3 -ErrorAction SilentlyContinue | Format-Table TimeCreated, Id -AutoSize

if ($RunNow) {
    Start-ScheduledTask -TaskName $TaskName
    Start-Sleep -Seconds 5
    Write-Host 'スリープ抑止の状況 (powercfg /requests):'
    & powercfg.exe /requests
}
