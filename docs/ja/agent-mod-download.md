# エージェント向け MOD ダウンロード手順

modded サーバー運用で MOD jar を取得するときの標準ワークフロー。

## 取得優先順位

1. **Modrinth**（API キー不要・最優先）
2. **CurseForge API**（`CF_API_KEY` 必要）
3. **GitHub Releases**（個人製 fix MOD 等）

## 前提

| 項目 | 内容 |
|------|------|
| スクリプト | [`scripts/download-mod.sh`](../../scripts/download-mod.sh) |
| Modrinth | API キー不要 |
| CurseForge | `CF_API_KEY` が必要（**git にコミットしない**） |
| 秘密の読み込み順 | `~/.cursor/secrets/secret.env` → プロジェクト `.env` |

## CF_API_KEY の管理（実運用での事故例に基づく）

`CF_API_KEY` は **[CurseForge Console](https://console.curseforge.com/)**（API Keys 画面）で発行したものだけを使う。`$2a$10$` で始まる文字列は正規の CF キー形式だが、**bcrypt パスワードハッシュ等の誤った値**では `Forbidden: API Key missing or invalid`（HTTP **403**）になる。

書き方（**単一引用符必須** — `$` が bash に展開されるとキーが壊れる）:

```bash
CF_API_KEY='$2a$10$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
```

検証（キー本体は表示しない）:

```bash
set -a; . ~/.cursor/secrets/secret.env; set +a
test -n "$CF_API_KEY" && echo "CF_API_KEY: set (${#CF_API_KEY} chars)"
curl -sS -o /dev/null -w "GET /v1/games -> HTTP %{http_code}\n" \
  -H "x-api-key: ${CF_API_KEY}" -H "Accept: application/json" \
  https://api.curseforge.com/v1/games
# 200 = 有効 / 401 or 403 = 再発行が必要
```

## 使い方

```bash
# Modrinth — 最新版（game_version / loader で絞り込み）
scripts/download-mod.sh modrinth <slug> [game_version] [loader] -o <dir>

# CurseForge — ファイル ID 指定（Modrinth 未掲載 MOD 向け）
# modIdOrSlug は公式 API が 403 のとき必須（www API フォールバック）
scripts/download-mod.sh curseforge-file <fileId> [modIdOrSlug] -o <dir>
```

## エージェントワークフロー（サーバー MOD 更新）

1. **`make backup`** — 必ず先にバックアップ（例外なし）
2. **ダウンロード** — `download-mod.sh` で `DATA_DIR/mods/` に jar を配置
3. **旧版削除** — 同 MOD の古い jar を削除（`.jar.disabled` も確認）
4. **マニフェスト更新** — `scripts/gen-mods-manifest.sh`
5. **`make restart`** — ログで MOD ロードを確認
6. **git commit** — 秘密ファイル・jar 本体は含めない

## セキュリティ

- スクリプトは API キーの値を標準出力に出さず、`curl` エラー時もマスクする
- `.env` / `secret.env` はコミット禁止
- キーの値をチャット・ログに貼らない（長さ・先頭数文字のみで検証）

## トラブルシュート

| 症状 | 対処 |
|------|------|
| `CF_API_KEY is not set` | `~/.cursor/secrets/secret.env` または `.env` に設定 |
| `401` / `403` | console.curseforge.com で新規キー発行 → 単一引用符で設定し直す |
| 公式 API 403 だが jar が必要 | `modIdOrSlug` を付けて実行（www API フォールバック） |
| Modrinth `no matching versions` | slug / game_version / loader を見直す |
