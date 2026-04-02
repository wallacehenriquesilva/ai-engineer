---
name: security
version: 2.0.0
description: >
  Validacao de seguranca abrangente para codigo antes da abertura de PRs. Cobre OWASP Top 10, deteccao de segredos, validacao de entrada, autenticacao, criptografia, dependencias vulneraveis, tratamento de erros e logging.
  Postura padrao: assume que o codigo é inseguro até prova em contrário.
depends-on: []
triggers:
  - called-by: engineer
  - user-command: /security
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# security: Validacao de Seguranca de Codigo

**IMPORTANTE:** Antes de aplicar qualquer recomendacao desta skill, verifique se o `CLAUDE.md` do repositorio define convencoes especificas (libs internas, frameworks, padroes do time). As convencoes do repo TEM PRIORIDADE sobre as recomendacoes genericas desta skill. Exemplo: se esta skill recomenda uma lib padrao mas o repo usa uma lib interna, siga o padrao do repo.

Skill de auditoria de seguranca para revisar codigo antes da abertura de PRs.
Postura padrao: **assume que o codigo e inseguro ate prova em contrario**.
Todo achado deve ser classificado, documentado e ter sugestao de correcao.

---

## Auto-deteccao de Linguagem

Antes de iniciar a analise, detecte a linguagem principal do projeto e carregue a referencia correspondente:

```bash
# Detectar linguagem principal
if [ -f go.mod ]; then
  echo "LANG=go"
elif [ -f pom.xml ] || [ -f build.gradle ]; then
  echo "LANG=java"
elif [ -f package.json ]; then
  echo "LANG=javascript"
elif [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f setup.py ]; then
  echo "LANG=python"
fi
```

Consulte a referencia da linguagem do projeto para patterns especificos:

- **Go:** [references/go.md](references/go.md)
- **JavaScript/TypeScript:** [references/javascript.md](references/javascript.md)
- **Java:** [references/java.md](references/java.md)
- **Python:** [references/python.md](references/python.md)

---

## Classificacao de Severidade

| Nivel      | Descricao                                                                 | Acao Requerida                        |
|------------|---------------------------------------------------------------------------|---------------------------------------|
| CRITICAL   | Exploravel remotamente sem autenticacao, impacto total no sistema         | **Bloqueia PR. Correcao obrigatoria** |
| HIGH       | Exploravel com alguma condicao, impacto significativo                     | **Bloqueia PR. Correcao obrigatoria** |
| MEDIUM     | Exploravel em cenarios especificos, impacto moderado                      | Correcao recomendada antes do merge   |
| LOW        | Impacto minimo ou risco teorico                                           | Documentar e corrigir quando possivel |

---

## Etapa 1 — Deteccao de Segredos e Credenciais

### Objetivo

Identificar chaves de API, senhas, tokens, chaves privadas e arquivos de configuracao sensivel que nunca devem ser commitados.

### Padroes para buscar

```bash
# Chaves de API genericas
grep -rn --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' \
  -E '(api[_-]?key|apikey|api[_-]?secret)\s*[:=]\s*["\x27][A-Za-z0-9+/=]{16,}' .

# Senhas hardcoded
grep -rn --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' \
  -E '(password|passwd|pwd|secret)\s*[:=]\s*["\x27][^"\x27]{4,}' .

# Tokens AWS
grep -rn -E '(AKIA[0-9A-Z]{16}|aws[_-]?(secret[_-]?access[_-]?key|access[_-]?key[_-]?id))\s*[:=]' .

# Chaves privadas
grep -rn -E 'BEGIN\s+(RSA|DSA|EC|OPENSSH|PGP)\s+PRIVATE\s+KEY' .

# Tokens JWT hardcoded
grep -rn -E 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' .

# Tokens do GitHub/GitLab
grep -rn -E '(ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|glpat-[A-Za-z0-9\-]{20,})' .

# Tokens Slack
grep -rn -E 'xox[bpors]-[A-Za-z0-9\-]{10,}' .

# Connection strings com credenciais
grep -rn -E '(postgres|mysql|mongodb|redis)://[^:]+:[^@]+@' .

# Tokens SendGrid, Twilio, Stripe
grep -rn -E '(SG\.[A-Za-z0-9_\-]{22,}\.[A-Za-z0-9_\-]{22,}|SK[a-f0-9]{32}|sk_(live|test)_[A-Za-z0-9]{20,})' .

# Arquivos .env commitados
find . -name '.env' -o -name '.env.local' -o -name '.env.production' | grep -v node_modules | grep -v .git
```

### Verificacao de .gitignore

```bash
# Verificar se .env esta no .gitignore
grep -q '\.env' .gitignore 2>/dev/null || echo "CRITICAL: .env nao esta no .gitignore"
```

**Severidade: CRITICAL** — Qualquer segredo encontrado no codigo bloqueia a PR imediatamente.

---

## Etapa 2 — Injecao de SQL

### Objetivo

Detectar construcao de queries SQL por concatenacao de strings, que permite SQL injection.

Consulte a referencia da linguagem do projeto para patterns especificos:
- [Go](references/go.md#injecao-de-sql) | [JavaScript](references/javascript.md#injecao-de-sql) | [Java](references/java.md#injecao-de-sql) | [Python](references/python.md#injecao-de-sql)

**Severidade: CRITICAL** — SQL injection permite acesso total ao banco de dados.

---

## Etapa 3 — Cross-Site Scripting (XSS)

### Objetivo

Detectar saida de dados do usuario sem sanitizacao em HTML/templates.

Consulte a referencia da linguagem do projeto para patterns especificos:
- [Go](references/go.md#cross-site-scripting-xss) | [JavaScript](references/javascript.md#cross-site-scripting-xss) | [Java](references/java.md#cross-site-scripting-xss) | [Python](references/python.md#cross-site-scripting-xss)

**Severidade: HIGH** — XSS permite roubo de sessao e dados do usuario.

---

## Etapa 4 — Injecao de Comandos (Command Injection)

### Objetivo

Detectar execucao de comandos do sistema operacional com entrada nao sanitizada.

Consulte a referencia da linguagem do projeto para patterns especificos:
- [Go](references/go.md#injecao-de-comandos) | [JavaScript](references/javascript.md#injecao-de-comandos) | [Java](references/java.md#injecao-de-comandos) | [Python](references/python.md#injecao-de-comandos)

**Severidade: CRITICAL** — Permite execucao remota de codigo no servidor.

---

## Etapa 5 — Path Traversal

### Objetivo

Detectar acesso a arquivos com caminhos controlados pelo usuario sem validacao.

Consulte a referencia da linguagem do projeto para patterns especificos:
- [Go](references/go.md#path-traversal) | [JavaScript](references/javascript.md#path-traversal) | [Java](references/java.md#path-traversal) | [Python](references/python.md#path-traversal)

**Severidade: HIGH** — Permite leitura/escrita de arquivos arbitrarios no servidor.

---

## Etapa 6 — Server-Side Request Forgery (SSRF)

### Objetivo

Detectar requisicoes HTTP onde a URL e controlada pelo usuario sem validacao.

Consulte a referencia da linguagem do projeto para patterns especificos:
- [Go](references/go.md#ssrf-server-side-request-forgery) | [JavaScript](references/javascript.md#ssrf-server-side-request-forgery) | [Java](references/java.md#ssrf-server-side-request-forgery) | [Python](references/python.md#ssrf-server-side-request-forgery)

**Severidade: HIGH** — Permite acesso a servicos internos e metadados da cloud (ex: 169.254.169.254).

---

## Etapa 7 — Autenticacao e Autorizacao

### Objetivo

Verificar se endpoints estao protegidos e se autorizacao esta implementada corretamente.

### Padroes genericos

```bash
# JWT sem verificacao de assinatura (qualquer linguagem)
grep -rn -E '(alg|algorithm)\s*[:=]\s*["\x27]none["\x27]' .
```

Consulte a referencia da linguagem do projeto para patterns especificos:
- [Go](references/go.md#autenticacao-e-autorizacao) | [JavaScript](references/javascript.md#autenticacao-e-autorizacao) | [Java](references/java.md#autenticacao-e-autorizacao) | [Python](references/python.md#autenticacao-e-autorizacao)

**Severidade: CRITICAL (endpoints sem auth), HIGH (timing attacks, JWT sem verificacao)**

---

## Etapa 8 — Criptografia Insegura

### Objetivo

Detectar uso de algoritmos fracos, IVs hardcoded, geracao de numeros aleatorios inseguros e hashing sem salt.

### Padroes genericos

```bash
# Algoritmos fracos — MD5, SHA1, DES, RC4, ECB (qualquer linguagem)
grep -rn -E '(MD5|md5|SHA1|sha1|DES|des|RC4|rc4|ECB|ecb)\b' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .

# Verificar uso correto: bcrypt, argon2, scrypt
grep -rn -E '(bcrypt|argon2|scrypt)' --include='*.go' --include='*.java' --include='*.py' --include='*.ts' --include='*.js' .
```

Consulte a referencia da linguagem do projeto para patterns especificos:
- [Go](references/go.md#criptografia-insegura) | [JavaScript](references/javascript.md#criptografia-insegura) | [Java](references/java.md#criptografia-insegura) | [Python](references/python.md#criptografia-insegura)

**Severidade: HIGH (algoritmos fracos para senhas), MEDIUM (random inseguro), CRITICAL (chaves/IVs hardcoded)**

---

## Etapa 9 — Vulnerabilidades em Dependencias

### Objetivo

Verificar dependencias com CVEs conhecidas usando ferramentas nativas de cada ecossistema.

Consulte a referencia da linguagem do projeto para comandos especificos:
- [Go](references/go.md#vulnerabilidades-em-dependencias) | [JavaScript](references/javascript.md#vulnerabilidades-em-dependencias) | [Java](references/java.md#vulnerabilidades-em-dependencias) | [Python](references/python.md#vulnerabilidades-em-dependencias)

### Verificacoes adicionais

```bash
# Verificar se existe Dependabot ou Renovate configurado
ls .github/dependabot.yml .github/renovate.json renovate.json 2>/dev/null
```

**Severidade: varia por CVE — CRITICAL para RCE, HIGH para data exposure, MEDIUM para DoS**

---

## Etapa 10 — Tratamento de Erros e Vazamento de Informacao

### Objetivo

Detectar exposicao de stack traces, mensagens de erro detalhadas e informacoes internas em respostas de API.

### Padroes genericos

```bash
# Debug mode habilitado em producao (qualquer linguagem)
grep -rn -E '(DEBUG\s*[:=]\s*[Tt]rue|debug\s*[:=]\s*true|NODE_ENV.*development)' \
  --include='*.py' --include='*.ts' --include='*.js' --include='*.go' --include='*.java' .
```

Consulte a referencia da linguagem do projeto para patterns especificos:
- [Go](references/go.md#tratamento-de-erros-e-vazamento-de-informacao) | [JavaScript](references/javascript.md#tratamento-de-erros-e-vazamento-de-informacao) | [Java](references/java.md#tratamento-de-erros-e-vazamento-de-informacao) | [Python](references/python.md#tratamento-de-erros-e-vazamento-de-informacao)

**Severidade: MEDIUM (vazamento de info), HIGH (stack traces com caminhos internos e versoes)**

---

## Etapa 11 — Logging de Dados Sensiveis

### Objetivo

Detectar log de PII (dados pessoais), senhas, tokens, numeros de cartao e dados sensiveis.

### Padroes para buscar

```bash
# Logging de senhas e tokens
grep -rn -E '(log|logger|logging|console)\.\w+\(.*password' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .
grep -rn -E '(log|logger|logging|console)\.\w+\(.*token' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .
grep -rn -E '(log|logger|logging|console)\.\w+\(.*secret' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .
grep -rn -E '(log|logger|logging|console)\.\w+\(.*authorization' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .

# Logging de PII — CPF, CNPJ, email, telefone
grep -rn -E '(log|logger|logging|console)\.\w+\(.*cpf' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .
grep -rn -E '(log|logger|logging|console)\.\w+\(.*cnpj' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .
grep -rn -E '(log|logger|logging|console)\.\w+\(.*email' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .
grep -rn -E '(log|logger|logging|console)\.\w+\(.*telefone|phone|celular' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .

# Logging de numeros de cartao de credito
grep -rn -E '(log|logger|logging|console)\.\w+\(.*card|cartao|credit' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .

# Logging de request/response completo (pode conter dados sensiveis)
grep -rn -E '(log|logger|logging|console)\.\w+\(.*request\.body|req\.body' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .
grep -rn -E '(log|logger|logging|console)\.\w+\(.*response\.body|res\.body' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .
```

**Severidade: HIGH (PII em logs, LGPD), MEDIUM (tokens em logs), CRITICAL (senhas em plaintext nos logs)**

---

## Etapa 12 — OWASP Top 10 Complementar

### A03:2021 — Injection (cobrindo casos nao listados acima)

```bash
# LDAP injection (generico)
grep -rn -E '(ldap|LDAP)\.(search|bind|modify)\(.*\+' \
  --include='*.go' --include='*.java' --include='*.py' .
```

Consulte a referencia da linguagem do projeto para patterns adicionais de injection:
- [JavaScript](references/javascript.md#owasp-complementar) | [Java](references/java.md#owasp-complementar) | [Python](references/python.md#owasp-complementar) | [Go](references/go.md#owasp-complementar)

**Severidade: CRITICAL (XXE, NoSQL injection), HIGH (LDAP injection)**

### A04:2021 — Design Inseguro

```bash
# Rate limiting ausente — verificar se ha middleware
grep -rn -E '(rate[_-]?limit|throttle|RateLimiter|limiter)' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .

# CORS permissivo (generico)
grep -rn -E '(Access-Control-Allow-Origin|AllowOrigins?|cors).*\*' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .
```

**Severidade: MEDIUM (rate limiting ausente), HIGH (CORS permissivo), MEDIUM (mass assignment)**

### A05:2021 — Configuracao de Seguranca Incorreta

```bash
# Headers de seguranca ausentes
grep -rn -E '(X-Content-Type-Options|X-Frame-Options|Strict-Transport-Security|Content-Security-Policy)' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .

# Versoes de TLS fracas
grep -rn -E '(TLSv1_0|TLSv1_1|SSLv3|TLS10|TLS11|MinVersion.*tls\.VersionTLS10)' \
  --include='*.go' --include='*.java' --include='*.py' .
```

Consulte a referencia da linguagem do projeto para patterns de TLS/SSL especificos.

**Severidade: CRITICAL (TLS skip verify em producao), HIGH (TLS fraco), MEDIUM (headers ausentes)**

### A08:2021 — Falhas de Integridade de Software e Dados

```bash
# Verificar integridade de downloads (generico)
grep -rn -E '(curl|wget)\s+' --include='Dockerfile' --include='*.sh' .
```

Consulte a referencia da linguagem do projeto para patterns de desserializacao insegura.

**Severidade: CRITICAL (desserializacao insegura), HIGH (downloads sem verificacao)**

### A09:2021 — Falhas de Logging e Monitoramento

```bash
# Verificar se eventos de autenticacao sao logados (generico)
grep -rn -E '(login|signin|signout|logout|authenticate|failed.*auth|invalid.*password)' \
  --include='*.go' --include='*.java' --include='*.ts' --include='*.js' --include='*.py' .
```

Consulte a referencia da linguagem do projeto para patterns de tratamento de exception global.

**Severidade: MEDIUM (logging insuficiente), LOW (monitoramento ausente)**

---

## Etapa 13 — Verificacao de Dockerfile e Infraestrutura

### Objetivo

Garantir que containers e configuracoes de infra seguem boas praticas.

```bash
# Container rodando como root
grep -rn --include='Dockerfile' -E '^USER\s' .
grep -rn --include='Dockerfile' -E 'USER\s+root' .

# Imagem base sem tag fixa (latest implicito)
grep -rn --include='Dockerfile' -E '^FROM\s+\w+\s*$' .
grep -rn --include='Dockerfile' -E '^FROM\s+.*:latest' .

# COPY de secrets para imagem
grep -rn --include='Dockerfile' -E 'COPY.*\.(env|pem|key|crt|p12|jks)' .

# Terraform — recursos publicos
grep -rn --include='*.tf' -E '(publicly_accessible|public_access|acl\s*=\s*"public)' .
grep -rn --include='*.tf' -E 'cidr_blocks\s*=\s*\["0\.0\.0\.0/0"\]' .
grep -rn --include='*.tf' -E 'ingress.*0\.0\.0\.0' .

# Kubernetes — privileged containers
grep -rn --include='*.yaml' --include='*.yml' -E '(privileged:\s*true|runAsRoot:\s*true|hostNetwork:\s*true)' .
grep -rn --include='*.yaml' --include='*.yml' -E 'allowPrivilegeEscalation:\s*true' .
```

**Severidade: HIGH (container root, imagem sem tag), CRITICAL (secrets em Dockerfile, recursos publicos na AWS)**

---

## Formato do Relatorio

Ao concluir a analise, gere um relatorio com o seguinte formato:

```markdown
# Relatorio de Seguranca

**Repositorio:** <nome>
**Branch:** <branch>
**Data:** <data>
**Status:** APROVADO | REPROVADO

## Resumo

| Severidade | Quantidade |
|------------|------------|
| CRITICAL   | X          |
| HIGH       | X          |
| MEDIUM     | X          |
| LOW        | X          |

## Achados

### [CRITICAL] <titulo>
- **Arquivo:** <caminho:linha>
- **Descricao:** <descricao detalhada>
- **Impacto:** <impacto no sistema>
- **Padrao OWASP:** <referencia>
- **Correcao:** <codigo ou instrucao de correcao>

### [HIGH] <titulo>
...

## Decisao

- Se houver **qualquer achado CRITICAL ou HIGH**: `REPROVADO` — PR nao deve ser aberta.
- Se houver apenas **MEDIUM ou LOW**: `APROVADO COM RESSALVAS` — PR pode ser aberta com issues de acompanhamento.
- Se nao houver achados: `APROVADO` — PR pode ser aberta.
```

---

## Regras de Execucao

1. **Escopo**: Analisar APENAS os arquivos alterados na branch atual em relacao a branch base. Usar `git diff --name-only <base>...HEAD` para obter a lista.
2. **Referencia de linguagem**: Detectar a linguagem principal do projeto e carregar a referencia correspondente em `references/`. Executar os patterns genericos (segredos, logging, infra) E os patterns especificos da linguagem.
3. **Falsos positivos**: Quando um padrao for encontrado, LER o codigo ao redor para confirmar se e uma vulnerabilidade real. Nao reportar testes unitarios como vulnerabilidades.
4. **Contexto**: Considerar se o codigo esta em producao ou em testes. Vulnerabilidades em testes sao `LOW`, em producao sao classificadas normalmente.
5. **Dependencias**: Se o projeto usa frameworks que ja mitigam certas vulnerabilidades (ex: GORM para SQL injection, React para XSS), ajustar a severidade de acordo.
6. **Bloqueio de PR**: Qualquer achado `CRITICAL` ou `HIGH` confirmado DEVE bloquear a abertura da PR. Retornar erro para a skill chamadora.
7. **Timeout**: A analise completa nao deve exceder 5 minutos. Se exceder, reportar os achados encontrados ate o momento.
8. **Idioma**: Todo o relatorio e comunicacao devem ser em PT-BR.
