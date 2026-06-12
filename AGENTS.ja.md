# AGENTS.ja.md — エージェント向け最短入口

<h4 align="center">Translations:</h4>

<p align="center">
  <a href="AGENTS.md"><img src="https://img.shields.io/badge/-EN-red?style=flat-square" alt="EN"></a> |
  JP
</p>

このリポジトリは **Minecraft サーバーインフラ構築** 用の指示書です。ゲーム内 AI ボット（AgentCraft / Steve 等）ではありません。

## 必読

作業を開始する前に、以下を **全文読んで** から実装してください。

- [docs/ja/minecraft-server-agent-brief.md](docs/ja/minecraft-server-agent-brief.md)

## 作業順序（要約）

1. **`SERVER_NAME` をユーザーに確認**（最優先。未回答なら進めない）
2. `MOTD=§6${SERVER_NAME}§r` を自動設定
3. ホスト OS 確認（Linux / Windows+WSL2）
4. 第1章ヒアリング → ユースケース選定 → ファイル生成
5. `make config` で構文検証 → ユーザー引き渡し
6. サーバー稼働開始後は**独立した運用リポジトリへ卒業**（ブリーフ付録 C.1）

## 禁止事項

| 禁止 | 理由 |
|------|------|
| Docker named volume | bind mount `./data:/data` のみ |
| `docker compose down -v` | データ削除リスク |
| systemd unit / cron timer | OS 自動起動・定期実行なし |
| `/mnt/c/...` へのプロジェクト配置 | WSL I/O 性能劣化 |
| `USE_AIKAR_FLAGS` 省略 | Java サーバーでは常時 `TRUE` |
| jar / mrpack / zip の git 追加 | リポジトリ肥大（実例: .git 6.8GB）。`mods-manifest.tsv` で管理 |
| `make backup` なしの MOD 変更 | 運用での例外なしルール |

## 障害調査の定型（modded）

- クラッシュレポートが無い「壊れた」: クラッシュハンドラ MOD が例外を握りつぶしている可能性 — `latest.log` の WARN を見る
- 原因 MOD: スタックトレースの mixin 名 `handler$xxx$<modid>$...` で即特定
- 詳細はブリーフ付録 C.4

## 必須設定

- `restart: unless-stopped`（compose）
- `USE_AIKAR_FLAGS: "TRUE"`（Java）
- `OVERRIDE_SERVER_PROPERTIES: "TRUE"` + `MOTD`
- バックアップ: `./data` 全体 → `${SERVER_NAME}_data_${TIMESTAMP}.tar.gz`

## 参照実装（本リポジトリ）

- [Makefile](Makefile) — 日常操作
- [scripts/backup.sh](scripts/backup.sh) / [scripts/restore.sh](scripts/restore.sh)
- [scripts/download-mod.sh](scripts/download-mod.sh) — Modrinth / CurseForge MOD 取得（[手順](docs/ja/agent-mod-download.md)）
- [scripts/gen-mods-manifest.sh](scripts/gen-mods-manifest.sh) — mods-manifest.tsv（sha256 正本・jar を git 外に保つ）
- [scripts/diff-client-mods.sh](scripts/diff-client-mods.sh) — サーバー/クライアント jar 差分
- [.env.example](.env.example)

## 外部参照

- [itzg/docker-minecraft-server](https://github.com/itzg/docker-minecraft-server) — 第一選択の Docker イメージ
- [公式ドキュメント](https://docker-minecraft-server.readthedocs.io/)
