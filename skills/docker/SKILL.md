---
name: docker
version: 1.0.0
description: >
  Cria, revisa e otimiza Dockerfiles e configurações de containers.
  Aplica boas práticas de segurança, performance, cache de camadas e builds multi-stage para Go, Node.js, Java e Python.
depends-on: []
triggers:
  - called-by: engineer
  - user-command: /docker
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# Docker — Criação e Revisão de Containers

**IMPORTANTE:** Antes de aplicar qualquer recomendacao desta skill, verifique se o `CLAUDE.md` do repositorio define convencoes especificas (libs internas, frameworks, padroes do time). As convencoes do repo TEM PRIORIDADE sobre as recomendacoes genericas desta skill. Exemplo: se esta skill recomenda uma lib padrao mas o repo usa uma lib interna, siga o padrao do repo.

Postura padrão: **toda imagem deve ser mínima, segura e reproduzível.**

Ao criar ou revisar um Dockerfile, siga todas as seções abaixo como checklist obrigatório.

---

## 1. Imagens Base

### Escolha da imagem base

| Tipo | Quando usar | Exemplo |
|---|---|---|
| `alpine` | Quando o runtime precisa de shell e utilitários mínimos | `node:22-alpine`, `python:3.12-alpine` |
| `distroless` | Quando não precisa de shell — máxima segurança | `gcr.io/distroless/static-debian12` |
| `scratch` | Binários estáticos compilados (Go, Rust) | `FROM scratch` |
| Imagem oficial slim | Quando Alpine causa incompatibilidades com glibc | `eclipse-temurin:21-jre-jammy` |

**Regras:**
- NUNCA use `:latest` — sempre fixe a versão com tag específica (ex: `node:22.14-alpine3.21`).
- Prefira imagens com menor superfície de ataque.
- Para Go com CGO desabilitado, use `scratch` ou `distroless/static`.

---

## 2. Builds Multi-Stage

Sempre separe o estágio de build do estágio de runtime. O objetivo é que a imagem final contenha **apenas o artefato necessário para execução**.

### Estrutura padrão

```dockerfile
# ---- Build Stage ----
FROM <imagem-com-toolchain> AS builder
WORKDIR /build
# copiar dependências primeiro (cache)
COPY go.mod go.sum ./
RUN go mod download
# copiar código-fonte
COPY . .
RUN CGO_ENABLED=0 go build -o /app ./cmd/server

# ---- Runtime Stage ----
FROM gcr.io/distroless/static-debian12
COPY --from=builder /app /app
ENTRYPOINT ["/app"]
```

**Regras:**
- O estágio de build pode ter ferramentas (compilador, make, npm, maven). O runtime NÃO.
- Use `COPY --from=builder` para copiar apenas artefatos finais.
- Nomeie os estágios com `AS builder`, `AS runtime` para clareza.

---

## 3. Estratégia de Cache de Camadas

A ordem das instruções no Dockerfile impacta diretamente o tempo de build. Camadas que mudam com menos frequência devem vir primeiro.

### Ordem recomendada

1. `FROM` — imagem base (muda raramente)
2. `RUN apt-get install` — dependências do sistema (muda raramente)
3. `COPY go.mod go.sum` / `COPY package.json package-lock.json` — manifesto de dependências
4. `RUN go mod download` / `RUN npm ci` — instalação de dependências
5. `COPY . .` — código-fonte (muda com frequência)
6. `RUN go build` / `RUN npm run build` — compilação

**Anti-padrão:** fazer `COPY . .` antes de instalar dependências invalida o cache a cada mudança de código.

---

## 4. .dockerignore

Todo projeto com Dockerfile DEVE ter um `.dockerignore`. Sem ele, o contexto de build inclui arquivos desnecessários (`.git`, `node_modules`, binários, testes).

### Exemplo mínimo

```
.git
.github
.gitignore
*.md
LICENSE
docker-compose*.yml
.env*
.vscode
.idea
node_modules
dist
bin
tmp
coverage
__pycache__
*.pyc
vendor
```

**Regras:**
- Nunca inclua `.env` ou arquivos de segredos no contexto de build.
- Exclua diretórios de dependências que serão reinstaladas dentro do container.

---

## 5. Segurança

### Usuário não-root

NUNCA execute o processo principal como root. Crie um usuário dedicado.

```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser
```

Para imagens distroless, o usuário `nonroot` já existe:

```dockerfile
FROM gcr.io/distroless/static-debian12
USER nonroot:nonroot
```

### Filesystem somente leitura

Quando possível, execute o container com filesystem read-only:

```yaml
# docker-compose.yml
services:
  app:
    read_only: true
    tmpfs:
      - /tmp
```

### Segredos

- NUNCA coloque segredos em `ENV`, `ARG`, ou `COPY`.
- Use Docker secrets, variáveis injetadas em runtime, ou mount de volumes.
- Se precisar de um segredo durante o build, use `--mount=type=secret`:

```dockerfile
RUN --mount=type=secret,id=github_token \
    GITHUB_TOKEN=$(cat /run/secrets/github_token) \
    go mod download
```

### Scanning de vulnerabilidades

Inclua scanning de imagem no CI:

```bash
# Trivy
trivy image --severity HIGH,CRITICAL minha-imagem:tag

# Docker Scout
docker scout cves minha-imagem:tag
```

---

## 6. Health Checks

Toda imagem de serviço deve declarar um `HEALTHCHECK` para que o orquestrador saiba se o processo está saudável.

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["/app", "healthcheck"]
```

Para serviços HTTP:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD ["wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/health"]
```

**Regras:**
- Use exec form (`CMD ["..."]`), não shell form.
- Ajuste `start-period` para o tempo que o serviço leva para inicializar.
- Em imagens distroless/scratch sem curl/wget, implemente o healthcheck no próprio binário.

---

## 7. Tratamento de Sinais (PID 1)

O processo principal do container roda como PID 1. Se não tratar sinais corretamente, `SIGTERM` não será encaminhado e o container será morto com `SIGKILL` após o timeout.

### Problema

- Shell form (`CMD app`) executa via `/bin/sh -c`, que não repassa sinais.
- Exec form (`CMD ["app"]`) executa diretamente, mas o processo precisa tratar sinais.

### Soluções

**1. Sempre use exec form no ENTRYPOINT/CMD:**

```dockerfile
# Correto
ENTRYPOINT ["/app"]

# Errado — shell form, PID 1 será o sh
ENTRYPOINT /app
```

**2. Use tini ou dumb-init quando o processo não trata sinais:**

```dockerfile
RUN apk add --no-cache tini
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app"]
```

Ou com dumb-init:

```dockerfile
RUN apt-get update && apt-get install -y dumb-init && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["dumb-init", "--"]
CMD ["/app"]
```

**3. Para Go:** o runtime já trata `SIGTERM` se o código usar `signal.NotifyContext` ou equivalente — exec form é suficiente.

---

## 8. Variáveis: ARG vs ENV

| Instrução | Disponível em | Persistida na imagem | Uso |
|---|---|---|---|
| `ARG` | Build-time apenas | Não | Versões, tokens temporários de build |
| `ENV` | Build-time e runtime | Sim | Configuração da aplicação |

**Regras:**
- Use `ARG` para valores que só existem durante o build (ex: `ARG GO_VERSION=1.24`).
- Use `ENV` para configuração que a aplicação lê em runtime.
- NUNCA passe segredos via `ARG` — eles ficam visíveis no histórico de camadas.

```dockerfile
ARG GO_VERSION=1.24
FROM golang:${GO_VERSION}-alpine AS builder

ENV APP_PORT=8080
ENV LOG_LEVEL=info
```

---

## 9. Combinação de Comandos RUN

Cada instrução `RUN` cria uma nova camada. Combine comandos relacionados para reduzir camadas e tamanho.

```dockerfile
# Errado — 3 camadas desnecessárias
RUN apt-get update
RUN apt-get install -y curl
RUN rm -rf /var/lib/apt/lists/*

# Correto — 1 camada, limpa cache
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*
```

**Regras:**
- Sempre limpe caches de pacotes na mesma camada da instalação.
- Use `--no-install-recommends` para evitar pacotes desnecessários.
- Não instale ferramentas de debug na imagem de produção (curl, vim, htop, etc.).

---

## 10. Logging

Containers devem escrever logs em **stdout** e **stderr**. Nunca escreva em arquivos de log dentro do container.

```dockerfile
# Para Nginx, redirecione logs para stdout/stderr
RUN ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log
```

O Docker captura stdout/stderr automaticamente e permite configurar log drivers (json-file, fluentd, awslogs, etc.) sem alterar a aplicação.

---

## 11. Docker Compose — Padrões

### Estrutura recomendada

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      target: runtime
    ports:
      - "8080:8080"
    environment:
      - LOG_LEVEL=info
      - DB_HOST=postgres
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 15s
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "1.0"
        reservations:
          memory: 256M
          cpus: "0.25"
    restart: unless-stopped
    read_only: true
    tmpfs:
      - /tmp

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: app
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 5s
      timeout: 3s
      retries: 5

volumes:
  pgdata:
```

### Regras de Compose

- Use `depends_on` com `condition: service_healthy` em vez de apenas `depends_on`.
- Defina `healthcheck` para cada serviço.
- Use volumes nomeados para dados persistentes — nunca bind mounts em produção.
- Defina limites de `memory` e `cpus` via `deploy.resources.limits`.
- Use `restart: unless-stopped` para serviços que devem reiniciar automaticamente.
- Separe redes quando há serviços que não devem se comunicar diretamente.

---

## 12. Limites de Recursos

Sempre defina limites de memória e CPU para evitar que um container consuma todos os recursos do host.

```yaml
deploy:
  resources:
    limits:
      memory: 512M
      cpus: "1.0"
    reservations:
      memory: 256M
      cpus: "0.25"
```

Em Kubernetes (contexto Conta Azul):

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "512Mi"
    cpu: "1000m"
```

---

## 13. Orquestração e Deploy

### Restart Policy

- `no` — não reinicia (testes, jobs).
- `on-failure` — reinicia apenas em falha.
- `unless-stopped` — reinicia sempre, exceto se parado manualmente.
- `always` — reinicia sempre (use com cautela).

### Graceful Shutdown

O container deve tratar `SIGTERM` e encerrar conexões abertas antes de parar:

1. O orquestrador envia `SIGTERM`.
2. A aplicação para de aceitar novas requisições.
3. Requisições em andamento são finalizadas (drain).
4. Conexões de banco e cache são fechadas.
5. O processo encerra com código 0.

Configure o `stop_grace_period` conforme o tempo necessário:

```yaml
services:
  app:
    stop_grace_period: 30s
```

### Zero-Downtime Deploy

- Use health checks para que o orquestrador saiba quando o novo container está pronto.
- Em Kubernetes, configure `readinessProbe` e `livenessProbe`.
- Use rolling update com `maxUnavailable: 0` e `maxSurge: 1`.

---

## 14. Anti-Padrões — Checklist de Revisão

Ao revisar um Dockerfile, verifique cada item abaixo:

| Anti-Padrão | Problema | Correção |
|---|---|---|
| Executar como root | Escalação de privilégios | Adicionar `USER nonroot` |
| Usar `:latest` | Build não reproduzível | Fixar tag com versão |
| Instalar curl/vim/htop na imagem final | Aumenta superfície de ataque | Remover ou limitar ao estágio de build |
| Não ter `.dockerignore` | Contexto de build enorme, possível vazamento | Criar `.dockerignore` |
| `COPY . .` antes de instalar dependências | Invalida cache a cada mudança de código | Copiar manifesto primeiro |
| Múltiplos `RUN` que deveriam ser combinados | Camadas desnecessárias | Combinar com `&&` |
| Segredos em `ENV` ou `ARG` | Ficam visíveis no histórico da imagem | Usar `--mount=type=secret` ou runtime |
| Shell form no ENTRYPOINT | Problema de PID 1, sinais não repassados | Usar exec form |
| Não definir HEALTHCHECK | Orquestrador não sabe se o serviço está saudável | Adicionar `HEALTHCHECK` |
| Imagem final com toolchain de build | Imagem grande e insegura | Usar multi-stage build |

---

## 15. Exemplos Completos por Linguagem

Consulte o exemplo da stack do projeto:

| Arquivo detectado | Stack | Referencia |
|---|---|---|
| `go.mod` | Go | [references/go.md](references/go.md) |
| `package.json` | Node.js | [references/nodejs.md](references/nodejs.md) |
| `pom.xml` ou `build.gradle` | Java (Spring Boot) | [references/java.md](references/java.md) |
| `requirements.txt` ou `pyproject.toml` | Python (FastAPI) | [references/python.md](references/python.md) |

### Auto-deteccao

Detecte a stack pelo repositorio antes de criar ou revisar um Dockerfile:

1. Verifique a raiz do projeto pelos arquivos indicadores acima.
2. Carregue o arquivo de referencia correspondente.
3. Adapte o exemplo ao contexto especifico do servico (portas, paths, comandos).

Se nenhum indicador for encontrado, pergunte ao usuario qual stack utilizar.

---

## 16. Fluxo de Execução da Skill

Quando invocada, siga esta ordem:

1. **Identificar o contexto:** Detectar linguagem do projeto, framework, e se já existe Dockerfile.
2. **Se criando Dockerfile:**
   - Aplicar multi-stage build adequado para a linguagem.
   - Criar `.dockerignore` se não existir.
   - Adicionar HEALTHCHECK, USER não-root, exec form.
   - Seguir a ordem de camadas para maximizar cache.
3. **Se revisando Dockerfile existente:**
   - Verificar cada item da tabela de anti-padrões (seção 14).
   - Sugerir correções específicas com exemplos de antes/depois.
   - Verificar se `.dockerignore` existe e está adequado.
4. **Se criando docker-compose:**
   - Aplicar padrões da seção 11 (healthcheck, limites, depends_on com condition).
   - Definir volumes nomeados, redes separadas quando aplicável.
5. **Validar o resultado:** Garantir que a imagem é mínima, segura e reproduzível.
