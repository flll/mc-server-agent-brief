.PHONY: help init config up down restart logs status pull update backup restore shell rcon check-path

COMPOSE := docker compose
ENV_FILE := .env
SCRIPTS := scripts

# .env を include（SERVER_NAME, COMPOSE_PROJECT_NAME 等）
-include $(ENV_FILE)
export $(shell sed -n 's/=.*//p' $(ENV_FILE) 2>/dev/null)

help: ## ターゲット一覧
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

init: ## 初回セットアップ（.env, SERVER_NAME 確認, ディレクトリ）
	@test -f $(ENV_FILE) || cp .env.example $(ENV_FILE)
	@grep -q '^SERVER_NAME=.' $(ENV_FILE) || (echo "ERROR: .env に SERVER_NAME を設定してください"; exit 1)
	@mkdir -p data backups config/plugins
	@$(MAKE) check-path
	@echo "Server: $$(grep ^SERVER_NAME= $(ENV_FILE) | cut -d= -f2)"
	@echo "Edit $(ENV_FILE) then run: make up"

check-path: ## 遅い bind mount パスを検出（WSL）
	@if echo "$$(pwd)" | grep -q '/mnt/'; then \
		echo "ERROR: /mnt/c 等の遅いパスです。WSL home (~/...) に移動してください"; exit 1; \
	fi

config: ## compose 構文検証
	$(COMPOSE) config

up: check-path ## 起動
	$(COMPOSE) up -d

down: ## 停止（volume 削除なし）
	$(COMPOSE) down

restart: down up ## 再起動

logs: ## ログ追跡
	$(COMPOSE) logs -f

status: ## コンテナ状態
	$(COMPOSE) ps

pull: ## イメージ更新取得
	$(COMPOSE) pull

update: pull up ## イメージ更新 + 再起動

backup: ## サーバーデータ全体バックアップ（./data 丸ごと）
	@bash $(SCRIPTS)/backup.sh

restore: ## RESTORE=backups/${SERVER_NAME}_data_xxx.tar.gz make restore
	@test -n "$(RESTORE)" || (echo "Usage: RESTORE=backups/$${SERVER_NAME}_data_xxx.tar.gz make restore"; exit 1)
	@bash $(SCRIPTS)/restore.sh "$(RESTORE)"

shell: ## コンテナに入る
	$(COMPOSE) exec mc bash

rcon: ## RCON 実行: make rcon CMD="list"
	$(COMPOSE) exec mc rcon-cli $(CMD)
