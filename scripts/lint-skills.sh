#!/bin/bash
# lint-skills.sh — Valida estrutura e qualidade das skills
#
# Uso:
#   ./scripts/lint-skills.sh                    # valida todas as skills
#   ./scripts/lint-skills.sh skills/engineer    # valida uma skill específica
#   ./scripts/lint-skills.sh --ci               # modo CI (exit 1 se houver erros)

set -eo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ERRORS=0
WARNINGS=0

error() { echo -e "  ${RED}ERROR${NC}  $1: $2"; ERRORS=$((ERRORS + 1)); }
warn()  { echo -e "  ${YELLOW}WARN${NC}   $1: $2"; WARNINGS=$((WARNINGS + 1)); }
ok()    { echo -e "  ${GREEN}OK${NC}     $1"; }

# ── Extrai campo do frontmatter YAML ────────────────────────────────────────

get_frontmatter_field() {
  local file="$1" field="$2"
  awk '/^---$/{n++; next} n==1' "$file" | grep "^${field}:" | head -1 | sed "s/^${field}:[[:space:]]*//"
}

has_frontmatter() {
  head -1 "$1" | grep -q "^---$"
}

# ── Valida uma skill ────────────────────────────────────────────────────────

lint_skill() {
  local skill_dir="$1"
  local skill_file="$skill_dir/SKILL.md"
  local name=$(basename "$skill_dir")

  if [ ! -f "$skill_file" ]; then
    error "$name" "SKILL.md não encontrado"
    return
  fi

  echo -e "\n${CYAN}Validando:${NC} $name"

  # Frontmatter existe?
  if ! has_frontmatter "$skill_file"; then
    error "$name" "Frontmatter YAML ausente (deve começar com ---)"
    return
  fi

  # Campos obrigatórios
  local fm_name=$(get_frontmatter_field "$skill_file" "name")
  local fm_desc=$(get_frontmatter_field "$skill_file" "description")
  local fm_tools=$(get_frontmatter_field "$skill_file" "allowed-tools")

  [ -z "$fm_name" ] && error "$name" "Campo 'name' ausente no frontmatter"
  [ -z "$fm_desc" ] && error "$name" "Campo 'description' ausente no frontmatter"

  # allowed-tools pode ser multi-line (lista YAML), verifica de forma diferente
  if ! awk '/^---$/{n++; next} n==1' "$skill_file" | grep -q "^allowed-tools:"; then
    error "$name" "Campo 'allowed-tools' ausente no frontmatter"
  fi

  # Campos opcionais recomendados
  if ! awk '/^---$/{n++; next} n==1' "$skill_file" | grep -q "^version:"; then
    warn "$name" "Campo 'version' ausente (recomendado)"
  fi

  # Conteúdo mínimo (corpo após frontmatter)
  local body_lines
  body_lines=$(awk '/^---$/{n++; next} n>=2' "$skill_file" | grep -c '[^ ]' 2>/dev/null || echo "0")
  if [ "$body_lines" -lt 10 ]; then
    error "$name" "Corpo muito curto ($body_lines linhas não-vazias, mínimo: 10)"
  fi

  # Seções recomendadas (pelo menos um heading)
  if ! grep -q "^## " "$skill_file"; then
    warn "$name" "Nenhuma seção (## heading) encontrada"
  fi

  # Nome no frontmatter deve bater com o diretório
  if [ -n "$fm_name" ] && [ "$fm_name" != "$name" ]; then
    warn "$name" "Nome no frontmatter ('$fm_name') difere do diretório ('$name')"
  fi

  # Verifica se há subdiretórios esperados (templates, examples)
  # Apenas avisa se existirem mas estiverem vazios
  for subdir in templates examples; do
    if [ -d "$skill_dir/$subdir" ]; then
      local count
      count=$(find "$skill_dir/$subdir" -type f | wc -l | tr -d ' ')
      [ "$count" -eq 0 ] && warn "$name" "Diretório '$subdir/' existe mas está vazio"
    fi
  done

  [ $ERRORS -eq 0 ] && ok "$name"
}

# ── Main ────────────────────────────────────────────────────────────────────

CI_MODE=false
TARGETS=()

for arg in "$@"; do
  case "$arg" in
    --ci) CI_MODE=true ;;
    *)    TARGETS+=("$arg") ;;
  esac
done

echo -e "${BOLD}${CYAN}AI Engineer — Lint de Skills${NC}"

# Se nenhum target, valida todas
if [ ${#TARGETS[@]} -eq 0 ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SKILLS_DIR="$(dirname "$SCRIPT_DIR")/skills"

  if [ ! -d "$SKILLS_DIR" ]; then
    # Tenta diretório instalado
    SKILLS_DIR="$HOME/.claude/skills"
  fi

  for skill_dir in "$SKILLS_DIR"/*/; do
    [ -d "$skill_dir" ] && TARGETS+=("$skill_dir")
  done
fi

for target in "${TARGETS[@]}"; do
  # Remove trailing slash
  target="${target%/}"
  lint_skill "$target"
done

# ── Resumo ──────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}Resultado:${NC} ${RED}$ERRORS erros${NC}, ${YELLOW}$WARNINGS avisos${NC}"

if [ "$CI_MODE" = true ] && [ $ERRORS -gt 0 ]; then
  exit 1
fi

[ $ERRORS -eq 0 ] && exit 0 || exit 1
