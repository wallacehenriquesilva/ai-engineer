.PHONY: help setup up down restart logs install scan watch build test clean

# Carrega .env se existir
-include .env
export

KNOWLEDGE_DIR := knowledge-service
SCRIPTS_DIR   := scripts
ORG           ?= $(GITHUB_ORG)
LIMIT         ?= $(REPO_LIMIT)

# ── Help ──────────────────────────────────────────────────────────────────────

help: ## Exibe esta ajuda
	@echo ""
	@echo "  AI Engineer — Comandos disponíveis"
	@echo "  ===================================="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ── Diagnóstico ──────────────────────────────────────────────────────────────

check: ## Verifica se o ambiente está pronto (dependências, MCPs, auth, skills)
	@bash scripts/check.sh

# ── Setup inicial ─────────────────────────────────────────────────────────────

setup: ## Configuração completa: copia .env, sobe serviços e faz carga inicial
	@echo ""
	@echo "→ Verificando dependências..."
	@command -v docker  >/dev/null 2>&1 || (echo "Docker não encontrado. Instale em https://docker.com" && exit 1)
	@command -v gh      >/dev/null 2>&1 || (echo "gh CLI não encontrado. Instale com: brew install gh" && exit 1)
	@command -v jq      >/dev/null 2>&1 || (echo "jq não encontrado. Instale com: brew install jq" && exit 1)
	@echo ""
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "✅ .env criado a partir de .env.example"; \
		echo "⚠️  Edite o .env com seus dados antes de continuar."; \
		echo ""; \
		exit 1; \
	fi
	@$(MAKE) up
	@echo ""
	@echo "⏳ Aguardando Ollama baixar o modelo de embeddings..."
	@docker compose -f $(KNOWLEDGE_DIR)/docker-compose.yml logs -f ollama-pull 2>/dev/null || true
	@echo ""
	@$(MAKE) scan
	@$(MAKE) install
	@echo ""
	@echo "✅ Setup concluído! Execute: cd ~/git && /run"
	@echo ""

# ── Knowledge Service ─────────────────────────────────────────────────────────

up: ## Sobe postgres + ollama + knowledge-service
	@echo "→ Subindo knowledge service..."
	@docker compose -f $(KNOWLEDGE_DIR)/docker-compose.yml up -d
	@echo "✅ Serviços no ar. API em http://localhost:8080"

down: ## Derruba todos os serviços
	@docker compose -f $(KNOWLEDGE_DIR)/docker-compose.yml down

restart: ## Reinicia o knowledge-service
	@docker compose -f $(KNOWLEDGE_DIR)/docker-compose.yml restart knowledge-service

logs: ## Exibe logs do knowledge-service em tempo real
	@docker compose -f $(KNOWLEDGE_DIR)/docker-compose.yml logs -f knowledge-service

health: ## Verifica saúde do knowledge-service
	@curl -s http://localhost:8080/health | jq .

repos: ## Lista repos indexados no knowledge base
	@curl -s http://localhost:8080/repos | jq -r '.[] | "[\(.lang)] \(.repo) — \(.chunks) chunks — \(.last_updated)"'

# ── Knowledge Base ────────────────────────────────────────────────────────────

scan: ## Carga inicial — escaneia todos os repos da org
	@echo "→ Iniciando carga inicial da org $(ORG)..."
	@ORG=$(ORG) LIMIT=$(LIMIT) OUTPUT_DIR=$(OUTPUT_DIR) \
		REPOS_DIR=$(REPOS_DIR) bash $(SCRIPTS_DIR)/org-scan.sh

watch: ## Atualiza repos com merges recentes (delta)
	@echo "→ Verificando merges recentes em $(ORG)..."
	@cd $(KNOWLEDGE_DIR) && \
		KNOWLEDGE_SERVICE_URL=$(KNOWLEDGE_SERVICE_URL) \
		GITHUB_TOKEN=$(GITHUB_TOKEN) \
		GITHUB_ORG=$(ORG) \
		SINCE_HOURS=$(SINCE_HOURS) \
		go run ./cmd/watch/main.go

watch-docker: ## Roda o job watch via Docker
	@docker compose -f $(KNOWLEDGE_DIR)/docker-compose.yml \
		--profile watch run --rm org-watch

cron-install: ## Instala cron para atualização automática a cada hora
	@(crontab -l 2>/dev/null; echo "0 * * * * cd $(PWD) && make watch >> ~/.ai-engineer/watch.log 2>&1") | crontab -
	@echo "✅ Cron instalado — watch roda a cada hora."

cron-remove: ## Remove o cron de atualização automática
	@crontab -l 2>/dev/null | grep -v "make watch" | crontab -
	@echo "✅ Cron removido."

# ── Instalação ────────────────────────────────────────────────────────────────

install: ## Setup completo com onboarding interativo
	@bash install.sh

install-skills: ## Instala apenas skills e commands (sem onboarding)
	@bash install.sh --skills

update: ## Atualiza para a versão mais recente
	@bash install.sh --update

version: ## Exibe a versão instalada
	@cat VERSION 2>/dev/null || echo "desconhecida"
	@echo -n "Instalada: " && cat ~/.ai-engineer/VERSION 2>/dev/null || echo "não instalada"

# ── Build ─────────────────────────────────────────────────────────────────────

build: ## Builda a imagem Docker do knowledge-service
	@docker compose -f $(KNOWLEDGE_DIR)/docker-compose.yml build knowledge-service

build-go: ## Compila o binário Go localmente
	@cd $(KNOWLEDGE_DIR) && CGO_ENABLED=0 go build -o knowledge-service ./cmd/server
	@echo "✅ Binário gerado: $(KNOWLEDGE_DIR)/knowledge-service"

# ── Testes ────────────────────────────────────────────────────────────────────

test: ## Roda os testes Go
	@cd $(KNOWLEDGE_DIR) && go test ./...

test-skills: ## Valida estrutura de skills, commands e scripts
	@bash tests/test-skills.sh

test-exec-log: ## Testa o sistema de log de execuções
	@bash tests/test-execution-log.sh

test-agents: ## Valida estrutura, contratos JSON e coerência dos agents
	@bash tests/test-agents.sh

test-classifier: ## Testes unitários do task-classifier e runbook-matcher
	@bash tests/test-task-classifier.sh

test-pipeline: ## Testes de cenários do pipeline (sem LLM real)
	@bash tests/test-pipeline.sh

test-pipeline-verbose: ## Testes de cenários do pipeline com output detalhado
	@bash tests/test-pipeline.sh --verbose

test-all: test test-skills test-exec-log test-agents test-classifier test-pipeline ## Roda todos os testes

test-query: ## Testa uma query semântica no knowledge service
	@read -p "Query: " q; \
	curl -s -X POST http://localhost:8080/query \
		-H "Content-Type: application/json" \
		-d "{\"query\": \"$$q\", \"top_k\": 3}" \
		| jq -r '.results[] | "[\(.score * 100 | round)%] \(.repo) — \(.section)\n\(.content | .[0:200])\n"'

# ── Observabilidade ───────────────────────────────────────────────────────────

history: ## Exibe estatísticas das últimas execuções
	@source scripts/execution-log.sh && exec_log_stats ${DAYS:-30}

history-list: ## Lista as últimas N execuções
	@source scripts/execution-log.sh && exec_log_history --limit ${LIMIT:-20} | jq -r '.[] | "[\(.status)] \(.started_at | .[0:10]) \(.command) \(.task) \(.repo) \(.duration_seconds/60 | floor)min $\(.cost_usd // 0)"'

# ── Execução Paralela ────────────────────────────────────────────────────────

run-parallel: ## Executa múltiplas tasks em paralelo
	@WORKERS=${WORKERS:-3} bash scripts/run-parallel.sh

run-loop: ## Executa /run em loop contínuo (contexto limpo a cada task)
	@bash scripts/run-loop.sh --interval ${INTERVAL:-5} --max ${MAX:-0} --command ${COMMAND:-run}

# ── Limpeza ───────────────────────────────────────────────────────────────────

clean: ## Remove containers, volumes e dados locais
	@echo "⚠️  Isso irá remover todos os dados do knowledge base."
	@read -p "Tem certeza? (s/N): " c; \
	if [ "$$c" = "s" ] || [ "$$c" = "S" ]; then \
		docker compose -f $(KNOWLEDGE_DIR)/docker-compose.yml down -v; \
		echo "✅ Dados removidos."; \
	else \
		echo "Cancelado."; \
	fi

clean-knowledge: ## Remove apenas os dados do knowledge base (mantém o banco)
	@curl -s -X DELETE http://localhost:8080/repo/all 2>/dev/null || true
	@rm -rf $(OUTPUT_DIR)
	@echo "✅ Knowledge base limpo."