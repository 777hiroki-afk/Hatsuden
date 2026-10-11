# 引き継ぎ: スリープ解除スケジューリング（SolarWake）

前提は [HANDOVER.md](HANDOVER.md)（プロジェクト全体）を参照。

## 目的

PC がスリープすると `solar_logger.py`（5 分ごと）と `smart_notifier.py`（10 分ごと）が止まる。
毎日決まった時刻に PC をスリープから起こし、日中は起こしておきたい。

## 実装済み（ブランチ `claude/zealous-brown-sjjrds`）

| ファイル | 置き場所（PC） | 内容 |
|---|---|---|
| `stay_awake.ps1` | 作業フォルダ（`start_solar.bat` と同じ） | `start_solar.bat` を実行し、`-Until` の時刻まで `SetThreadExecutionState` でスリープを抑止 |
| `scripts/register_wake_task.ps1` | どこでも | タスク `SolarWake` を登録。電源プランの「スリープ解除タイマーの許可」を AC/DC とも有効化 |

`SolarWake` タスクの内容:

- トリガー: 毎日 `-WakeTime`（既定 05:00）
- WakeToRun（スリープ解除して実行）、バッテリー時も実行、StartWhenAvailable、IgnoreNew、実行時間制限 23 時間
- 実行: `powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "<作業フォルダ>\stay_awake.ps1" -Until <AwakeUntil>`（既定 19:00）
- プリンシパル: 現在のユーザー / Interactive / Limited（ログオン中のみ動作。ロック中は OK）
- 管理者権限が無ければ UAC 昇格して自分を再実行

時刻は `H:mm` / `HH:mm` どちらでも可。`AwakeUntil` は `WakeTime` より後であること。

## 検証状況

- Linux 上の PowerShell 7 で構文解析・時刻パース・フラグ計算のみ確認済み
- **Windows 上では未実行**（タスク登録・スリープ解除・スリープ抑止はすべて未検証）

## 次のセッション（PC ローカル）でやること

1. ブランチの最新を作業フォルダ `C:\Users\777hi\OneDrive\パワコンデータ取得` に反映
   - git 管理でなければ raw から取得（リポジトリは public）:
     ```powershell
     cd "$env:USERPROFILE\OneDrive\パワコンデータ取得"
     $base = "https://raw.githubusercontent.com/777hiroki-afk/Hatsuden/claude/zealous-brown-sjjrds"
     Invoke-WebRequest "$base/stay_awake.ps1" -OutFile ".\stay_awake.ps1"
     Invoke-WebRequest "$base/scripts/register_wake_task.ps1" -OutFile ".\register_wake_task.ps1"
     ```
2. `powercfg /a` でスリープ状態を確認。「スタンバイ (S0 低電力アイドル)」（モダンスタンバイ）だとスリープ解除タイマーが効かないことがある
3. 5 分後に起きる設定でテスト登録（UAC はユーザーが「はい」を押す。結果は昇格後の別ウィンドウに出るので、
   `schtasks /Query /TN "SolarWake" /FO LIST /V` と `powercfg /waketimers` で確認する）:
   ```powershell
   $wake  = (Get-Date).AddMinutes(5).ToString('HH:mm')
   $until = (Get-Date).AddMinutes(35).ToString('HH:mm')
   powershell -ExecutionPolicy Bypass -File .\register_wake_task.ps1 -WakeTime $wake -AwakeUntil $until
   ```
4. ユーザーが手動でスリープ → 指定時刻に復帰するかユーザーが目視確認（スリープ中は Claude も止まる）
5. 復帰後に確認:
   - `powercfg /requests` の SYSTEM 欄に `powershell.exe` があるか（スリープ抑止）
   - `Get-Process pythonw` が 2 つあるか
   - `Get-ScheduledTaskInfo SolarWake` の LastTaskResult が 0（実行中なら 267009）
6. 問題なければ本番時刻で再登録（同名タスクは上書き）:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\register_wake_task.ps1 -WakeTime 5:00 -AwakeUntil 19:00
   ```
7. 直した点があればブランチ `claude/zealous-brown-sjjrds` にコミット・プッシュ

## 起きなかった場合の確認ポイント

- `powercfg /waketimers` に SolarWake が出ているか（出なければタスクの WakeToRun / 電源プランの RTCWAKE を確認）
- `powercfg /q SCHEME_CURRENT SUB_SLEEP RTCWAKE` が AC/DC とも 1 か
- 電源プランを後から切り替えると RTCWAKE 設定は引き継がれない（再登録で再設定される）
- BIOS/UEFI 側でウェイク機能が無効になっていないか
- 起きたがすぐ寝る場合: `stay_awake.ps1` が動いているか（タスクの履歴 / `Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"` の CommandLine）

## 注意（ファイル形式）

`.ps1` / `.bat` は CRLF。`.ps1` は日本語を含むので UTF-8 **BOM 付き**で保存すること（Windows PowerShell 5.1 が BOM なしを Shift-JIS と誤認する）。
`.gitattributes` で `*.ps1 -text` 指定済み。

## スマホから任意のタイミングで起こす（Wake-on-LAN）

PC（有線 `イーサネット` = Realtek PCIe GbE Family Controller）で設定済み（2026-10-11）:

- `Set-NetAdapterPowerManagement -WakeOnMagicPacket Enabled`、`powercfg /deviceenablewake` 済み（`wake_armed` に表示される）
- 詳細設定: Wake on Magic Packet / Shutdown Wake-On-Lan = Enabled
- `powercfg /a`: スタンバイ (S3) 対応・モダンスタンバイ非対応 → スリープ解除タイマーも WoL も効く。高速スタートアップは無効
- **iPhone（Mocha WOL）からスリープ解除できることを確認済み**（2026-10-11）。設定:
  - IP Address: `192.168.71.255`（家の LAN は `192.168.68.0/22`、ルーター `192.168.68.1`）
  - Mac Address: PC の有線アダプターの MAC（`Get-NetAdapter` で確認）/ WOL Port: `9`
  - **WOL Broadcast: オフ**（オンだとアプリが送信先を自動算出し `192.0.0.6` に送ってしまい届かない）
  - `255.255.255.255` も同じ理由で届かなかった
- 外出先から起こすには家の中の中継（ルーターの WoL / VPN / 将来の Home Assistant）が必要
- 未対応: WoL で起きた後は約 2 分で再スリープする（`stay_awake.ps1` を起動する仕組みは未実装）
