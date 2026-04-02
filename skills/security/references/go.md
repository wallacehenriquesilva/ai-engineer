# Referencia de Seguranca — Go

Patterns especificos para auditoria de seguranca em projetos Go.

---

## Injecao de SQL

```bash
# Concatenacao de SQL com fmt.Sprintf
grep -rn --include='*.go' -E '(fmt\.Sprintf|"\s*\+)\s*.*\b(SELECT|INSERT|UPDATE|DELETE|FROM|WHERE|DROP|ALTER|CREATE|EXEC)\b' .
grep -rn --include='*.go' -E 'db\.(Query|Exec|QueryRow)\(.*fmt\.Sprintf' .
grep -rn --include='*.go' -E 'db\.(Query|Exec|QueryRow)\(.*\+\s*' .
```

**Correcao:** Usar parametros posicionais (`$1`, `$2`) com `db.Query(query, param1, param2)`. ORMs como GORM ja parametrizam automaticamente.

---

## Cross-Site Scripting (XSS)

```bash
# template sem escape
grep -rn --include='*.go' -E 'template\.HTML\(' .
grep -rn --include='*.go' -E 'fmt\.Fprintf\(w,' .
grep -rn --include='*.go' -E 'w\.Write\(\[\]byte\(' .
grep -rn --include='*.go' -E 'io\.WriteString\(w,' .
```

**Correcao:** Usar `html/template` (que escapa automaticamente) em vez de `text/template`. Evitar `template.HTML()` com dados do usuario.

---

## Injecao de Comandos

```bash
# exec.Command com variaveis
grep -rn --include='*.go' -E 'exec\.Command(Context)?\(' .
grep -rn --include='*.go' -E 'os\.StartProcess\(' .
```

**Correcao:** Evitar `exec.Command` com entrada do usuario. Se necessario, usar allowlist de comandos e validar argumentos.

---

## Path Traversal

```bash
# filepath com entrada do usuario
grep -rn --include='*.go' -E '(os\.Open|os\.ReadFile|os\.Create|ioutil\.ReadFile)\(' .
grep -rn --include='*.go' -E 'http\.ServeFile\(' .
grep -rn --include='*.go' -E 'filepath\.Join\(.*r\.(URL|Form|Query)' .
```

**Correcao:** Usar `filepath.Clean()` e validar que o caminho resultante esta dentro do diretorio esperado com `strings.HasPrefix()`.

---

## SSRF (Server-Side Request Forgery)

```bash
# HTTP client com URL dinamica
grep -rn --include='*.go' -E 'http\.(Get|Post|NewRequest)\(.*\+' .
grep -rn --include='*.go' -E 'http\.(Get|Post|NewRequest)\(.*fmt\.Sprintf' .
grep -rn --include='*.go' -E 'http\.(Get|Post|NewRequest)\(.*r\.(URL|Form|Query)' .
```

**Correcao:** Validar URL contra allowlist de dominios. Bloquear IPs privados (10.x, 172.16.x, 192.168.x, 169.254.x).

---

## Autenticacao e Autorizacao

```bash
# Endpoints sem middleware de autenticacao
grep -rn --include='*.go' -E '(HandleFunc|Handle|Get|Post|Put|Delete|Patch)\(' .
grep -rn --include='*.go' -E '(NoAuth|SkipAuth|Public|AllowAnonymous)' .

# Comparacao de token insegura (timing attack)
grep -rn --include='*.go' -E '==\s*.*token|token\s*==' .

# Verificar uso de constant-time comparison
grep -rn --include='*.go' -E 'hmac\.Equal|subtle\.ConstantTimeCompare' .

# JWT sem verificacao de assinatura
grep -rn --include='*.go' -E 'jwt\.Parse.*func.*\*jwt\.Token' .
```

**Correcao:** Usar `hmac.Equal()` ou `subtle.ConstantTimeCompare()` para comparacao de tokens. Sempre verificar assinatura JWT.

---

## Criptografia Insegura

```bash
# math/rand (inseguro) vs crypto/rand
grep -rn --include='*.go' -E '"math/rand"' .
grep -rn --include='*.go' -E 'rand\.(Intn|Int63|Float64|Read)\(' .

# IVs e chaves hardcoded
grep -rn -E '(iv|IV|nonce|NONCE)\s*[:=]\s*\[\]byte\{' --include='*.go' .

# Hashing de senhas sem salt ou com algoritmo fraco
grep -rn -E '(sha256\.Sum|sha512\.Sum|md5\.Sum).*password' --include='*.go' .
```

**Correcao:** Usar `crypto/rand` para geracao de numeros aleatorios seguros. Para senhas, usar `golang.org/x/crypto/bcrypt` ou `argon2`.

---

## Tratamento de Erros e Vazamento de Informacao

```bash
# Retornando erro interno diretamente ao cliente
grep -rn --include='*.go' -E 'http\.Error\(w,\s*err\.Error\(\)' .
grep -rn --include='*.go' -E 'json\..*Encode.*err\.Error\(\)' .
grep -rn --include='*.go' -E 'fmt\.Fprintf\(w,.*err' .
```

**Correcao:** Retornar mensagens de erro genericas ao cliente. Logar o erro detalhado internamente.

---

## Vulnerabilidades em Dependencias

```bash
# govulncheck (se disponivel)
if command -v govulncheck &>/dev/null; then
  govulncheck ./...
fi

# Verificar go.sum para modulos conhecidamente vulneraveis
grep -c 'golang.org/x/crypto v0\.0\.' go.sum 2>/dev/null
grep -c 'golang.org/x/net v0\.0\.' go.sum 2>/dev/null

# Dependencias desatualizadas
go list -m -u all 2>/dev/null | grep '\[' | head -20
```

---

## OWASP Complementar

### Injection adicional

```bash
# XML External Entity (XXE)
grep -rn --include='*.go' -E 'xml\.NewDecoder|xml\.Unmarshal' .
```

### Design Inseguro

```bash
# CORS permissivo
grep -rn -E 'AllowAllOrigins\s*[:=]\s*true' --include='*.go' .

# Mass assignment — binding de request direto em entidade
grep -rn --include='*.go' -E 'json\.NewDecoder.*Decode\(&' .
```

### Configuracao de Seguranca Incorreta

```bash
# TLS inseguro — skip verify
grep -rn --include='*.go' -E 'InsecureSkipVerify\s*:\s*true' .
```

### Logging e Monitoramento

```bash
# Verificar se ha tratamento de panic global
grep -rn --include='*.go' -E 'recover\(\)' .
```
