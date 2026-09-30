# 太陽光発電モニタリング・スマートホーム連携プロジェクト 引き継ぎ

## プロジェクト概要
一条工務店で建てた住宅の太陽光発電（ダイヤゼブラ電機 EIBS7、パワコン型番：EHF-S99MP5B）から
ECHONET Liteでデータを取得し、CSV保存・Gmail通知を行うシステム。

## 環境情報

### PC環境
- OS: Windows
- ユーザー名: 777hi
- Python: python コマンドで実行可能
- 作業フォルダ: `C:\Users\777hi\OneDrive\パワコンデータ取得`

### ネットワーク構成
```
インターネット
    ↓
一条ルーター（Hongduan H8950）
    ↓ ─ [パワコン EIBS7: 192.168.68.51]（元々ここに繋がっていた）
    ↓
TP-Linkルーター（現在、パワコンのLANケーブルを刺し替え済み）
    ↓
    ├─ PC（Wi-Fi/有線どちらでも接続可）
    └─ パワコン EIBS7: 192.168.68.51
```

**重要**: パワコンのLANケーブルはHongduan H8950から抜いて、TP-Linkルーターに刺し替え済み。
これによりPCと同じネットワークになり、ECHONET Lite通信が可能になった。

### パワコン情報
- 型番: EHF-S99MP5B
- 製品シリーズ: ダイヤゼブラ電機 EIBS7
- IPアドレス: 192.168.68.51
- 対応オブジェクト:
  - 0x027901: 住宅用太陽光発電
  - 0x027D01: 蓄電池
  - 0x028701: 分散型電源
  - 0x02A501: 低圧スマート電力量メータ

## 既存ファイル

`C:\Users\777hi\OneDrive\パワコンデータ取得\` に以下が存在：

1. **find_echonet.py** - ECHONET Liteデバイス探索スクリプト
2. **get_objects.py** - パワコンの各EPCから値を取得して表示
3. **check_status.py** - 現在の状態を1回だけ確認（単発実行用）
4. **solar_logger.py** - 5分ごとにデータを取得しCSV保存する常駐スクリプト
5. **smart_notifier.py** - 10分ごとに状態チェックし条件付きGmail通知
6. **notifier.py** - Gmail送信テスト用
7. **notifier_state.json** - smart_notifier.pyの状態管理ファイル（自動生成）
8. **solar_data.csv** - solar_logger.pyが生成するデータCSV
9. **start_solar.bat** - solar_logger.pyとsmart_notifier.pyを同時起動するバッチ

## 現在のタスク：タスクスケジューラ登録の自動化

start_solar.bat を Windows起動時（ログオン時）に自動実行するタスクを登録したい。

### 要件
- タスク名: `SolarMonitor`
- トリガー: ユーザーログオン時
- 実行するプログラム: `C:\Users\777hi\OneDrive\パワコンデータ取得\start_solar.bat`
- 作業フォルダ: `C:\Users\777hi\OneDrive\パワコンデータ取得`
- AC電源判定なし（バッテリー駆動時も実行）
- 実行時間制限なし（3日で止まらないように）
- 既に同名タスクがある場合は上書き

### 実装イメージ（PowerShellでschtasks.exe利用）

```powershell
# タスク定義XML作成 → schtasks /Create /XML で登録
# または
# Register-ScheduledTask コマンドレット使用
```

### 動作確認方法
```powershell
schtasks /Query /TN "SolarMonitor" /FO LIST /V
Get-Process pythonw
```

## この後やりたいこと（優先順位順）

### Phase 1: 自動起動（今回のタスク）
- タスクスケジューラでSolarMonitor登録

### Phase 2: SwitchBot連携
- SwitchBot APIトークン: 別途 secrets.py で管理予定
- 実装したい制御:
  - 発電量4kW超え → SwitchBotプラグで食洗機/洗濯機ON
  - 蓄電残量20%以下 → 通知
  - 異常検知 → 即通知

### Phase 3: 通知機能強化
- 現在Gmail通知は smart_notifier.py で実装済み
- 将来的にiPhone向けプッシュ通知（ntfy.sh等）を検討

### Phase 4: Home Assistant導入検討
- Raspberry Pi 4 (4GB) または中古ミニPC購入予定
- 情報ボックス（内寸目安: 20×15×5cm）に収まるサイズ要
- ECHONET Lite統合、SwitchBot統合、Alexa統合を予定

## セキュリティ注意事項

- Gmail アプリパスワード、SwitchBot トークン等の認証情報は
  絶対にコード内にハードコードせず、別ファイル（secrets.py 等）で管理
- secrets.py は .gitignore に追加

## 主要なECHONET Liteプロパティ参照

### 太陽光発電 (0x027901)
| EPC | 内容 | 単位 |
|-----|------|------|
| 0xE0 | 瞬時発電電力 | W |
| 0xE1 | 積算発電電力量 | ×0.001 kWh |
| 0xE3 | 積算売電電力量 | ×0.001 kWh |
| 0x80 | 動作状態 | 0x30=ON |
| 0x88 | 異常発生状態 | 0x41=異常 |

### 蓄電池 (0x027D01)
| EPC | 内容 | 単位 |
|-----|------|------|
| 0xE4 | 瞬時充放電電力 | W (signed) |
| 0xE6 | 劣化状態(SOH) | % |
| 0xC8 | 充電残量 | Wh (PDC=8, 後半4バイト) |
| 0xA1 | AC実効容量(放電) | ×0.001 kWh |
| 0xA8 | 積算充電量 | ×0.001 kWh |
| 0xA9 | 積算放電量 | ×0.001 kWh |

## Claude Codeへの依頼例

```
1回目: 「太陽光発電モニタリングプロジェクトです。まず HANDOVER.md を読んで状況を把握してください」

2回目: 「タスクスケジューラに SolarMonitor を登録するPowerShellスクリプトを作成し、
実行してください。要件はHANDOVER.mdのPhase 1セクション参照」
```
