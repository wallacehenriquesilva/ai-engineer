# Referencia de Seguranca — JavaScript / TypeScript

Patterns especificos para auditoria de seguranca em projetos JS/TS (Node.js, React, Next.js).

---

## Injecao de SQL

```bash
# Concatenacao de SQL com template literals
grep -rn --include='*.ts' --include='*.js' -E '(query|execute|raw)\s*\(\s*[`"].*\$\{' .
grep -rn --include='*.ts' --include='*.js' -E '(query|execute)\s*\(.*\+\s*' .
```

**Correcao:** Usar parametros preparados (`query('SELECT * FROM users WHERE id = $1', [id])`). ORMs como Prisma e Sequelize ja parametrizam automaticamente.

---

## Cross-Site Scripting (XSS)

```bash
# innerHTML e dangerouslySetInnerHTML
grep -rn --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
  -E '(innerHTML|outerHTML|dangerouslySetInnerHTML|document\.write)\s*=' .
grep -rn --include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx' \
  -E 'v-html\s*=' .
```

**Correcao:** Usar `textContent` em vez de `innerHTML`. Em React, evitar `dangerouslySetInnerHTML` — se necessario, sanitizar com DOMPurify. Vue: evitar `v-html`.

---

## Injecao de Comandos

```bash
# child_process e exec
grep -rn --include='*.ts' --include='*.js' -E '(exec|execSync|spawn|spawnSync|execFile)\s*\(' .
grep -rn --include='*.ts' --include='*.js' -E 'child_process' .
grep -rn --include='*.ts' --include='*.js' -E 'eval\s*\(' .
```

**Correcao:** Evitar `exec()` com entrada do usuario. Usar `execFile()` ou `spawn()` com array de argumentos (sem shell). Nunca usar `eval()`.

---

## Path Traversal

```bash
# fs com entrada do usuario
grep -rn --include='*.ts' --include='*.js' -E 'fs\.(readFile|writeFile|readFileSync|createReadStream)\(.*req\.' .
grep -rn --include='*.ts' --include='*.js' -E 'path\.join\(.*req\.' .
```

**Correcao:** Usar `path.resolve()` e validar que o caminho resultante esta dentro do diretorio esperado.

---

## SSRF (Server-Side Request Forgery)

```bash
# fetch/axios com URL dinamica
grep -rn --include='*.ts' --include='*.js' -E '(fetch|axios\.(get|post|put|delete)|got|request)\(.*\+' .
grep -rn --include='*.ts' --include='*.js' -E '(fetch|axios\.(get|post|put|delete))\(.*\$\{' .
```

**Correcao:** Validar URL contra allowlist de dominios. Usar bibliotecas como `ssrf-req-filter` para bloquear IPs privados.

---

## Autenticacao e Autorizacao

```bash
# Comparacao de token insegura (timing attack)
grep -rn --include='*.ts' --include='*.js' -E '===?\s*.*token|token\s*===?' .
```

**Correcao:** Usar `crypto.timingSafeEqual()` para comparacao de tokens.

---

## Criptografia Insegura

```bash
# Math.random (inseguro)
grep -rn --include='*.ts' --include='*.js' -E 'Math\.random\(\)' .

# IVs e chaves hardcoded
grep -rn -E '(iv|IV|nonce|NONCE)\s*[:=]\s*(Buffer\.from|new\s+Uint8Array|["\x27])' --include='*.ts' --include='*.js' .
```

**Correcao:** Usar `crypto.randomBytes()` ou `crypto.randomUUID()` para geracao de valores aleatorios seguros. Para senhas, usar `bcrypt` via `bcryptjs`.

---

## Tratamento de Erros e Vazamento de Informacao

```bash
# Erro raw em response
grep -rn --include='*.ts' --include='*.js' -E 'res\.(json|send)\(.*err' .
grep -rn --include='*.ts' --include='*.js' -E 'res\.status\(500\).*message.*err' .
grep -rn --include='*.ts' --include='*.js' -E 'console\.(error|log)\(.*err.*stack' .
```

**Correcao:** Retornar mensagens de erro genericas ao cliente. Logar stack trace apenas internamente.

---

## Vulnerabilidades em Dependencias

```bash
# npm audit
if [ -f package-lock.json ]; then
  npm audit --json 2>/dev/null | head -100
fi
if [ -f yarn.lock ]; then
  yarn audit --json 2>/dev/null | head -100
fi
```

---

## OWASP Complementar

### Injection adicional

```bash
# NoSQL injection (MongoDB)
grep -rn -E '\$where|\$regex|\$ne|\$gt|\$lt' \
  --include='*.ts' --include='*.js' .
grep -rn -E '(find|findOne|aggregate|updateOne)\(.*\{.*\$' \
  --include='*.ts' --include='*.js' .
```

### Configuracao de Seguranca Incorreta

```bash
# TLS inseguro
grep -rn --include='*.ts' --include='*.js' -E 'rejectUnauthorized\s*:\s*false' .
grep -rn -E 'NODE_TLS_REJECT_UNAUTHORIZED.*0' .
```

### Desserializacao Insegura

```bash
grep -rn --include='*.ts' --include='*.js' -E '(serialize-javascript|node-serialize|unserialize)\(' .
```

### Logging e Monitoramento

```bash
# Verificar se ha tratamento de exception global
grep -rn --include='*.ts' --include='*.js' -E 'process\.on\(.uncaughtException' .
```
