<div align="center">

<p align="center">
  <img src="docs/assets/logo.png" alt="mc-server-agent-brief" width="100" height="100">
</p>

<h1 align="center">:sunny: Minecraft サーバー構築 — AI エージェント向け :crescent_moon:</h1>

<p align="center">
  Docker で Minecraft サーバーを構築する AI エージェント向け指示書と参照実装。
  <br>
  Paper / モッドパック / Velocity / Bedrock — Linux・Windows (WSL2)。
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://github.com/itzg/docker-minecraft-server"><img src="https://img.shields.io/badge/Docker-itzg%2Fminecraft--server-2496ED?logo=docker&logoColor=white" alt="Docker"></a>
  <a href="https://github.com/flll/mc-server-agent-brief"><img src="https://img.shields.io/github/stars/flll/mc-server-agent-brief?style=social" alt="GitHub stars"></a>
</p>

<h2 align="center">
  <a href="#クイックスタート">概要</a> |
  <a href="docs/ja/minecraft-server-agent-brief.md">指示書</a> |
  <a href="AGENTS.ja.md">Agents</a> |
  <a href="Makefile">Makefile</a> |
  <a href="#ライセンス">License</a>
</h2>

<h4 align="center">Translations:</h4>

<p align="center">
  <a href="README.md"><img src="https://img.shields.io/badge/-EN-red?style=flat-square" alt="EN"></a> |
  JP
</p>

<p align="center"><sub>この指示書が、エージェントの Minecraft サーバー構築の定番ガイドになることを。</sub></p>

</div>

AI エージェント（Cursor / Claude Code 等）が Docker で Minecraft サーバーを構築するための**指示書**と**参照実装**（Makefile・バックアップスクリプト）です。

> **Note:** ゲーム内 AI ボット（[AgentCraft](https://github.com/wrxck/AgentCraft) や Steve 等）ではありません。**サーバーインフラ構築**のための指示書です。

---

## 含まれるもの

| ファイル | 内容 |
|----------|------|
| [docs/ja/minecraft-server-agent-brief.md](docs/ja/minecraft-server-agent-brief.md) | 詳細指示書（日本語） |
| [docs/en/minecraft-server-agent-brief.md](docs/en/minecraft-server-agent-brief.md) | Detailed brief (English) |
| [AGENTS.ja.md](AGENTS.ja.md) | エージェント向け最短入口 |
| [Makefile](Makefile) | 日常操作の統一入口 |
| [scripts/](scripts/) | バックアップ / リストア（Linux + Windows） |
| [.env.example](.env.example) | 環境変数テンプレート |

エージェントがサーバーを構築した際に生成する **各サーバー用 `README.md`** とは別物です。本 README は**このリポジトリ自体**の説明です。

---

## クイックスタート

### 1. エージェントに指示書を渡す

```text
docs/ja/minecraft-server-agent-brief.md を読んで、Minecraft サーバーを構築してください。
```

または [AGENTS.ja.md](AGENTS.ja.md) を Cursor Rules / プロジェクトルールにリンクしてください。

### 2. エージェントが生成するプロジェクト

エージェントは `~/servers/${SERVER_NAME}/` に以下を生成します:

- `docker-compose.yml`（bind mount、`restart: unless-stopped`）
- `.env` / `.env.example`
- `Makefile`（本リポジトリの参照実装をベースに）

### 3. サーバー起動（ユーザー操作）

```bash
cd ~/servers/your-server-name
cp .env.example .env   # SERVER_NAME 等を編集
make init
make up
make logs
```

Windows では **WSL2 内**で `make` を実行することを推奨します。

---

## 主要方針

| 項目 | 方針 |
|------|------|
| 永続化 | bind mount `./data:/data` のみ（named volume 禁止） |
| 性能 | WSL2 では ext4 内に配置（`/mnt/c` 禁止） |
| 再起動 | `restart: unless-stopped`（systemd 禁止） |
| JVM | `USE_AIKAR_FLAGS: "TRUE"` 常時必須 |
| MOTD | `§6${SERVER_NAME}§r` を自動生成 |
| バックアップ | `./data` 全体を手動 `make backup` |

---

## 対応ユースケース（指示書 第7章）

- Paper / Purpur プラグインサーバー
- CurseForge / Modrinth モッドパック
- Fabric / Forge カスタム MOD
- Velocity プロキシ + 複数 Paper
- Bedrock Dedicated Server
- Geyser クロスプレイ
- プラグイン開発環境（参考）

基盤イメージ: [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server)

---

## Makefile コマンド（参照実装）

| コマンド | 説明 |
|----------|------|
| `make help` | ターゲット一覧 |
| `make init` | 初回セットアップ（`.env`、ディレクトリ作成） |
| `make config` | compose 構文検証 |
| `make up` | 起動 |
| `make down` | 停止 |
| `make restart` | 再起動 |
| `make logs` | ログ追跡 |
| `make status` | コンテナ状態 |
| `make pull` | イメージ更新取得 |
| `make update` | イメージ更新 + 再起動 |
| `make backup` | `./data` 全体バックアップ |
| `make restore` | `RESTORE=backups/xxx.tar.gz make restore` |
| `make shell` | コンテナに入る |
| `make rcon CMD="list"` | RCON コマンド実行 |
| `make check-path` | WSL 遅いパス検出 |

---

## ユーザープロンプト例

```text
サーバー名 survival-2024 で Paper 1.21.1。10人、4GB RAM、RCON 有効。
docs/ja/minecraft-server-agent-brief.md に従って構築して。
```

```text
CurseForge の All the Mods 10。RAM 12GB。WSL2。
mc-server-agent-brief の指示書に従って。
```

---

## ドキュメント保守

指示書の更新は **日本語（`docs/ja/`）を正** とし、英語（`docs/en/`）も同章を同期してください。

---

## ライセンス

[MIT License](LICENSE)

---

## 関連リンク

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server)
- [docker-minecraft-server ドキュメント](https://docker-minecraft-server.readthedocs.io/)
