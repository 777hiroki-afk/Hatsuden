# Hatsuden — 太陽光発電モニタリング

ダイヤゼブラ電機 EIBS7（EHF-S99MP5B）から ECHONET Lite でデータを取得し、CSV 保存・Gmail 通知を行う。
詳細な経緯・環境は [docs/HANDOVER.md](docs/HANDOVER.md) を参照。

## start_solar.bat

`solar_logger.py` と `smart_notifier.py` を `pythonw` でバックグラウンド起動する。

- 自分自身のフォルダ（`%~dp0`）に移動するので、フォルダ名をハードコードしない
- 同じスクリプトの `pythonw` が既に動いていれば起動をスキップ（二重起動防止）
- 日本語を含まない ASCII のみ（cmd の文字コード問題を避けるため）

## Phase 1: ログオン時の自動起動（タスクスケジューラ）

`scripts/register_solar_task.ps1` を PC の任意の場所に置き、PowerShell で実行する。

```powershell
# 登録（管理者権限が無ければ UAC 昇格して再実行される）
powershell -ExecutionPolicy Bypass -File .\register_solar_task.ps1

# 登録してすぐ 1 回起動
powershell -ExecutionPolicy Bypass -File .\register_solar_task.ps1 -RunNow

# フォルダが既定と違う場合
powershell -ExecutionPolicy Bypass -File .\register_solar_task.ps1 -WorkDir "D:\solar"

# 削除
powershell -ExecutionPolicy Bypass -File .\register_solar_task.ps1 -Unregister
```

登録内容: タスク名 `SolarMonitor` / ログオン時（1 分遅延）/ `cmd.exe /c start_solar.bat` /
バッテリー駆動でも実行 / 実行時間制限なし / 多重起動しない / 同名タスクは上書き。

動作確認:

```powershell
schtasks /Query /TN "SolarMonitor" /FO LIST /V
Get-Process pythonw
```

## 決まった時刻にスリープ解除（タスクスケジューラ + スリープ解除タイマー）

PC がスリープ中は `solar_logger.py`（5 分ごと）や `smart_notifier.py`（10 分ごと）も止まる。
`scripts/register_wake_task.ps1` で、毎日決まった時刻に PC を起こし、指定時刻まで起こしておくタスク `SolarWake` を登録する。

`stay_awake.ps1` は `start_solar.bat` と同じフォルダ（作業フォルダ）に置くこと。

```powershell
# 登録（既定: 毎日 05:00 に復帰し、19:00 までスリープさせない）
powershell -ExecutionPolicy Bypass -File .\register_wake_task.ps1

# 時刻を変える
powershell -ExecutionPolicy Bypass -File .\register_wake_task.ps1 -WakeTime 04:30 -AwakeUntil 19:30

# 削除
powershell -ExecutionPolicy Bypass -File .\register_wake_task.ps1 -Unregister
```

仕組み:

1. タスクに「タスクを実行するためにスリープを解除する」(WakeToRun) を付け、電源プランの「スリープ解除タイマーの許可」を有効化する
2. 復帰したら `stay_awake.ps1` が `start_solar.bat` を実行（既に動いていればスキップ）
3. タイマーで復帰しただけの PC は無操作だと約 2 分で再スリープするため、`stay_awake.ps1` が
   `SetThreadExecutionState` で `-AwakeUntil` までスリープを抑止する（画面は消えてよい）。終了後は通常の電源設定どおりスリープに戻る

動作確認:

```powershell
schtasks /Query /TN "SolarWake" /FO LIST /V
powercfg /waketimers              # SolarWake のタイマーが表示されれば OK
powercfg /requests                # 抑止中は SYSTEM 欄に powershell.exe が出る
```

テスト方法: `-WakeTime` を数分後にして登録 → スタートメニューからスリープ → 時刻に復帰するか確認。

注意:

- 「ユーザーがログオンしているときのみ実行」のタスクなので、ロック中のスリープは OK だが、サインアウト／再起動後に未ログオンだと動かない
- シャットダウン（電源オフ）や休止状態からは基本的に起こせない。スリープを使うこと
- `powercfg /a` で「スタンバイ (S0 低電力アイドル)」（モダンスタンバイ）と出る PC は、スリープ解除タイマーが効かないことがある。
  その場合は日中スリープしないよう電源設定で調整する
- ノート PC はバッテリー駆動時のスリープ解除も有効になる（鞄の中で起きないよう注意）

## スリープ復帰後に一定時間起こしておく（スマホからの Wake-on-LAN 用）

スマホ（Mocha WOL 等）で起こした PC は、無操作だと約 2 分で再スリープする。
`scripts/register_resume_task.ps1` で、スリープ復帰のたびに `stay_awake.ps1 -Minutes 10` を実行するタスク `SolarResume` を登録する
（復帰時のイベント System / Microsoft-Windows-Power-Troubleshooter / ID 1 がトリガー。復帰の原因は区別しない）。

```powershell
powershell -ExecutionPolicy Bypass -File .\register_resume_task.ps1                   # 10 分
powershell -ExecutionPolicy Bypass -File .\register_resume_task.ps1 -AwakeMinutes 60  # 時間を変える
powershell -ExecutionPolicy Bypass -File .\register_resume_task.ps1 -Unregister
```

Mocha WOL の設定: IP Address = `192.168.71.255`、Port = 9、**WOL Broadcast はオフ**（オンだと別アドレスに送られて届かない）。

## セキュリティ

認証情報（Gmail アプリパスワード、SwitchBot トークン等）は `secrets.py` に置き、コミットしない（`.gitignore` 済み）。
