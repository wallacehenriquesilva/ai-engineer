#!/bin/bash
# org-watch.sh — Atualização delta do knowledge base
# Detecta merges recentes e reindexa apenas os repos afetados.
# Uso: ./scripts/org-watch.sh
# Cron: 0 * * * * cd /path/to/ai-engineer && make watch >> ~/.ai-engineer/watch.log 2>&1

set -e

# ── Configuração ──────────────────────────────────────────────────────────────

ORG="${GITHUB_ORG:?Defina GITHUB_ORG no .env}"
LIMIT="${REPO_LIMIT:-200}"
SERVICE="${KNOWLEDGE_SERVICE_URL:-http://localhost:8080}"
REPOS_DIR="${REPOS_DIR:-$HOME/git}"
SINCE_HOURS="${SINCE_HOURS:-24}"
STATE_FILE="${STATE_FILE:-$HOME/.ai-engineer/.watch-state}"
LOG_DIR="$HOME/.ai-engineer"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
log_ok()   { echo -e "${GREEN}[ok]${NC} $1"; }
log_info() { echo -e "${CYAN}[->]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
log_err()  { echo -e "${RED}[xx]${NC} $1"; }

mkdir -p "$LOG_DIR"

# ── Validações ────────────────────────────────────────────────────────────────

command -v gh   >/dev/null 2>&1 || { log_err "gh CLI nao encontrado."; exit 1; }
command -v jq   >/dev/null 2>&1 || { log_err "jq nao encontrado.";     exit 1; }
command -v curl >/dev/null 2>&1 || { log_err "curl nao encontrado.";   exit 1; }

if ! curl -sf "$SERVICE/health" >/dev/null 2>&1; then
  log_err "Knowledge service nao acessivel em $SERVICE"
  exit 1
fi

# ── Janela de tempo ───────────────────────────────────────────────────────────

if [ -f "$STATE_FILE" ]; then
  SINCE=$(cat "$STATE_FILE")
else
  # Primeira execucao
  if date --version >/dev/null 2>&1; then
    SINCE=$(date -u -d "$SINCE_HOURS hours ago" +%Y-%m-%dT%H:%M:%SZ)
  else
    SINCE=$(date -u -v-"${SINCE_HOURS}"H +%Y-%m-%dT%H:%M:%SZ)
  fi
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo ""
echo -e "${CYAN}AI Engineer — Watch (delta)${NC}"
echo -e "${CYAN}===========================${NC}"
echo ""
log_info "Verificando merges desde: $SINCE"
log_info "Org: $ORG"
echo ""

# ── Detectar repos com merges ─────────────────────────────────────────────────

log_info "Listando repos..."
REPOS=$(gh repo list "$ORG" \
  --limit "$LIMIT" \
  --json name,primaryLanguage,isArchived \
  | jq -r '.[] | select(.isArchived == false) | [.name, (.primaryLanguage.name // "unknown")] | @tsv')

changed=()

while IFS=$'\t' read -r name language; do
  merges=$(gh api "repos/$ORG/$name/commits" \
    -f since="$SINCE" \
    -f until="$NOW" \
    -f per_page=10 \
    --jq '[.[] | select(
      (.commit.message | startswith("Merge")) or
      (.parents | length > 1)
    )] | length' 2>/dev/null || echo "0")

  if [ "$merges" -gt 0 ] 2>/dev/null; then
    log_info "$name — $merges merge(s)"
    changed+=("$name:$language")
  fi
done <<< "$REPOS"

if [ "${#changed[@]}" -eq 0 ]; then
  log_ok "Nenhum merge detectado desde $SINCE."
  echo "$NOW" > "$STATE_FILE"
  exit 0
fi

log_info "${#changed[@]} repo(s) com mudancas."
echo ""

# ── Reingerir repos afetados ──────────────────────────────────────────────────

generate_summary() {
  local name="$1"
  local repo_path="$2"
  local lang="$3"
  local repo_type="$4"
  local tmp_content="$5"

  # Prioridade 1: CLAUDE.md existente
  if [ -f "$repo_path/CLAUDE.md" ]; then
    cat "$repo_path/CLAUDE.md" > "$tmp_content"
    echo "claude-md"
    return
  fi

  # Prioridade 2: AI.md existente
  if [ -f "$repo_path/AI.md" ]; then
    cat "$repo_path/AI.md" > "$tmp_content"
    echo "ai-md"
    return
  fi

  # Prioridade 3: Gerar via Gemini
  [ -z "$GEMINI_API_KEY" ] && echo "skip" && return

  local context=""

  for f in README.md readme.md Readme.md; do
    [ -f "$repo_path/$f" ] && {
      context="${context}$(head -c 2000 "$repo_path/$f")\n\n"
      break
    }
  done

  [ -f "$repo_path/go.mod" ] && \
    context="${context}$(head -c 500 "$repo_path/go.mod")\n\n"

  [ -f "$repo_path/package.json" ] && \
    context="${context}$(jq '{name,description,dependencies}' "$repo_path/package.json" 2>/dev/null | head -c 500)\n\n"

  local structure
  structure=$(find "$repo_path" -maxdepth 2 \
    -not -path "*/.git/*" -not -path "*/vendor/*" \
    -not -path "*/node_modules/*" \
    | sed "s|$repo_path/||" | sort | head -30)
  context="${context}Estrutura:\n${structure}\n\n"

  for main_file in main.go cmd/main.go src/main.go index.js index.ts app.py; do
    [ -f "$repo_path/$main_file" ] && {
      context="${context}$(head -c 1000 "$repo_path/$main_file")\n\n"
      break
    }
  done

  local prompt="Analise o repositorio '$name' (linguagem: $lang, tipo: $repo_type) com base nas informacoes abaixo e gere um resumo tecnico em portugues em formato CLAUDE.md.

O resumo deve conter:
- O que o servico faz (proposito principal)
- Como ele se encaixa na arquitetura (consumidor de eventos, API, worker, infra, etc.)
- Topicos SQS/Kafka, endpoints HTTP ou recursos Terraform principais (se houver)
- Padroes tecnicos relevantes (ex: clean architecture, consumer/usecase/gateway)
- Dependencias externas importantes (ex: Segment, Braze, SendGrid)
- Como rodar e testar localmente (se houver informacao)

Seja conciso e tecnico. Maximo 400 palavras.

CONTEXTO DO REPOSITORIO:
${context}"

  local prompt_file
  prompt_file=$(mktemp)
  printf '%s' "$prompt" > "$prompt_file"

  local payload
  payload=$(jq -n \
    --rawfile prompt "$prompt_file" \
    '{contents:[{parts:[{text:$prompt}]}]}')

  rm -f "$prompt_file"

  local response
  response=$(curl -sf -X POST \
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null)

  [ -z "$response" ] && echo "skip" && return

  local summary
  summary=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)

  [ -z "$summary" ] && echo "skip" && return

  printf '%s' "$summary" > "$tmp_content"
  echo "generated"
}


  local repo="$1" section="$2" content="$3" lang="$4" repo_type="$5"
  [ -z "$content" ] && return

  if [ ${#content} -gt 6000 ]; then
    content="${content:0:6000}
...[truncado]"
  fi

  payload=$(jq -n \
    --arg repo "$repo" \
    --arg section "$section" \
    --arg content "$content" \
    --arg lang "$lang" \
    --arg repo_type "$repo_type" \
    '{repo: $repo, section: $section, content: $content, lang: $lang, repo_type: $repo_type}')

  curl -sf -X POST "$SERVICE/ingest" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null 2>&1 || log_warn "Falha ao ingerir $repo::$section"
}

for entry in "${changed[@]}"; do
  name="${entry%%:*}"
  language="${entry##*:}"

  repo_type="service"
  echo "$name" | grep -q "\-infra$" && repo_type="infra"

  # Localiza ou clona
  repo_path=$(find "$REPOS_DIR" -maxdepth 2 -type d -name "$name" 2>/dev/null | head -1)
  tmp_dir=""

  if [ -z "$repo_path" ]; then
    tmp_dir=$(mktemp -d)
    if ! gh repo clone "$ORG/$name" "$tmp_dir/$name" -- --depth=1 --quiet 2>/dev/null; then
      log_warn "$name — clone falhou, pulando."
      rm -rf "$tmp_dir"
      continue
    fi
    repo_path="$tmp_dir/$name"
  else
    git -C "$repo_path" pull --quiet 2>/dev/null || log_warn "$name — pull falhou, usando versao local."
  fi

  # Commits recentes para contexto
  recent=$(gh api "repos/$ORG/$name/commits" \
    -f since="$SINCE" -f per_page=10 \
    --jq '.[] | "- " + .commit.message[0:80]' 2>/dev/null | head -10 || true)

  # Remove chunks antigos
  curl -sf -X DELETE "$SERVICE/repo/$name" >/dev/null 2>&1 || true

  # Reingerir
  # summary — CLAUDE.md, AI.md ou gerado pelo Gemini
  summary_source=$(generate_summary "$name" "$repo_path" "$lang" "$repo_type" "$tmp_content")
  case "$summary_source" in
    claude-md)  ingest_chunk "$name" "summary" "$tmp_content" "$lang" "$repo_type"
                log_info "$name — summary do CLAUDE.md" ;;
    ai-md)      ingest_chunk "$name" "summary" "$tmp_content" "$lang" "$repo_type"
                log_info "$name — summary do AI.md" ;;
    generated)  ingest_chunk "$name" "summary" "$tmp_content" "$lang" "$repo_type"
                log_info "$name — summary gerado pelo Gemini" ;;
    skip)       log_warn "$name — summary pulado" ;;
  esac

  ingest_chunk "$name" "overview" \
    "Repositorio: $name
Linguagem: $language
Tipo: $repo_type
Atualizado em: $NOW
Commits recentes:
$recent" "$language" "$repo_type"

  for f in README.md readme.md; do
    [ -f "$repo_path/$f" ] && {
      ingest_chunk "$name" "readme" "$(head -c 4000 "$repo_path/$f")" "$language" "$repo_type"
      break
    }
  done

  [ -f "$repo_path/CLAUDE.md" ] && \
    ingest_chunk "$name" "claude-md" "$(cat "$repo_path/CLAUDE.md")" "$language" "$repo_type"

  structure=$(find "$repo_path" -maxdepth 3 \
    -not -path "*/.git/*" -not -path "*/vendor/*" -not -path "*/node_modules/*" \
    | sed "s|$repo_path/||" | sort | head -60 || true)
  ingest_chunk "$name" "structure" "Estrutura de $name:

$structure" "$language" "$repo_type"

  [ -f "$repo_path/go.mod" ] && \
    ingest_chunk "$name" "go-mod" "$(cat "$repo_path/go.mod")" "$language" "$repo_type"

  env_vars=$(grep -rh "os.Getenv\|viper.Get\|process.env\." \
    "$repo_path" --include="*.go" --include="*.js" --include="*.ts" 2>/dev/null \
    | grep -oE '"[A-Z_]+"' | sort -u | head -30 || true)
  [ -n "$env_vars" ] && \
    ingest_chunk "$name" "env-vars" "Variaveis de ambiente de $name:
$env_vars" "$language" "$repo_type"

  [ -n "$tmp_dir" ] && rm -rf "$tmp_dir"
  log_ok "$name atualizado"
done

# ── Salvar estado ─────────────────────────────────────────────────────────────

echo "$NOW" > "$STATE_FILE"

echo ""
log_ok "Watch concluido. ${#changed[@]} repo(s) atualizados."
log_info "Proximo watch verificara desde: $NOW"
echo ""