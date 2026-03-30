#!/bin/bash
# org-scan.sh — Carga inicial do knowledge base
# Uso: ./scripts/org-scan.sh [--org MyOrg] [--limit 200]

ORG="${GITHUB_ORG:?Defina GITHUB_ORG no .env}"
LIMIT="${REPO_LIMIT:-200}"
SERVICE="${KNOWLEDGE_SERVICE_URL:-http://localhost:8080}"
REPOS_DIR="${REPOS_DIR:-$HOME/git}"
TMPDIR_WORK=$(mktemp -d)

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
log_ok()   { echo -e "${GREEN}[ok]${NC} $1"; }
log_info() { echo -e "${CYAN}[->]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!!]${NC} $1"; }
log_err()  { echo -e "${RED}[xx]${NC} $1"; }

cleanup() { rm -rf "$TMPDIR_WORK"; }
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case $1 in
    --org)     ORG="$2";     shift 2 ;;
    --limit)   LIMIT="$2";   shift 2 ;;
    --service) SERVICE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

command -v gh   >/dev/null 2>&1 || { log_err "gh CLI nao encontrado."; exit 1; }
command -v jq   >/dev/null 2>&1 || { log_err "jq nao encontrado.";     exit 1; }
command -v curl >/dev/null 2>&1 || { log_err "curl nao encontrado.";   exit 1; }
gh auth status  >/dev/null 2>&1 || { log_err "Execute: gh auth login"; exit 1; }

if ! curl -sf "$SERVICE/health" >/dev/null 2>&1; then
  log_err "Knowledge service nao acessivel em $SERVICE — execute: make up"
  exit 1
fi

echo ""
echo -e "${CYAN}AI Engineer — Carga inicial do knowledge base${NC}"
echo -e "${CYAN}=============================================${NC}"
echo ""
log_info "Org:     $ORG"
log_info "Limite:  $LIMIT repos"
log_info "Service: $SERVICE"
[ -n "$GEMINI_API_KEY" ] && log_info "Gemini:  ativo (geracao de summaries)" || log_warn "Gemini:  inativo (defina GEMINI_API_KEY para summaries)"
echo ""

# ── ingest_chunk ──────────────────────────────────────────────────────────────

ingest_chunk() {
  local repo="$1"
  local section="$2"
  local content_file="$3"
  local lang="$4"
  local repo_type="$5"

  [ -f "$content_file" ] || return 0
  [ -s "$content_file" ] || return 0

  local content
  content=$(head -c 6000 "$content_file")
  printf '%s' "$content" > "$content_file"

  local payload
  payload=$(jq -n \
    --arg      repo      "$repo" \
    --arg      section   "$section" \
    --rawfile  content   "$content_file" \
    --arg      lang      "$lang" \
    --arg      repo_type "$repo_type" \
    '{repo:$repo, section:$section, content:$content, lang:$lang, repo_type:$repo_type}')

  curl -sf -X POST "$SERVICE/ingest" \
    -H "Content-Type: application/json" \
    -d "$payload" >/dev/null 2>&1 \
    || log_warn "Falha ao ingerir $repo::$section"
}

# ── generate_summary ──────────────────────────────────────────────────────────

generate_summary() {
  local name="$1"
  local repo_path="$2"
  local lang="$3"
  local repo_type="$4"
  local out_file="$5"

  # Prioridade 1: CLAUDE.md
  if [ -f "$repo_path/CLAUDE.md" ]; then
    cat "$repo_path/CLAUDE.md" > "$out_file"
    echo "claude-md"
    return
  fi

  # Prioridade 2: AI.md
  if [ -f "$repo_path/AI.md" ]; then
    cat "$repo_path/AI.md" > "$out_file"
    echo "ai-md"
    return
  fi

  # Prioridade 3: Gemini
  [ -z "$GEMINI_API_KEY" ] && echo "skip" && return

  local context=""

  for f in README.md readme.md Readme.md; do
    if [ -f "$repo_path/$f" ]; then
      context="${context}$(head -c 2000 "$repo_path/$f")\n\n"
      break
    fi
  done

  if [ -f "$repo_path/go.mod" ]; then
    context="${context}$(head -c 500 "$repo_path/go.mod")\n\n"
  fi

  if [ -f "$repo_path/package.json" ]; then
    context="${context}$(jq '{name,description,dependencies}' "$repo_path/package.json" 2>/dev/null | head -c 500)\n\n"
  fi

  local structure
  structure=$(find "$repo_path" -maxdepth 2 \
    -not -path "*/.git/*" -not -path "*/vendor/*" \
    -not -path "*/node_modules/*" \
    | sed "s|$repo_path/||" | sort | head -30 2>/dev/null || true)
  context="${context}Estrutura:\n${structure}\n\n"

  for main_file in main.go cmd/main.go src/main.go index.js index.ts app.py; do
    if [ -f "$repo_path/$main_file" ]; then
      context="${context}$(head -c 1000 "$repo_path/$main_file")\n\n"
      break
    fi
  done

  local prompt_file
  prompt_file=$(mktemp)
  printf "Analise o repositorio '%s' (linguagem: %s, tipo: %s) e gere um resumo tecnico em portugues.\n\nO resumo deve conter:\n- O que o servico faz\n- Como se encaixa na arquitetura\n- Topicos SQS/Kafka, endpoints ou recursos Terraform principais\n- Padroes tecnicos relevantes\n- Dependencias externas importantes\n\nSeja conciso. Maximo 400 palavras.\n\nCONTEXTO:\n%s" \
    "$name" "$lang" "$repo_type" "$context" > "$prompt_file"

  local payload
  payload=$(jq -n --rawfile prompt "$prompt_file" \
    '{contents:[{parts:[{text:$prompt}]}]}')
  rm -f "$prompt_file"

  local response
  response=$(curl -sf -X POST \
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null || true)

  [ -z "$response" ] && echo "skip" && return

  local summary
  summary=$(echo "$response" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null || true)

  [ -z "$summary" ] && echo "skip" && return

  printf '%s' "$summary" > "$out_file"
  echo "generated"
}

# ── process_repo ──────────────────────────────────────────────────────────────

process_repo() {
  local name="$1"
  local lang="$2"
  local repo_type="$3"
  local repo_path="$4"
  local tmp_content="$TMPDIR_WORK/content.txt"

  # Remove chunks antigos
  curl -sf -X DELETE "$SERVICE/repo/$name" >/dev/null 2>&1 || true

  # summary
  local summary_source
  summary_source=$(generate_summary "$name" "$repo_path" "$lang" "$repo_type" "$tmp_content")
  case "$summary_source" in
    claude-md) ingest_chunk "$name" "summary" "$tmp_content" "$lang" "$repo_type"
               log_info "$name — summary do CLAUDE.md" ;;
    ai-md)     ingest_chunk "$name" "summary" "$tmp_content" "$lang" "$repo_type"
               log_info "$name — summary do AI.md" ;;
    generated) ingest_chunk "$name" "summary" "$tmp_content" "$lang" "$repo_type"
               log_info "$name — summary gerado pelo Gemini" ;;
    skip)      : ;;
  esac

  # overview
  printf "Repositorio: %s\nLinguagem: %s\nTipo: %s" "$name" "$lang" "$repo_type" > "$tmp_content"
  ingest_chunk "$name" "overview" "$tmp_content" "$lang" "$repo_type"

  # readme
  for f in README.md readme.md Readme.md; do
    if [ -f "$repo_path/$f" ]; then
      head -c 4000 "$repo_path/$f" > "$tmp_content"
      ingest_chunk "$name" "readme" "$tmp_content" "$lang" "$repo_type"
      break
    fi
  done

  # structure
  { find "$repo_path" -maxdepth 3 \
      -not -path "*/.git/*" \
      -not -path "*/vendor/*" \
      -not -path "*/node_modules/*" \
      -not -path "*/.terraform/*" \
      | sed "s|$repo_path/||" | sort | head -60 > "$tmp_content"; } || true
  ingest_chunk "$name" "structure" "$tmp_content" "$lang" "$repo_type"

  # go.mod
  if [ -f "$repo_path/go.mod" ]; then
    head -c 5000 "$repo_path/go.mod" | tr -cd '[:print:]\n\t' > "$tmp_content"
    ingest_chunk "$name" "go-mod" "$tmp_content" "$lang" "$repo_type"
  fi

  # package.json
  if [ -f "$repo_path/package.json" ]; then
    jq '{name,version,dependencies,devDependencies}' \
      "$repo_path/package.json" 2>/dev/null \
      | head -c 5000 | tr -cd '[:print:]\n\t' > "$tmp_content"
    ingest_chunk "$name" "package-json" "$tmp_content" "$lang" "$repo_type"
  fi

  # env vars
  { grep -rh "os.Getenv\|viper.Get\|process.env\." \
      "$repo_path" --include="*.go" --include="*.js" --include="*.ts" 2>/dev/null \
      | grep -oE '"[A-Z_]+"' | sort -u | head -30 > "$tmp_content"; } || true
  ingest_chunk "$name" "env-vars" "$tmp_content" "$lang" "$repo_type"

  # endpoints
  { grep -rh "router\.\|http\.\|gin\.\|echo\.\|mux\." \
      "$repo_path" --include="*.go" 2>/dev/null \
      | grep -E "(GET|POST|PUT|DELETE|PATCH)" | head -20 > "$tmp_content"; } || true
  ingest_chunk "$name" "endpoints" "$tmp_content" "$lang" "$repo_type"

  # terraform
  if [ "$repo_type" = "infra" ]; then
    { grep -rh "^resource\|^module" \
        "$repo_path" --include="*.tf" 2>/dev/null \
        | sort -u | head -30 > "$tmp_content"; } || true
    ingest_chunk "$name" "terraform" "$tmp_content" "$lang" "$repo_type"
  fi

  log_ok "$name ($lang / $repo_type)"
}

# ── Listar repos ──────────────────────────────────────────────────────────────

log_info "Listando repositorios ativos..."

REPOS_JSON="$TMPDIR_WORK/repos.json"
gh repo list "$ORG" \
  --limit "$LIMIT" \
  --json name,primaryLanguage,isArchived \
  > "$REPOS_JSON"

TOTAL=$(jq '[.[] | select(.isArchived == false)] | length' "$REPOS_JSON")
log_info "Encontrados $TOTAL repositorios ativos."
echo ""

NAMES_FILE="$TMPDIR_WORK/names.txt"
jq -r '.[] | select(.isArchived == false) | [.name, (.primaryLanguage.name // "unknown")] | @tsv' \
  "$REPOS_JSON" > "$NAMES_FILE"

# ── Loop principal ────────────────────────────────────────────────────────────

count=0
while read -r line; do
  name=$(echo "$line" | cut -f1)
  lang=$(echo "$line" | cut -f2)

  [ -z "$name" ] && continue

  repo_type="service"
  echo "$name" | grep -q "\-infra$" && repo_type="infra"

  repo_path=$(find "$REPOS_DIR" -maxdepth 2 -type d -name "$name" 2>/dev/null | head -1)
  tmp_clone=""

  if [ -z "$repo_path" ]; then
    tmp_clone="$TMPDIR_WORK/clone_$count"
    mkdir -p "$tmp_clone"
    if ! gh repo clone "$ORG/$name" "$tmp_clone/$name" -- --depth=1 --quiet 2>/dev/null; then
      log_warn "$name — clone falhou, pulando."
      rm -rf "$tmp_clone"
      count=$((count + 1))
      continue
    fi
    repo_path="$tmp_clone/$name"
  fi

  process_repo "$name" "$lang" "$repo_type" "$repo_path"

  [ -n "$tmp_clone" ] && rm -rf "$tmp_clone"
  count=$((count + 1))

done < "$NAMES_FILE"

echo ""
log_ok "Carga inicial concluida. $count repositorios processados."
log_info "Verifique com: make repos"
log_info "Teste com:     make test-query"
echo ""