# Referencia de Seguranca — Python

Patterns especificos para auditoria de seguranca em projetos Python (Django, FastAPI, Flask).

---

## Injecao de SQL

```bash
# Concatenacao de SQL com f-strings e format
grep -rn --include='*.py' -E '(execute|cursor\.execute)\s*\(\s*f["\x27]' .
grep -rn --include='*.py' -E '(execute|cursor\.execute)\s*\(.*%\s*' .
grep -rn --include='*.py' -E '(execute|cursor\.execute)\s*\(.*\.format\(' .
```

**Correcao:** Usar parametros preparados (`cursor.execute('SELECT * FROM users WHERE id = %s', (id,))`). ORMs como Django ORM e SQLAlchemy ja parametrizam automaticamente.

---

## Cross-Site Scripting (XSS)

```bash
# mark_safe e |safe
grep -rn --include='*.py' -E 'mark_safe\(' .
grep -rn --include='*.html' -E '\|\s*safe\b' .
```

**Correcao:** Evitar `mark_safe()` com dados do usuario. Em templates Django, o auto-escape ja esta habilitado — nao usar `|safe` com dados nao confiaveis.

---

## Injecao de Comandos

```bash
# subprocess e os.system
grep -rn --include='*.py' -E '(os\.system|os\.popen|subprocess\.(call|run|Popen|check_output))\s*\(' .
grep -rn --include='*.py' -E '(eval|exec)\s*\(' .
grep -rn --include='*.py' -E '__import__\s*\(' .
```

**Correcao:** Usar `subprocess.run()` com lista de argumentos e `shell=False` (padrao). Nunca usar `eval()` ou `exec()` com entrada do usuario. Evitar `os.system()`.

---

## Path Traversal

```bash
# open com entrada do usuario
grep -rn --include='*.py' -E 'open\(.*request\.' .
grep -rn --include='*.py' -E 'send_file\(.*request\.' .
```

**Correcao:** Usar `os.path.realpath()` e validar que o caminho resultante esta dentro do diretorio esperado com `startswith()`. Em Django, usar `FileResponse` com caminhos controlados.

---

## SSRF (Server-Side Request Forgery)

```bash
# requests com URL dinamica
grep -rn --include='*.py' -E 'requests\.(get|post|put|delete|head)\(.*\+' .
grep -rn --include='*.py' -E 'requests\.(get|post|put|delete|head)\(.*f["\x27]' .
grep -rn --include='*.py' -E 'urllib\.(request\.urlopen|parse\.urljoin)\(.*request\.' .
```

**Correcao:** Validar URL contra allowlist de dominios. Usar `ipaddress` para bloquear IPs privados antes de fazer a requisicao.

---

## Autenticacao e Autorizacao

```bash
# Comparacao de token insegura (timing attack)
grep -rn --include='*.py' -E '==\s*.*token|token\s*==' .

# Verificar uso de constant-time comparison
grep -rn --include='*.py' -E 'hmac\.compare_digest|secrets\.compare_digest' .
```

**Correcao:** Usar `hmac.compare_digest()` para comparacao de tokens. Em Django, usar `django.utils.crypto.constant_time_compare()`.

---

## Criptografia Insegura

```bash
# random (inseguro) vs secrets
grep -rn --include='*.py' -E 'import\s+random\b' .
grep -rn --include='*.py' -E 'random\.(randint|choice|random|randrange)\(' .

# Hashing de senhas sem salt ou com algoritmo fraco
grep -rn --include='*.py' -E 'hashlib\.(md5|sha1|sha256)\(.*password' .
```

**Correcao:** Usar o modulo `secrets` para geracao de valores aleatorios seguros (`secrets.token_hex()`, `secrets.token_urlsafe()`). Para senhas, usar `bcrypt`, `argon2-cffi`, ou `django.contrib.auth.hashers`.

---

## Tratamento de Erros e Vazamento de Informacao

```bash
# Traceback em response
grep -rn --include='*.py' -E 'traceback\.(format_exc|print_exc)\(\)' .
grep -rn --include='*.py' -E 'return.*str\(e\)|return.*repr\(e\)' .

# Debug mode habilitado em producao
grep -rn --include='*.py' -E 'DEBUG\s*=\s*True' .
```

**Correcao:** Nunca retornar `str(e)` ou `traceback.format_exc()` ao cliente. Usar middleware de erro que retorna mensagens genericas. Garantir `DEBUG = False` em producao.

---

## Vulnerabilidades em Dependencias

```bash
# pip-audit ou safety
if [ -f requirements.txt ]; then
  pip-audit -r requirements.txt 2>/dev/null || safety check -r requirements.txt 2>/dev/null
fi
```

---

## OWASP Complementar

### Injection adicional

```bash
# NoSQL injection (MongoDB)
grep -rn -E '\$where|\$regex|\$ne|\$gt|\$lt' --include='*.py' .
grep -rn -E '(find|findOne|aggregate|updateOne)\(.*\{.*\$' --include='*.py' .

# XML External Entity (XXE)
grep -rn --include='*.py' -E 'etree\.parse|minidom\.parse|sax\.parse' .

# LDAP injection
grep -rn -E '(ldap|LDAP)\.(search|bind|modify)\(.*\+' --include='*.py' .
```

### Configuracao de Seguranca Incorreta

```bash
# TLS inseguro — verify=False
grep -rn --include='*.py' -E 'verify\s*=\s*False' .
```

### Desserializacao Insegura

```bash
grep -rn --include='*.py' -E '(pickle\.loads?|yaml\.load\(|marshal\.loads?)' .
grep -rn --include='*.py' -E 'yaml\.load\(' .  # Deve ser yaml.safe_load
```

**Correcao:** Nunca usar `pickle` com dados nao confiaveis. Usar `yaml.safe_load()` em vez de `yaml.load()`. Preferir JSON para serializacao.

### Logging e Monitoramento

```bash
# Verificar se eventos de autenticacao sao logados
grep -rn -E '(login|signin|signout|logout|authenticate|failed.*auth|invalid.*password)' --include='*.py' .
```
