---
description: >
  Analisa o repositório atual e gera um CLAUDE.md com convenções, arquitetura,
  comandos e padrões detectados. Usado automaticamente pelo /engineer quando
  um repo não tem CLAUDE.md, ou manualmente para criar/atualizar.
  Uso: /init
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
---

# init: Gerar CLAUDE.md do Repositório

Analisa o repositório atual e gera um `CLAUDE.md` com tudo que o agente precisa para implementar código seguindo os padrões existentes.

---

## Etapa 1 — Verificar Estado Atual

```bash
test -f CLAUDE.md && echo "exists" || echo "missing"
```

Se já existir:
- Pergunte: **"CLAUDE.md já existe. Deseja sobrescrever? (s/N)"**
- Se não: encerre.
- Se sim: prossiga (backup do atual em `CLAUDE.md.bak`).

---

## Etapa 2 — Detectar Stack

Analise a raiz do repositório para identificar a stack:

```bash
ls -la go.mod package.json pom.xml build.gradle pyproject.toml requirements.txt \
  Cargo.toml mix.exs Gemfile composer.json 2>/dev/null
```

| Arquivo encontrado | Stack | Tipo |
|---|---|---|
| `go.mod` | Go | backend |
| `package.json` | Node.js / TypeScript | frontend ou backend |
| `pom.xml` ou `build.gradle` | Java | backend |
| `pyproject.toml` ou `requirements.txt` | Python | backend |
| `*.tf` na raiz ou subpastas | Terraform | infra |
| `Cargo.toml` | Rust | backend |
| `composer.json` | PHP | backend |

Para `package.json`, verifique se é frontend:
```bash
grep -q "next\|react\|vue\|angular\|svelte" package.json 2>/dev/null && echo "frontend" || echo "backend"
```

Se repo termina com `-infra`: tipo = infra.

---

## Etapa 3 — Analisar Estrutura

Mapeie a estrutura do projeto:

```bash
find . -maxdepth 3 -type f \
  -not -path "*/.git/*" \
  -not -path "*/vendor/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.terraform/*" \
  | head -80
```

Identifique:
- **Estrutura de pastas** — src/, internal/, cmd/, pages/, components/, etc.
- **Padrão arquitetural** — Clean Architecture, MVC, hexagonal, monorepo, etc.
- **Separação de camadas** — controllers, usecases, repositories, etc.

---

## Etapa 4 — Analisar Código Existente

### Entry point

Leia o arquivo principal para entender a inicialização:

```bash
# Go
cat main.go cmd/main.go cmd/*/main.go 2>/dev/null | head -100

# Node
cat index.js index.ts src/index.ts src/main.ts pages/_app.tsx app/layout.tsx 2>/dev/null | head -100

# Java
find . -name "Application.java" -o -name "*Application.java" 2>/dev/null | head -1 | xargs cat 2>/dev/null | head -100

# Python
cat main.py app.py src/main.py 2>/dev/null | head -100
```

### Dependências

```bash
# Go: módulos principais
cat go.mod 2>/dev/null | head -30

# Node: deps
cat package.json 2>/dev/null | jq '{name, dependencies, devDependencies}' 2>/dev/null

# Java: deps
cat pom.xml 2>/dev/null | head -50

# Python: deps
cat pyproject.toml requirements.txt 2>/dev/null | head -30
```

### Testes existentes

```bash
# Encontre arquivos de teste
find . -name "*_test.go" -o -name "*.test.ts" -o -name "*.test.tsx" \
  -o -name "*.test.js" -o -name "*Test.java" -o -name "test_*.py" \
  2>/dev/null | head -20
```

Leia 1-2 testes para entender o padrão (framework, estilo, mocks).

### Comandos disponíveis

```bash
# Makefile
cat Makefile 2>/dev/null | grep -E '^[a-zA-Z_-]+:' | head -20

# package.json scripts
cat package.json 2>/dev/null | jq '.scripts' 2>/dev/null

# Gradle tasks
cat build.gradle 2>/dev/null | grep -E 'task ' | head -10
```

### Variáveis de ambiente

```bash
grep -rh "os.Getenv\|viper.Get\|process.env\.\|os.environ" \
  --include="*.go" --include="*.js" --include="*.ts" --include="*.py" \
  . 2>/dev/null | grep -oE '"[A-Z_]+"' | sort -u | head -30
```

### CI/CD

```bash
ls .github/workflows/*.yml Jenkinsfile .gitlab-ci.yml .circleci/config.yml 2>/dev/null
```

---

## Etapa 5 — Gerar CLAUDE.md

Com base na análise, gere o `CLAUDE.md` seguindo este template:

```markdown
# <nome-do-repo>

## O que é

<1-2 frases descrevendo o propósito do serviço/app>

## Stack

- **Linguagem:** <Go 1.24 | TypeScript 5 | Java 21 | Python 3.12 | ...>
- **Framework:** <detectado do código — ex: Chi, Next.js 15, Spring Boot 3, FastAPI, ...>
- **Banco:** <PostgreSQL | DynamoDB | Redis | ...>
- **Mensageria:** <SNS/SQS | Kafka | ...>
- **Testes:** <testify+gomock | Jest+Testing Library | JUnit+Mockito | pytest | ...>

## Arquitetura

<Descreva a estrutura de pastas e o padrão arquitetural detectado>

```
<árvore de pastas principal, 2-3 níveis>
```

## Comandos

| Comando | O que faz |
|---|---|
| `<make run>` | Roda localmente |
| `<make test>` | Roda testes |
| `<make build>` | Compila |
| `<make lint>` | Linter |

## Convenções

### Nomenclatura

<Padrões de nome de arquivo, struct, componente, etc. detectados>

### Testes

<Framework, estilo (table-driven, describe/it, etc.), cobertura mínima se detectável>

### Commits

- `feat:` `fix:` `test:` `docs:` `refactor:` `chore:`

## Variáveis de ambiente

<Lista das env vars detectadas com descrição quando possível>

## Dependências externas

<APIs, serviços, filas que o repo consome ou publica>
```

### Regras para geração

- **Descreva o que encontrou, não invente.** Se não detectou cobertura mínima, não invente um número.
- **Use o código como fonte de verdade.** Nomes de arquivos, padrões de teste, estrutura — tudo vem da análise.
- **Seja conciso.** O CLAUDE.md é referência rápida, não documentação completa.
- **Inclua exemplos de código inline** apenas se o padrão não for óbvio pela estrutura.

---

## Etapa 6 — Salvar e Confirmar

```bash
# Backup se existia
[ -f CLAUDE.md ] && cp CLAUDE.md CLAUDE.md.bak

# Salva o novo
cat > CLAUDE.md << 'CONTENT'
<conteúdo gerado>
CONTENT
```

Confirme:

```
## CLAUDE.md gerado

- **Repo:** <nome>
- **Stack:** <linguagem + framework>
- **Arquitetura:** <padrão detectado>
- **Comandos:** <N> detectados
- **Env vars:** <N> detectadas
- **Testes:** <padrão detectado>

O arquivo foi salvo em `CLAUDE.md`.
Revise e ajuste conforme necessário.
```

---

## Regras Gerais

- Nunca invente informações — se não detectou, omita a seção.
- Se o repo estiver vazio ou sem código significativo, gere um CLAUDE.md mínimo com apenas nome e stack.
- O CLAUDE.md gerado é um ponto de partida — o time deve revisar e complementar.
- Esta skill não implementa código e não move tasks.
