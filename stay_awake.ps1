<#
.SYNOPSIS
    スリープ解除後に呼ばれ、指定時刻（または指定分数）まで PC をスリープさせないようにします。

.DESCRIPTION
    1. start_solar.bat を実行して solar_logger.py / smart_notifier.py を確実に起動する
       （既に動いていれば start_solar.bat 側でスキップされる）
    2. SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED) で終了時刻まで
       アイドルスリープを抑止する。画面は消えてよいので ES_DISPLAY_REQUIRED は付けない。
    スリープ解除タイマーや Wake-on-LAN で起きた直後は、操作が無いと約 2 分で再スリープするため、この抑止が必要。
    このスクリプトが終了すると抑止は解除され、通常の電源設定どおりスリープに戻る。
    呼び出し元: タスク "SolarWake"（-Until）、タスク "SolarResume"（-Minutes）

.PARAMETER Until
    この時刻 (HH:mm) までスリープを抑止します。既に過ぎていれば起動だけして終了します。

.PARAMETER Minutes
    今から指定分数だけスリープを抑止します。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\stay_awake.ps1 -Until 19:00
    powershell -NoProfile -ExecutionPolicy Bypass -File .\stay_awake.ps1 -Minutes 60
#>
[CmdletBinding(DefaultParameterSetName = 'Until')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Until')]
    [string]$Until,

    [Parameter(Mandatory = $true, ParameterSetName = 'Minutes')]
    [ValidateRange(1, 1440)]
    [int]$Minutes
)

$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'Minutes') {
    $end = (Get-Date).AddMinutes($Minutes)
} else {
    $end = [datetime]::ParseExact($Until, 'H:mm', [cultureinfo]::InvariantCulture)
}

# --- モニタリングを起動（二重起動防止は start_solar.bat 側） ---
$batPath = Join-Path $PSScriptRoot 'start_solar.bat'
if (Test-Path -LiteralPath $batPath) {
    # 出力をパイプで受けると、起動した pythonw がハンドルを継承して終わらなくなるので
    # Start-Process で切り離し、cmd.exe 本体の終了だけを待つ（-Wait は子孫まで待つため使わない）
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$batPath`"" `
        -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru
    $p.WaitForExit()
}

if ((Get-Date) -ge $end) { return }

# --- スリープ抑止 ---
Add-Type -Namespace Win32 -Name Power -MemberDefinition @'
[DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
'@
$ES_CONTINUOUS      = [uint32]'0x80000000'
$ES_SYSTEM_REQUIRED = [uint32]'0x00000001'

[void][Win32.Power]::SetThreadExecutionState($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED)
try {
    while ((Get-Date) -lt $end) {
        Start-Sleep -Seconds 60
    }
} finally {
    [void][Win32.Power]::SetThreadExecutionState($ES_CONTINUOUS)
}
