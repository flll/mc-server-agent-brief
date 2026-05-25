# Minecraft サーバー構築 — AI エージェント向け指示書

> **バージョン**: 1.0  
> **対象読者**: Cursor / Claude Code 等の AI エージェント  
> **基盤イメージ**: [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server)（Java）、[itzg/docker-minecraft-bedrock-server](https://github.com/itzg/docker-minecraft-bedrock-server)（Bedrock）

---

## 目次

- [第0章 — この指示書の使い方](#第0章--この指示書の使い方)
- [第1章 — 事前ヒアリング](#第1章--事前ヒアリング)
- [第2章 — ホスト環境セットアップ](#第2章--ホスト環境セットアップ)
- [第3章 — bind mount 永続化 + I/O 性能最適化](#第3章--bind-mount-永続化--io-性能最適化)
- [第4章 — 標準プロジェクト構成](#第4章--標準プロジェクト構成)
- [第5章 — Makefile リファレンス](#第5章--makefile-リファレンス)
- [第6章 — アーキテクチャ決定フロー](#第6章--アーキテクチャ決定フロー)
- [第7章 — ユースケース別詳細手順](#第7章--ユースケース別詳細手順)
- [第8章 — 環境変数リファレンス](#第8章--環境変数リファレンス)
- [第9章 — エージェント実行チェックリスト](#第9章--エージェント実行チェックリスト)
- [第10章 — セキュリティ](#第10章--セキュリティ)
- [第11章 — トラブルシューティング](#第11章--トラブルシューティング)
- [第12章 — ユーザー向けプロンプト例](#第12章--ユーザー向けプロンプト例)
- [第13章 — 参考リンク](#第13章--参考リンク)

---

## 第0章 — この指示書の使い方

### 0.1 読者と目的

本指示書は、**AI エージェント**がユーザーの要件から Docker ベースの Minecraft サーバー環境を**一貫した手順**で構築するための詳細ガイドである。

エージェントは本書に従い、以下を生成・設定する:

- `docker-compose.yml`（bind mount 専用、`restart: unless-stopped`）
- `.env` / `.env.example`（秘密情報は `.env` のみ）
- `Makefile`（日常操作の統一入口）
- `scripts/backup.sh` / `restore.sh`（および Windows 向け `.ps1`）
- `README.md`（ユーザー向け引き渡し文書）

**本指示書のスコープ外**（実行しないこと）:

- 実際の `docker compose up` によるサーバー起動（ユーザー明示指示がある場合のみ）
- モッドパックのダウンロード実行（設定のみ生成）
- Terraform 等のクラウド IaC 実装
- systemd unit / cron timer の設定
- Docker named volume の使用

### 0.2 基本原則

| 原則 | 内容 |
|------|------|
| **再現性** | compose + `.env.example` + README + Makefile で構成を固定 |
| **秘密情報の分離** | API キー・RCON パスワードは `.env` のみ。gitignore 必須 |
| **bind mount のみ** | `./data:/data` 等。named volume / external volume **禁止** |
| **I/O 性能最適化** | 配置場所・キャッシュ・build context 除外を必須とする |
| **OS 自動起動なし** | systemd unit / cron timer **禁止** |
| **Docker restart あり** | compose の `restart: unless-stopped`（または `always`）**必須** |
| **手動運用** | 日常操作は `make up` / `make logs` / `make backup` 等。バックアップは手動のみ |
| **Aikar フラグ常時** | すべての Java サーバーで `USE_AIKAR_FLAGS: "TRUE"` **必須** |
| **MOTD 自動生成** | `MOTD=§6${SERVER_NAME}§r` を `SERVER_NAME` 確定後に自動設定 |

### 0.3 エージェント作業フロー概要

```
1. SERVER_NAME をユーザーに確認（最優先）
2. MOTD を SERVER_NAME から自動生成
3. ホスト OS を確認（Linux / Windows+WSL2）
4. 事前ヒアリング（第1章）を完了
5. ユースケース（UC）を選定
6. プロジェクトファイルを生成（Phase 2）
7. make config で構文検証
8. ユーザーに引き渡し（README 含む）
```

### 0.4 成功条件チェックリスト（10項目）

作業完了時、以下すべてを満たしていること:

- [ ] **1.** `SERVER_NAME` が slug ルールに適合し、ルートディレクトリ名・`COMPOSE_PROJECT_NAME`・バックアップ名に反映されている
- [ ] **2.** `MOTD=§6${SERVER_NAME}§r` が `.env` および compose に設定されている
- [ ] **3.** すべての永続データが bind mount（`./data:/data`）のみで構成され、named volume が存在しない
- [ ] **4.** compose に `restart: unless-stopped`（または `always`）が設定されている
- [ ] **5.** Java サーバーに `USE_AIKAR_FLAGS: "TRUE"` が設定されている
- [ ] **6.** `OVERRIDE_SERVER_PROPERTIES: "TRUE"` により MOTD が反映される
- [ ] **7.** `.dockerignore` に `data/`、`backups/`、`.env` が含まれている
- [ ] **8.** `Makefile` の全ターゲットが機能する（`make help` で確認可能）
- [ ] **9.** Windows 環境では WSL2 内配置（`/mnt/c` 禁止）が確認されている
- [ ] **10.** systemd / cron / タスクスケジューラによる自動起動・自動バックアップが**設定されていない**

---

## 第1章 — 事前ヒアリング

### 1.0 作業順序（厳守）

**`SERVER_NAME` は他のすべての作業より先に必ずユーザーに確認する。** 未回答の場合、以降の作業を進めてはならない。

確定後の作業順序:

1. `SERVER_NAME` をユーザーに確認・バリデーション
2. `MOTD=§6${SERVER_NAME}§r` を `.env` に自動設定（別途質問不要）
3. `~/servers/${SERVER_NAME}/`（Linux）または WSL home 内にプロジェクトを作成
4. compose / Makefile / backup スクリプトはすべて `SERVER_NAME` を参照
5. compose に `USE_AIKAR_FLAGS: "TRUE"` と `MOTD` を必ず含める

### 1.1 ヒアリング項目一覧

| # | 項目 | 選択肢 | デフォルト |
|---|------|--------|-----------|
| **0** | **サーバー名 (`SERVER_NAME`)** | 英小文字・数字・ハイフンの slug | **必ず質問。未回答なら停止** |
| 1 | ホスト OS | Linux / Windows | ユーザー環境を検出 |
| 2 | エディション | Java / Bedrock / Java+Bedrock | Java |
| 3 | サーバー種別 | Vanilla / Paper / Purpur / Fabric / Forge / NeoForge | Paper |
| 4 | コンテンツ | バニラ / プラグイン / モッドパック / カスタム MOD | プラグイン |
| 5 | モッドパック元 | CurseForge / Modrinth / FTB / 手元 zip | — |
| 6 | MC バージョン | 例 `1.21.1` | 最新安定版 |
| 7 | 同時接続人数 | 数値 | 10 |
| 8 | 割当 RAM | GB | 人数 × 0.5〜1GB（MOD 時 ×2） |
| 9 | 公開範囲 | LAN / インターネット / ローカルのみ | LAN |
| 10 | 追加機能 | RCON / whitelist / バックアップ / プロキシ / Dynmap | RCON + バックアップ |

### 1.2 サーバー名 (`SERVER_NAME`) ルール

エージェントはヒアリング時に次をユーザーへ提示する:

> 「サーバー名を決めてください。プロジェクトのフォルダ名、バックアップファイル名、Docker Compose のプロジェクト名に使います。」

| ルール | 例（OK） | 例（NG） |
|--------|----------|----------|
| 英小文字・数字・ハイフンのみ | `my-paper-server`, `atm10` | `My Server`（スペース） |
| 先頭は英字 | `survival-01` | `01-survival`（数字始まり） |
| 3〜32 文字 | `lobby` | `a`（短すぎ） |
| 予約語回避 | — | `data`, `backups`, `config` |

**バリデーション用正規表現**:

```regex
^[a-z][a-z0-9-]{2,31}$
```

**`SERVER_NAME` の使い道**:

| 用途 | 形式 | 例（`SERVER_NAME=survival-2024`） |
|------|------|-----------------------------------|
| ルートディレクトリ名 | `${SERVER_NAME}/` | `~/servers/survival-2024/` |
| バックアップファイル名 | `${SERVER_NAME}_data_${TIMESTAMP}.tar.gz` | `survival-2024_data_20260526_143000.tar.gz` |
| Compose プロジェクト名 | `COMPOSE_PROJECT_NAME=${SERVER_NAME}` | コンテナ名接頭辞に反映 |
| `.env` 変数 | `SERVER_NAME=survival-2024` | 全スクリプトが参照 |
| **MOTD（必須）** | `SERVER_NAME` から自動生成 | `§6survival-2024§r` |

### 1.3 MOTD — シンプル表示（必須・`SERVER_NAME` 連動）

**方針**: サーバー一覧で**サーバー名がわかれば十分**。MOTD は別途ヒアリングしない — **`SERVER_NAME` から自動生成**する。

**必須要件**:

- compose / `.env` に **`MOTD` を必ず設定**（省略禁止）
- **1行・シンプル**: サーバー名が読める表示のみ（複数行・装飾の盛りすぎ禁止）
- **`SERVER_NAME` が決まれば MOTD も決まる** — 追加質問不要

**デフォルト生成ルール**:

```
MOTD = "§6" + SERVER_NAME + "§r"
```

例: `SERVER_NAME=survival-2024` → `MOTD=§6survival-2024§r`

**compose テンプレート**:

```yaml
environment:
  OVERRIDE_SERVER_PROPERTIES: "TRUE"
  MOTD: "§6${SERVER_NAME}§r"
```

**`.env` への明示設定**:

```dotenv
SERVER_NAME=survival-2024
MOTD=§6survival-2024§r
```

**任意カスタム**（ユーザーが明示要求した場合のみ）:

- 表示用の別名を使いたいときだけ MOTD を上書き（例: `§6My Survival Server§r`）
- それ以外は `SERVER_NAME` ベースのデフォルトを使う

### 1.4 `USE_AIKAR_FLAGS` — 常時有効（必須）

- **すべての Java サーバー構成**で `USE_AIKAR_FLAGS: "TRUE"` を設定（省略・`FALSE` 禁止）
- JVM 性能最適化のため交渉不可の固定要件
- Bedrock 専用サーバー（UC-F）には適用しない

### 1.5 RAM 見積もり表

| 構成 | 最小 RAM | 推奨 RAM |
|------|----------|----------|
| Vanilla 1〜5人 | 2GB | 4GB |
| Paper + プラグイン 10人 | 4GB | 6GB |
| 軽量 MOD（Fabric） | 4GB | 6GB |
| 中規模 MOD パック | 8GB | 12GB |
| 大規模 MOD パック（ATM 等） | 10GB | 16GB+ |

**Docker Desktop / WSL2 の場合**: ホストに割当 RAM 以上の `MEMORY` を設定しない。`.wslconfig` でメモリ上限を調整する（第2章参照）。

---

## 第2章 — ホスト環境セットアップ

### 2.1 共通前提

| 項目 | 要件 |
|------|------|
| Docker Engine | 24+ |
| Docker Compose | v2（`docker compose` サブコマンド） |
| Java ポート | 25565/TCP |
| Bedrock ポート | 19132/UDP |
| RCON ポート | 25575/TCP（有効時） |
| ディスク | 最低 10GB。MOD パックは 20GB+ |
| OS 自動起動 | **不要** — systemd / cron timer は設定しない |
| コンテナ自動再起動 | compose の `restart:` ポリシーで対応 |

### 2.2 Linux（Ubuntu / Debian 例）

#### 2.2.1 Docker インストール

```bash
# 1. 公式 convenience script（推奨）
curl -fsSL https://get.docker.com | sh

# 2. ユーザーを docker グループに追加
sudo usermod -aG docker $USER

# 3. 再ログイン後、バージョン確認
docker --version && docker compose version
```

#### 2.2.2 ファイアウォール（ufw 使用時）

```bash
sudo ufw allow 25565/tcp comment 'Minecraft Java'
sudo ufw allow 19132/udp comment 'Minecraft Bedrock'
sudo ufw allow 25575/tcp comment 'Minecraft RCON'
```

#### 2.2.3 プロジェクト配置

```bash
mkdir -p ~/servers/${SERVER_NAME}
cd ~/servers/${SERVER_NAME}
```

**理由**: ホームディレクトリ内の ext4/xfs は bind mount の I/O 性能が最良。

#### 2.2.4 UID / GID 設定

```bash
id -u   # → .env の UID に設定
id -g   # → .env の GID に設定
```

compose の `environment` に渡すことで、コンテナ内プロセスのファイル所有者をホストユーザーと一致させる。

#### 2.2.5 禁止事項

- `/etc/systemd/system/minecraft.service` 等の systemd unit **作成禁止**
- cron による定期バックアップ **設定禁止**
- `docker compose up` を systemd から呼び出す構成 **禁止**

### 2.3 Windows — 2 パターン

#### パターン A（推奨）: WSL2 + Docker Desktop

1. WSL2 有効化:

```powershell
wsl --install
```

2. Docker Desktop インストール → **Settings → Resources → WSL Integration** で使用するディストリビューションを有効化

3. **プロジェクトは WSL ファイルシステム内に配置**:

```bash
# WSL（Ubuntu）ターミナル内
mkdir -p ~/servers/${SERVER_NAME}
cd ~/servers/${SERVER_NAME}
```

**理由**: `C:\Users\...` への bind mount は 9p/DrvFs 経由で I/O が極端に遅く、ファイル監視も不安定。

4. 操作は WSL ターミナルで `make` コマンドを実行

5. Windows 側から WSL 内 make を呼ぶ場合:

```powershell
wsl -d Ubuntu --cd ~/servers/survival-2024 make up
```

#### パターン B: Docker Desktop + Windows ネイティブパス — 非推奨

- `C:\Users\...` への bind mount は **禁止に近い扱い**
- どうしても使う場合は README に「チャンク保存・MOD DL が 10 倍遅くなる」警告を明記
- Makefile は WSL 内で実行すること

**Velocity マウント差分**（Windows ネイティブ時のみ）:

```yaml
# Linux / WSL
- ./velocity.toml:/config

# Windows ネイティブ（必要時）
- ./velocity.toml:/config/velocity.toml
```

#### 2.3.1 Windows ファイアウォール（PowerShell — 管理者）

```powershell
New-NetFirewallRule -DisplayName "Minecraft Java" -Direction Inbound -Protocol TCP -LocalPort 25565 -Action Allow
New-NetFirewallRule -DisplayName "Minecraft Bedrock" -Direction Inbound -Protocol UDP -LocalPort 19132 -Action Allow
New-NetFirewallRule -DisplayName "Minecraft RCON" -Direction Inbound -Protocol TCP -LocalPort 25575 -Action Allow
```

#### 2.3.2 WSL2 メモリ設定

`%UserProfile%\.wslconfig`:

```ini
[wsl2]
memory=8GB
processors=4
# localhostForwarding=true  # デフォルトで有効
```

変更後:

```powershell
wsl --shutdown
```

### 2.4 OS 横断 — エージェント向け分岐ルール

```
IF ホスト OS == Windows:
  IF Docker Desktop + WSL2 利用可能:
    推奨: WSL2 内にプロジェクト作成（~/servers/${SERVER_NAME}/）
    スクリプト: .sh（bash）を主、.ps1 を補助
    make check-path で /mnt/ パスを拒否
  ELSE:
    Windows ネイティブパスで compose 生成（非推奨・警告必須）
    スクリプト: .ps1 を主
ELSE Linux:
  スクリプト: .sh を主
  配置: ~/servers/${SERVER_NAME}/
  バックアップ: make backup（手動実行のみ）
```

### 2.5 空きポート・ディスク確認

**Linux / WSL**:

```bash
ss -tlnp | grep -E '25565|25575'
ss -ulnp | grep 19132
df -h .
```

**Windows（PowerShell）**:

```powershell
netstat -ano | findstr 25565
netstat -ano | findstr 25575
Get-PSDrive C | Select-Object Used,Free
```

---

## 第3章 — bind mount 永続化 + I/O 性能最適化

> **本章は指示書の核心。** エージェントは本章のルールを厳守すること。

### 3.1 永続化方針 — bind mount のみ（厳守）

**必須**: すべての永続データはホストディレクトリへの bind mount とする。

```yaml
services:
  mc:
    volumes:
      - ./data:/data
      - ./config/plugins:/plugins:ro   # 任意: 読み取り専用プラグイン注入
      - ./backups:/backups             # 任意: バックアップ出力先
```

**禁止**（違反時は構成を修正すること）:

| 禁止事項 | 理由 |
|----------|------|
| `volumes:` トップレベルの named volume 定義（`mc-data:` 等） | データ所在が不透明、移行困難 |
| `mc-data:/data` 形式のマウント | named volume 使用 |
| `docker compose down -v` | named volume 削除リスク（bind mount でも習慣化を避ける） |
| Windows で `C:\...` / `/mnt/c/...` へのプロジェクト配置 | 9p 越しの I/O が激遅 |
| `./config:/data/config` 等の過度な分割マウント | マウント点増加は逆効果 |

### 3.2 I/O キャッシュ・性能最適化

| 施策 | Linux | Windows (WSL2) | 理由 |
|------|-------|----------------|------|
| プロジェクト配置 | ローカル ext4/xfs | **`~/servers/${SERVER_NAME}`（WSL ext4 内）** | ネイティブ FS = フルキャッシュ効率 |
| 禁止パス | — | `/mnt/c/Users/...` | 9p 越しはランダム I/O が激遅 |
| Docker Desktop | — | Settings → WSL2 engine 有効 | Linux VM 内で ext4 bind |
| `.dockerignore` | `data/`, `backups/`, `*.log` | 同左 | build context から巨大 data を除外 |
| イメージ pull | `pull_policy: daily` またはバージョン固定 | 同左 | 不要な再 pull 回避 |
| MC/JAR キャッシュ | `data/` 内に server.jar 等が保持 | 同左 | 2 回目以降の起動が高速化 |
| MOD 初回 DL | `CF_PARALLEL_DOWNLOADS: "8"`（RAM に余裕時） | 同左 | 並列 DL で初回のみ短縮 |
| JVM | `USE_AIKAR_FLAGS: "TRUE"` | 同左 | **常時必須** |
| sync 負荷低減 | `./data` 一括マウントが基本 | 同左 | 分割マウントは非推奨 |

### 3.3 配置チェック（エージェント必須）

WSL 内で実行 — `/mnt/c` を含むパスなら **FAIL**:

```bash
make check-path
# または
pwd | grep -q '/mnt/' && echo "ERROR: 遅いパスです。WSL home へ移動してください" || echo "OK"
```

`make up` は `check-path` に依存するため、遅いパスでは起動前にエラーとなる。

### 3.4 compose 標準テンプレート

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    pull_policy: daily
    tty: true
    stdin_open: true
    ports:
      - "${MC_PORT:-25565}:25565"
    environment:
      EULA: "TRUE"
      USE_AIKAR_FLAGS: "TRUE"          # 常時必須
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"       # SERVER_NAME から自動。1行シンプル
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
      TYPE: "${TYPE:-PAPER}"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-4G}"
      ENABLE_RCON: "${ENABLE_RCON:-TRUE}"
      RCON_PASSWORD: "${RCON_PASSWORD}"
    volumes:
      - ./data:/data
    restart: unless-stopped   # 異常終了・OOM 後に Docker が自動再起動
```

### 3.5 Docker `restart:` ポリシー

**systemd は使わないが、compose の `restart:` は必ず設定する。**

| ポリシー | 動作 | 推奨 |
|----------|------|------|
| `unless-stopped` | クラッシュ・OOM・Docker デーモン再起動後に自動復帰。`make down` 後は再起動しない | **デフォルト** |
| `always` | 手動 stop 後も Docker デーモン再起動時に復帰 | 常時稼働最優先時 |
| `on-failure` | 非ゼロ終了コード時のみ再起動 | デバッグ中 |
| （未指定） | 停止後は再起動しない | **使用禁止** |

**動作整理**:

| イベント | `unless-stopped` の動作 |
|----------|-------------------------|
| プロセス異常終了 / OOM | Docker が自動再起動 |
| `make down`（意図的停止） | 停止状態を維持（再起動しない） |
| ホスト OS 再起動 | Docker 起動時に自動復帰（systemd unit 不要） |
| `make restart` | 手動 down + up |

**禁止との整理**:

| 方式 | 許可 |
|------|------|
| compose `restart: unless-stopped` | OK |
| compose `restart: always` | OK（要件次第） |
| systemd unit で `docker compose up` | **NG** |
| cron / systemd timer で定期起動 | **NG** |
| cron / タスクスケジューラで定期バックアップ | **NG** |

### 3.6 永続化対象 — `./data` ディレクトリ全体

**バックアップ対象も `./data` 全体**（ワールドだけでなく mods / plugins / config / jar キャッシュ等すべて含む）。

| コンテナ内パス | 内容 | バックアップ |
|---------------|------|-------------|
| `/data/` 全体 | ワールド・MOD・プラグイン・設定・JAR 等 | **一括（tar.gz）** |
| `/data/world` | ワールドデータ | ↑ に含む |
| `/data/mods` | MOD | ↑ に含む |
| `/data/plugins` | プラグイン | ↑ に含む |
| `/data/config` | 各種設定 | ↑ に含む |

### 3.7 権限（Linux / WSL）

```yaml
environment:
  UID: "1000"   # id -u の値
  GID: "1000"   # id -g の値
```

`data/` 配下が root 所有になる場合の修復:

```bash
sudo chown -R $(id -u):$(id -g) ./data
```

### 3.8 バックアップ手順 — サーバーデータ全体（`make backup`）

**方針**: `./data` ディレクトリを**丸ごと**アーカイブ。ワールドのみの部分バックアップは行わない。

**ファイル名形式**: `${SERVER_NAME}_data_${TIMESTAMP}.tar.gz`

**Linux / WSL** — `scripts/backup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source .env
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p backups
docker compose exec -T mc rcon-cli save-all flush 2>/dev/null || true
docker compose stop mc
tar -czf "backups/${SERVER_NAME}_data_${TS}.tar.gz" -C . data
docker compose start mc
```

**Windows PowerShell** — `scripts/backup.ps1`:

```powershell
# WSL 内推奨。ネイティブ Windows では tar コマンドを使用
tar -czf "backups\${env:SERVER_NAME}_data_$ts.tar.gz" -C . data
```

**リストア**:

```bash
RESTORE=backups/survival-2024_data_20260526_143000.tar.gz make restore
make up
```

内部処理:

1. `docker compose down`
2. 既存 `data/` を `data.old.<timestamp>/` に退避
3. `tar -xzf "$RESTORE"` で `./data` を復元
4. ユーザーが `make up` で起動

- バックアップは **手動実行のみ**（`make backup`）
- cron / タスクスケジューラの設定例は**載せない**

### 3.9 更新・イメージ Pull 時のデータ保全

```bash
make update    # 内部: pull + up -d。./data は bind mount のまま維持
```

- `docker compose down -v` は **絶対禁止**
- volume 削除ターゲットは Makefile に設けない

---

## 第4章 — 標準プロジェクト構成

**ルートディレクトリ名 = `SERVER_NAME`**（固定名 `minecraft-server/` は使わない）。

```
${SERVER_NAME}/                    # 例: survival-2024/
├── Makefile
├── docker-compose.yml
├── docker-compose.override.yml    # 任意（ローカル差分）
├── .dockerignore
├── .env.example
├── .env                           # gitignore
├── .gitignore
├── README.md
├── docs/
│   └── minecraft-server-agent-brief.md
├── config/
│   └── plugins/                   # 任意: ローカルプラグイン注入
├── data/                          # bind mount 先（gitignore）
├── backups/                       # ${SERVER_NAME}_data_*.tar.gz（gitignore）
└── scripts/
    ├── backup.sh
    ├── backup.ps1
    ├── restore.sh
    └── restore.ps1
```

### 4.1 `.env.example` 先頭項目

```dotenv
SERVER_NAME=survival-2024
MOTD=§6survival-2024§r
COMPOSE_PROJECT_NAME=survival-2024
```

### 4.2 `.dockerignore` 必須項目

```
data/
backups/
.git/
*.log
.env
```

### 4.3 `.gitignore` 必須項目

```
.env
data/
backups/
*.log
forwarding.secret
*.old.*
```

### 4.4 README.md 必須セクション

1. サーバー名（`SERVER_NAME`）と接続方法
2. 必要 RAM / ディスク / MC バージョン
3. 初回セットアップ（`make init` → `.env` 編集 → `make up`）
4. 日常操作（`make help` 一覧）
5. OS 別注意（WSL2 推奨等）
6. バックアップ / リストア手順
7. 更新手順（`make update`）
8. トラブルシューティング

---

## 第5章 — Makefile リファレンス

日常操作の**唯一の入口**として Makefile を使用する。

### 5.1 ターゲット一覧

| ターゲット | 処理 | 備考 |
|-----------|------|------|
| `help` | ターゲット一覧表示 | デフォルト |
| `init` | `.env` 生成、**SERVER_NAME 確認**、ディレクトリ作成 | 初回のみ |
| `config` | `docker compose config` 構文検証 | |
| `up` | `docker compose up -d` | `check-path` 実行 |
| `down` | `docker compose down`（**-v なし**） | |
| `restart` | down + up | |
| `logs` | `docker compose logs -f` | |
| `status` | `docker compose ps` | |
| `pull` | `docker compose pull` | |
| `update` | pull + up -d | |
| `backup` | RCON save → stop → `./data` 全体 tar → start | `scripts/backup.sh` |
| `restore` | `RESTORE=...` で `./data` 丸ごと復元 | `scripts/restore.sh` |
| `shell` | コンテナ内 bash | |
| `rcon` | `make rcon CMD="list"` | RCON コマンド実行 |
| `check-path` | WSL で `/mnt/` 配置を検出 | Windows 向け |

### 5.2 参照実装

プロジェクトルートの `Makefile` を参照。主要部分:

```makefile
-include $(ENV_FILE)
export $(shell sed -n 's/=.*//p' $(ENV_FILE) 2>/dev/null)

init:
	@test -f .env || cp .env.example .env
	@grep -q '^SERVER_NAME=.' .env || (echo "ERROR: .env に SERVER_NAME を設定"; exit 1)
	@mkdir -p data backups config/plugins
	@$(MAKE) check-path

backup:
	@bash scripts/backup.sh

restore:
	@test -n "$(RESTORE)" || (echo "Usage: RESTORE=backups/... make restore"; exit 1)
	@bash scripts/restore.sh "$(RESTORE)"
```

### 5.3 Windows での Makefile 実行

| 方法 | コマンド |
|------|----------|
| **推奨: WSL 内** | `cd ~/servers/my-server && make up` |
| Windows ターミナルから | `wsl -d Ubuntu --cd ~/servers/my-server make up` |
| make 未インストール | `sudo apt install make`（WSL） |
| make 不可時 | README に `docker compose` 直叩き表を記載 |

**Windows ネイティブのみ**: `scripts/*.ps1` は補助。**主導線は WSL + make**。

### 5.4 docker compose 直叩き代替表

| make コマンド | docker compose 直叩き |
|--------------|----------------------|
| `make up` | `docker compose up -d` |
| `make down` | `docker compose down` |
| `make logs` | `docker compose logs -f` |
| `make status` | `docker compose ps` |
| `make pull` | `docker compose pull` |
| `make shell` | `docker compose exec mc bash` |
| `make rcon CMD="list"` | `docker compose exec mc rcon-cli list` |

---

## 第6章 — アーキテクチャ決定フロー

```
要件ヒアリング
    │
    ▼
SERVER_NAME をユーザーに確認（最優先）
    │
    ▼
MOTD = §6${SERVER_NAME}§r を自動設定
    │
    ▼
OS 確認 ── Windows ── WSL2 可? ── Yes ── WSL 内配置
    │                    └── No ── ネイティブ（警告）
    └── Linux ── ~/servers/${SERVER_NAME}/
    │
    ▼
エディション ── Java ── 種別 ── プラグイン → Paper (UC-A)
    │                    ├── MOD パック → CF/MR (UC-B/C)
    │                    ├── カスタム MOD → Fabric/Forge (UC-D)
    │                    └── 複数鯖 → Velocity (UC-E)
    ├── Bedrock → UC-F
    └── Java+Bedrock → Geyser (UC-G)
```

**イメージ選定**:

| 要件 | イメージ |
|------|----------|
| Java（万能） | `itzg/minecraft-server` |
| Bedrock | `itzg/minecraft-bedrock-server` |
| Velocity プロキシ | `itzg/mc-proxy` |

---

## 第7章 — ユースケース別詳細手順

各 UC は同一フォーマットで記載する:

1. 概要・向いている場面
2. 前提条件
3. `docker-compose.yml` 完全例
4. `.env.example` 追加項目
5. 初回起動手順（Linux / Windows 分岐）
6. 起動確認方法
7. クライアント接続手順
8. よくある失敗と対処
9. 参考リンク

---

### UC-A: Paper プラグインサーバー

#### 概要

最も一般的な構成。Bukkit/Spigot 互換プラグインを利用した Java サーバー。

#### 前提条件

- RAM: 4GB+（10 人想定）
- ディスク: 10GB+
- ポート: 25565/TCP

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME:-survival-2024}

services:
  mc:
    image: itzg/minecraft-server:latest
    pull_policy: daily
    tty: true
    stdin_open: true
    ports:
      - "${MC_PORT:-25565}:25565"
      - "${RCON_PORT:-25575}:25575"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      MAX_PLAYERS: "${MAX_PLAYERS:-10}"
      ENABLE_RCON: "${ENABLE_RCON:-TRUE}"
      RCON_PASSWORD: "${RCON_PASSWORD}"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
      ONLINE_MODE: "${ONLINE_MODE:-TRUE}"
      DIFFICULTY: "${DIFFICULTY:-normal}"
      WHITE_LIST: "${WHITE_LIST:-FALSE}"
      # プラグイン URL リスト（カンマ区切り）
      PLUGINS: |
        https://github.com/EssentialsX/Essentials/releases/latest/download/EssentialsX-2.21.0.jar
        https://download.luckperms.net/1565/bukkit/loader/LuckPerms-Bukkit-5.4.145.jar
    volumes:
      - ./data:/data
      - ./config/plugins:/plugins:ro
    restart: unless-stopped
```

#### .env.example 追加項目

```dotenv
TYPE=PAPER
VERSION=1.21.1
MEMORY=4G
MAX_PLAYERS=10
ENABLE_RCON=TRUE
RCON_PASSWORD=your-secure-password-here
```

#### 初回起動手順

**Linux / WSL**:

```bash
cd ~/servers/${SERVER_NAME}
cp .env.example .env
# .env を編集（SERVER_NAME, RCON_PASSWORD 等）
make init
make config
make up
make logs
```

**Windows（WSL2 推奨）**:

```powershell
wsl -d Ubuntu
cd ~/servers/${SERVER_NAME}
make init && make up
```

#### 起動確認

ログに以下が表示されれば成功:

```
[Server thread/INFO]: Done (XX.Xs)! For help, type "help"
```

MOTD 確認:

```bash
make rcon CMD="list"
```

#### クライアント接続

- アドレス: `<ホストIP>:25565`
- LAN: 同一ネットワーク内の IP
- インターネット: ルーターのポートフォワード設定が必要

#### よくある失敗

| 症状 | 原因 | 対処 |
|------|------|------|
| プラグイン未ロード | バージョン不一致 | MC 版に合ったプラグイン版を指定 |
| Permission denied | UID/GID 不一致 | `chown -R $(id -u):$(id -g) data` |
| MOTD 未反映 | OVERRIDE 未設定 | `OVERRIDE_SERVER_PROPERTIES: "TRUE"` |

#### 参考リンク

- [itzg/docker-minecraft-server — Paper](https://docker-minecraft-server.readthedocs.io/en/latest/types-and-platforms/server-types/paper/)
- [Paper 公式](https://papermc.io/)

---

### UC-B: CurseForge モッドパック

#### 概要

CurseForge 上の MOD パックを自動ダウンロード・構築する構成。

#### 前提条件

- RAM: **8GB+**（大規模パックは 12GB+）
- ディスク: **20GB+**
- `CF_API_KEY` 必須

#### CF_API_KEY 取得

1. https://console.curseforge.com/ にアクセス
2. アカウント作成 / ログイン
3. API キーを生成
4. `.env` に `CF_API_KEY=...` として設定（git 禁止）

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  mc:
    image: itzg/minecraft-server:latest
    pull_policy: daily
    tty: true
    stdin_open: true
    ports:
      - "${MC_PORT:-25565}:25565"
    environment:
      EULA: "TRUE"
      TYPE: "AUTO_CURSEFORGE"
      CF_API_KEY: "${CF_API_KEY}"
      CF_PAGE_URL: "${CF_PAGE_URL}"
      CF_PARALLEL_DOWNLOADS: "8"
      MEMORY: "${MEMORY:-8G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

#### .env.example 追加項目

```dotenv
TYPE=AUTO_CURSEFORGE
CF_API_KEY=
CF_PAGE_URL=https://www.curseforge.com/minecraft/modpacks/all-the-mods-10
MEMORY=12G
```

#### 重要: サーバー専用 zip を選ばない

CurseForge には「クライアント用」と「サーバー用」の zip がある。**クライアント用**（通常の MOD パックページ URL）を `CF_PAGE_URL` に指定すること。サーバー専用 zip は MOD 構成が不完全な場合がある。

#### 初回起動

初回は **10〜30 分**のダウンロードが発生。ログ例:

```
[mc-image-helper] Downloading mod ...
[mc-image-helper] Mod download complete
```

#### よくある失敗

| 症状 | 対処 |
|------|------|
| 401 Unauthorized | `CF_API_KEY` を確認 |
| OOM Killed | `MEMORY` を増加、`.wslconfig` も調整 |
| 特定 MOD 競合 | `CF_EXCLUDE_MODS` / `CF_FORCE_INCLUDE_MODS` |

---

### UC-C: Modrinth モッドパック

#### 概要

Modrinth ホストの MOD パックを URL 指定で導入。

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "MODRINTH"
      MODRINTH_MODPACK: "${MODRINTH_MODPACK}"
      MODRINTH_LOADER: "${MODRINTH_LOADER:-fabric}"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-6G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    ports:
      - "${MC_PORT:-25565}:25565"
    restart: unless-stopped
```

#### .env.example

```dotenv
MODRINTH_MODPACK=https://modrinth.com/modpack/fabulously-optimized
MODRINTH_LOADER=fabric
VERSION=LATEST
MEMORY=6G
```

---

### UC-D: カスタム MOD 一覧（Fabric / Forge / NeoForge）

#### 概要

Modrinth プロジェクト slug のリストで MOD を個別指定。

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "${TYPE:-FABRIC}"
      VERSION: "${VERSION:-LATEST}"
      MODRINTH_PROJECTS: |
        fabric-api
        lithium
        sodium?
      VERSION_FROM_MODRINTH_PROJECTS: "TRUE"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    ports:
      - "${MC_PORT:-25565}:25565"
    restart: unless-stopped
```

**`?` サフィックス**: オプショナル MOD（見つからなくてもエラーにしない）

**TYPE 値**: `FABRIC` / `FORGE` / `NEOFORGE`

---

### UC-E: Velocity プロキシ + 複数 Paper サーバー

#### 概要

ロビー + サバイバル等、複数バックエンドを Velocity で統合。

#### 前提条件

- RAM: 各サーバー 2GB+ + プロキシ 512MB
- `forwarding.secret` の生成と Paper 側設定

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  velocity:
    image: itzg/mc-proxy:latest
    ports:
      - "25565:25565"
    environment:
      TYPE: "VELOCITY"
      MEMORY: "512M"
    volumes:
      - ./velocity.toml:/config
      - ./forwarding.secret:/forwarding.secret:ro
    restart: unless-stopped
    depends_on:
      - lobby
      - survival

  lobby:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "2G"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}-lobby§r"
      ONLINE_MODE: "FALSE"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data/lobby:/data
    restart: unless-stopped

  survival:
    image: itzg/minecraft-server:latest
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}-survival§r"
      ONLINE_MODE: "FALSE"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data/survival:/data
    restart: unless-stopped
```

#### forwarding.secret 設定（ステップバイステップ）

1. シークレット生成:

```bash
openssl rand -hex 16 > forwarding.secret
chmod 600 forwarding.secret
```

2. `velocity.toml` に設定（`player-info-forwarding-mode = "modern"`）

3. 各 Paper サーバーの `config/paper-global.yml`:

```yaml
proxies:
  velocity:
    enabled: true
    online-mode: true
    secret: "<forwarding.secret の内容>"
```

4. **Docker 内部 DNS を使用**: バックエンドアドレスは `lobby:25565`（`127.0.0.1` 禁止）

#### Windows マウント差分

```yaml
# Linux / WSL
- ./velocity.toml:/config

# Windows ネイティブ
- ./velocity.toml:/config/velocity.toml
```

#### 参考リンク

- [itzg/docker-mc-proxy](https://github.com/itzg/docker-mc-proxy)
- [heyvaldemar/minecraft-server-proxy-docker-compose](https://github.com/heyvaldemar/minecraft-server-proxy-docker-compose)

---

### UC-F: Bedrock Dedicated Server

#### 概要

Minecraft Bedrock Edition（PE / Windows10 / Xbox 等）専用サーバー。

#### 前提条件

- ポート: **19132/UDP**（TCP ではない）
- イメージ: `itzg/minecraft-bedrock-server`

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  bedrock:
    image: itzg/minecraft-bedrock-server:latest
    pull_policy: daily
    ports:
      - "19132:19132/udp"
    environment:
      EULA: "TRUE"
      SERVER_NAME: "${SERVER_NAME}"
      GAMEMODE: "survival"
      DIFFICULTY: "normal"
      MAX_PLAYERS: "${MAX_PLAYERS:-10}"
      ALLOW_CHEATS: "false"
      LEVEL_NAME: "Bedrock level"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

**注意**: Bedrock には `USE_AIKAR_FLAGS` は不要（Java 専用）。

#### ファイアウォール

```bash
# Linux
sudo ufw allow 19132/udp
```

```powershell
# Windows
New-NetFirewallRule -DisplayName "Minecraft Bedrock" -Direction Inbound -Protocol UDP -LocalPort 19132 -Action Allow
```

#### クライアント接続

- Bedrock クライアント → 「サーバー」→ `<IP>:19132`

---

### UC-G: Java + Bedrock クロスプレイ（Geyser + Floodgate）

#### 概要

Java サーバーに Geyser / Floodgate プラグインを追加し、Bedrock クライアントから参加可能にする。

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    ports:
      - "${MC_PORT:-25565}:25565"
      - "19132:19132/udp"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-4G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      PLUGINS: |
        https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot
        https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

#### ポート

- 25565/TCP — Java クライアント
- 19132/UDP — Bedrock クライアント

---

### UC-H: プラグイン開発環境

#### 概要

Paper API を使ったプラグイン開発用サーバー。ホットデプロイまたは再起動でテスト。

#### 前提条件

- ローカル開発マシン（WSL2 推奨）
- Gradle プロジェクト（別リポジトリ）

#### docker-compose.yml

```yaml
services:
  mc:
    image: itzg/minecraft-server:latest
    ports:
      - "25565:25565"
    environment:
      EULA: "TRUE"
      TYPE: "PAPER"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "2G"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}-dev§r"
      ONLINE_MODE: "FALSE"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
      - ./plugins-dev:/data/plugins
    restart: unless-stopped
```

#### 開発フロー

1. Gradle で `build` → `.jar` 生成
2. `plugins-dev/` にコピー
3. `make restart` または RCON `reload confirm`（非推奨 — 再起動推奨）

#### 参考リンク

- [KevinTCoughlin/minecraft-server](https://github.com/KevinTCoughlin/minecraft-server)

---

### UC-I: GitOps / VPS 本番（上級）

#### 概要

VPS 上での GitOps デプロイ。Webhook による自動更新。

#### 方針

- 本指示書では**概要のみ**記載
- 詳細は [blueprint-minecraft-server-gitops](https://github.com/timo-reymann/blueprint-minecraft-server-gitops) を参照
- bind mount / `restart: unless-stopped` / `USE_AIKAR_FLAGS` の原則は維持
- systemd による compose 起動は**依然禁止** — Docker restart ポリシーに委ねる

#### 最小構成要素

- Git リポジトリに compose + `.env.example`
- デプロイ webhook → `git pull && make update`
- 手動バックアップ（`make backup`）をデプロイ前に実行

---

### UC-J: Vanilla バニラサーバー（最小構成）

#### 概要

プラグイン・MOD なしの最小 Vanilla Java サーバー。動作確認・学習用。

#### 前提条件

- RAM: 2GB+
- ディスク: 5GB+

#### docker-compose.yml

```yaml
name: ${COMPOSE_PROJECT_NAME}

services:
  mc:
    image: itzg/minecraft-server:latest
    pull_policy: daily
    tty: true
    stdin_open: true
    ports:
      - "${MC_PORT:-25565}:25565"
    environment:
      EULA: "TRUE"
      TYPE: "VANILLA"
      VERSION: "${VERSION:-LATEST}"
      MEMORY: "${MEMORY:-2G}"
      USE_AIKAR_FLAGS: "TRUE"
      OVERRIDE_SERVER_PROPERTIES: "TRUE"
      MOTD: "§6${SERVER_NAME}§r"
      MAX_PLAYERS: "${MAX_PLAYERS:-5}"
      UID: "${UID:-1000}"
      GID: "${GID:-1000}"
    volumes:
      - ./data:/data
    restart: unless-stopped
```

#### .env.example

```dotenv
SERVER_NAME=vanilla-test
MOTD=§6vanilla-test§r
TYPE=VANILLA
VERSION=1.21.1
MEMORY=2G
MAX_PLAYERS=5
```

#### 起動確認

```
[Server thread/INFO]: Done (XX.Xs)! For help, type "help"
```

---

## 第8章 — 環境変数リファレンス

### 8.1 プロジェクト共通変数

| 変数 | 必須 | 説明 | 例 |
|------|------|------|-----|
| **`SERVER_NAME`** | **Yes** | ヒアリングで決定。ルート Dir・バックアップ名・Compose 名 | `survival-2024` |
| **`MOTD`** | **Yes** | サーバー一覧 MOTD。`SERVER_NAME` から 1 行自動生成 | `§6survival-2024§r` |
| `COMPOSE_PROJECT_NAME` | Yes | Docker Compose プロジェクト名 | `survival-2024` |
| `MC_PORT` | No | Java ポート | `25565` |
| `RCON_PORT` | No | RCON ポート | `25575` |

### 8.2 itzg/minecraft-server 主要変数

| 変数 | 必須 | 説明 | 例 |
|------|------|------|-----|
| `EULA` | Yes | Mojang EULA 同意 | `TRUE` |
| `TYPE` | No | サーバー種別 | `PAPER`, `VANILLA`, `FABRIC`, `AUTO_CURSEFORGE` |
| `VERSION` | No | MC バージョン | `1.21.1`, `LATEST` |
| `MEMORY` | No | JVM ヒープ | `4G` |
| **`USE_AIKAR_FLAGS`** | **Yes** | JVM 性能最適化。**常に `TRUE`** | `TRUE` |
| `OVERRIDE_SERVER_PROPERTIES` | Yes | MOTD 等の env 反映 | `TRUE` |
| `MAX_PLAYERS` | No | 最大人数 | `10` |
| `ENABLE_RCON` | No | RCON 有効化 | `TRUE` |
| `RCON_PASSWORD` | RCON 時 | パスワード | `.env` 参照 |
| `UID` / `GID` | Linux 推奨 | ファイル所有者 | `1000` |
| `ONLINE_MODE` | No | 正規認証 | `TRUE` |
| `DIFFICULTY` | No | 難易度 | `normal` |
| `WHITE_LIST` | No | ホワイトリスト | `TRUE` |
| `VIEW_DISTANCE` | No | 描画距離 | `10` |
| `SPAWN_PROTECTION` | No | スポーン保護半径 | `16` |

### 8.3 モッドパック関連

| 変数 | 必須 | 説明 | 例 |
|------|------|------|-----|
| `CF_API_KEY` | CF 時 | CurseForge API キー | `.env` |
| `CF_PAGE_URL` | CF 時 | パック URL | `https://www.curseforge.com/...` |
| `CF_FILE_ID` | CF 時 | 特定ファイル ID（版固定） | `1234567` |
| `CF_PARALLEL_DOWNLOADS` | No | 並列 DL 数 | `8` |
| `CF_EXCLUDE_MODS` | No | 除外 MOD slug | `sodium` |
| `CF_FORCE_INCLUDE_MODS` | No | 強制包含 MOD | `fabric-api` |
| `MODRINTH_MODPACK` | MR 時 | Modrinth パック URL | `https://modrinth.com/modpack/...` |
| `MODRINTH_LOADER` | MR 時 | ローダー | `fabric`, `forge`, `quilt` |
| `MODRINTH_PROJECTS` | カスタム時 | MOD slug リスト | `fabric-api\nlithium` |
| `VERSION_FROM_MODRINTH_PROJECTS` | No | MC 版自動決定 | `TRUE` |

### 8.4 プラグイン関連

| 変数 | 説明 | 例 |
|------|------|-----|
| `PLUGINS` | プラグイン URL リスト（改行区切り） | GitHub releases URL |
| `MODS` | Fabric/Forge MOD URL リスト | Modrinth CDN URL |
| `SPIGET_RESOURCES` | Spiget リソース ID | `34315` |

### 8.5 ワールド・ゲーム設定

| 変数 | 説明 | 例 |
|------|------|-----|
| `LEVEL` | ワールド名 | `world` |
| `MODE` | ゲームモード | `survival`, `creative` |
| `PVP` | PVP 有効 | `TRUE` |
| `ALLOW_NETHER` | ネザー有効 | `TRUE` |
| `ANNOUNCE_PLAYER_ACHIEVEMENTS` | 実績通知 | `TRUE` |
| `ENABLE_COMMAND_BLOCK` | コマンドブロック | `FALSE` |
| `SNOOPER_ENABLED` | スヌーパー | `FALSE` |
| `GENERATE_STRUCTURES` | 構造物生成 | `TRUE` |
| `HARDCORE` | ハードコア | `FALSE` |

---

## 第9章 — エージェント実行チェックリスト

### Phase 0: 環境確認

- [ ] **`SERVER_NAME` をユーザーに確認・バリデーション（最優先）**
- [ ] **`SERVER_NAME` 確定後、`MOTD=§6${SERVER_NAME}§r` を自動設定**
- [ ] プロジェクトを `~/servers/${SERVER_NAME}/` に作成
- [ ] `docker --version` / `docker compose version` 確認
- [ ] 空きポート確認（Linux: `ss -tlnp`, Windows: `netstat -an`）
- [ ] 空きディスク確認
- [ ] Windows の場合: プロジェクト配置場所決定（WSL 推奨）
- [ ] `make check-path` で `/mnt/` パスを拒否

### Phase 1: 設計

- [ ] ヒアリング完了 or デフォルト明記
- [ ] UC 選定（UC-A 〜 UC-J）
- [ ] RAM / ディスク見積もり README に記載
- [ ] 必要 API キー一覧（CF 等）

### Phase 2: ファイル生成

- [ ] `docker-compose.yml`（bind mount、`restart: unless-stopped`、`USE_AIKAR_FLAGS: TRUE`、`MOTD` 必須）
- [ ] `.dockerignore`（`data/` 除外）
- [ ] `Makefile`（第5章参照）
- [ ] `.env.example` + `.gitignore`
- [ ] `scripts/backup.sh` + `scripts/restore.sh`（+ `.ps1`）
- [ ] `README.md`（`make help` 一覧、OS 別セクション）
- [ ] named volume が**存在しない**ことを確認

### Phase 3: 起動・検証

- [ ] `make config`
- [ ] `make up`（ユーザー明示指示時のみ）
- [ ] `make logs` で起動完了確認
  - Paper: `Done (XX.Xs)! For help, type "help"`
  - MOD: `Loading ... mods`
- [ ] `data/` ディレクトリ生成・権限確認
- [ ] サーバー一覧で MOTD（サーバー名）表示確認
- [ ] クライアント接続テスト

### Phase 4: 引き渡し

- [ ] README: 接続方法、MC 版、Mod 要件
- [ ] README: 起動 / 停止 / 再起動（OS 別）
- [ ] README: バックアップ / リストア
- [ ] README: 更新手順（`make update`）
- [ ] README: トラブルシューティング
- [ ] `.env` が gitignore されていることを確認
- [ ] systemd / cron が**設定されていない**ことを確認

---

## 第10章 — セキュリティ

### 10.1 認証

- `ONLINE_MODE=TRUE` をデフォルトとする（正規 Minecraft アカウント必須）
- インターネット公開時は `WHITE_LIST=TRUE` を推奨

### 10.2 RCON パスワード生成

**Linux / WSL**:

```bash
openssl rand -hex 16
```

**Windows（PowerShell）**:

```powershell
-join ((1..16) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
```

生成した値を `.env` の `RCON_PASSWORD` に設定。git 禁止。

### 10.3 秘密情報管理

| ファイル | git 管理 |
|----------|----------|
| `.env` | **禁止** |
| `CF_API_KEY` | `.env` 内のみ |
| `forwarding.secret` | **禁止** |
| `RCON_PASSWORD` | `.env` 内のみ |

### 10.4 ネットワーク

- インターネット公開時: ファイアウォールで必要ポートのみ開放
- RCON ポート（25575）は外部公開**非推奨**（必要時は VPN / SSH トンネル）
- Velocity `forwarding.secret` は Paper と Velocity で同一値を使用

### 10.5 禁止操作

- `docker compose down -v` — **絶対禁止**（README にも明記）
- `.env` の git コミット — **禁止**
- デフォルト RCON パスワードの使用 — **禁止**

---

## 第11章 — トラブルシューティング

### 11.1 OS 別対処表

| 症状 | Linux / WSL | Windows |
|------|-------------|---------|
| Permission denied on `data/` | `sudo chown -R $(id -u):$(id -g) data` | WSL 内に移動 |
| ポート使用中 | `ss -tlnp \| grep 25565` | `netstat -ano \| findstr 25565` |
| 遅い I/O | ディスク確認 `iostat` | WSL 外パス（`/mnt/c`）を使っている |
| OOM Killed | `dmesg \| grep -i oom`, `MEMORY` 増 | Docker Desktop → Resources → Memory 増 |
| ファイアウォール | `sudo ufw status` | Windows Defender ファイアウォール |
| 改行コード問題 | — | `.gitattributes` で `* text=auto` |
| MOTD 未表示 | `OVERRIDE_SERVER_PROPERTIES` 確認 | 同左 |
| コンテナ再起動ループ | `make logs` で原因確認 | 同左 |
| MOD ダウンロード失敗 | `CF_API_KEY` / ネットワーク確認 | WSL DNS 設定確認 |

### 11.2 よくある Docker 問題

**コンテナが起動しない**:

```bash
make config          # 構文エラー確認
docker compose logs  # エラーメッセージ確認
```

**データが消えた**:

- bind mount なら `./data` がホストに残っているはず
- `docker compose down -v` を実行していないか確認
- `data.old.*` 退避ディレクトリを確認

**イメージ更新後に起動失敗**:

```bash
make logs
# バージョン不一致 → VERSION を固定
# MOD 非互換 → バックアップからリストア
```

### 11.3 WSL2 固有

**メモリ不足**:

`%UserProfile%\.wslconfig` で `memory=8GB` 等に増加 → `wsl --shutdown`

**Docker Desktop 連携失敗**:

Settings → Resources → WSL Integration → 使用中 distro を ON

**`/mnt/c` 配置検出**:

```bash
make check-path
# ERROR → ~/servers/${SERVER_NAME}/ へ移動
```

---

## 第12章 — ユーザー向けプロンプト例

以下をユーザーがコピペして AI エージェントに渡す例。エージェントは本指示書に従って構築する。

### Paper（Linux VPS）

> サーバー名 `survival-2024` で Ubuntu VPS に Paper 1.21.1。10 人、EssentialsX + LuckPerms、4GB RAM、RCON、手動バックアップ（data 全体）。restart: unless-stopped、systemd なし。

### Paper（Windows 自宅）

> Windows 11 + WSL2 で Paper サーバー。サーバー名 `friends-mc`。友達 3 人 LAN 公開。data/ は bind mount。MOTD は SERVER_NAME から自動。

### CurseForge MOD

> サーバー名 `atm10-home` で ATM10 を CurseForge から。CF_API_KEY あり。RAM 12GB。WSL2。bind mount のみ。

### Modrinth パック

> サーバー名 `fo-server` で Fabulously Optimized を Modrinth から。Fabric、6GB RAM。

### Velocity

> サーバー名 `network-01` で Velocity + ロビー + サバイバル。Docker Compose。WSL2。forwarding.secret 設定含む。

### Bedrock

> サーバー名 `bedrock-pe` で Windows + WSL2 上に Bedrock Dedicated Server。UDP 19132。

### プラグイン開発

> サーバー名 `plugin-dev` で Paper 開発環境。ONLINE_MODE=false、2GB RAM。plugins-dev/ マウント。

### Vanilla 最小

> サーバー名 `vanilla-test` で Vanilla 1.21.1。2GB RAM。動作確認用。

### カスタム MOD

> サーバー名 `fabric-custom` で Fabric + Modrinth から fabric-api, lithium, sodium。4GB RAM。

### クロスプレイ

> サーバー名 `crossplay` で Paper + Geyser + Floodgate。Java + Bedrock 両対応。

---

## 第13章 — 参考リンク

### 主要リポジトリ

| 用途 | リポジトリ |
|------|-----------|
| 万能 Java サーバー | [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) |
| Bedrock 専用 | [itzg/docker-minecraft-bedrock-server](https://github.com/itzg/docker-minecraft-bedrock-server) |
| Velocity / BungeeCord | [itzg/docker-mc-proxy](https://github.com/itzg/docker-mc-proxy) |
| GitOps（Paper） | [timo-reymann/blueprint-minecraft-server-gitops](https://github.com/timo-reymann/blueprint-minecraft-server-gitops) |
| プラグイン開発 | [KevinTCoughlin/minecraft-server](https://github.com/KevinTCoughlin/minecraft-server) |
| プロキシ例 | [heyvaldemar/minecraft-server-proxy-docker-compose](https://github.com/heyvaldemar/minecraft-server-proxy-docker-compose) |
| IaC（クラウド時） | [nolte/minecraft-infrastructure](https://github.com/nolte/minecraft-infrastructure) |

### ドキュメント

- [itzg 公式ドキュメント](https://docker-minecraft-server.readthedocs.io/)
- [examples ディレクトリ](https://github.com/itzg/docker-minecraft-server/tree/master/examples)
- [CurseForge API Key 取得](https://console.curseforge.com/)
- [Modrinth](https://modrinth.com/)
- [Paper MC](https://papermc.io/)
- [Velocity 公式](https://docs.papermc.io/velocity/)
- [Geyser MC](https://geysermc.org/)

### 除外対象（本指示書の範囲外）

以下は「ゲーム内 AI ボット」であり、本指示書の対象外:

- Minecraft_AI
- mindcraft-ce
- AgentCraft

---

## 付録 A — 禁止事項まとめ

| # | 禁止事項 | 代替 |
|---|----------|------|
| 1 | Docker named volume | bind mount `./data:/data` |
| 2 | `docker compose down -v` | `make down`（`-v` なし） |
| 3 | systemd unit / cron timer | compose `restart: unless-stopped` |
| 4 | 自動バックアップ（cron 等） | 手動 `make backup` |
| 5 | Windows `/mnt/c/` 配置 | WSL home 内配置 |
| 6 | `USE_AIKAR_FLAGS: "FALSE"` | 常に `"TRUE"` |
| 7 | MOTD 省略 | `§6${SERVER_NAME}§r` |
| 8 | 固定名 `minecraft-server/` | `${SERVER_NAME}/` |
| 9 | CurseForge サーバー専用 zip | クライアント用パック URL |
| 10 | Velocity で `127.0.0.1` | Docker サービス名（`lobby:25565`） |

---

## 付録 B — 調査サマリー（GitHub 先駆者）

| 用途 | 代表リポジトリ | 指示書での位置づけ |
|------|---------------|-------------------|
| 万能 Java サーバー | itzg/docker-minecraft-server | **第一選択。全 UC の基盤** |
| Bedrock 専用 | itzg/docker-minecraft-bedrock-server | UC-F |
| Velocity/BungeeCord | itzg/docker-mc-proxy | UC-E |
| GitOps（Paper） | blueprint-minecraft-server-gitops | UC-I（上級） |
| プラグイン開発 | KevinTCoughlin/minecraft-server | UC-H |
| プロキシ例 | heyvaldemar/minecraft-server-proxy-docker-compose | UC-E（Windows パス差分参考） |
| IaC | nolte/minecraft-infrastructure | 付録（クラウド時のみ） |

---

*本指示書に従い、エージェントは再現性の高い Minecraft サーバー環境を構築すること。*
