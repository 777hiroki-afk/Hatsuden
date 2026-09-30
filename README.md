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

## セキュリティ

認証情報（Gmail アプリパスワード、SwitchBot トークン等）は `secrets.py` に置き、コミットしない（`.gitignore` 済み）。
