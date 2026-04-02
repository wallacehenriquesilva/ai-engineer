# Referencia de Seguranca — Java

Patterns especificos para auditoria de seguranca em projetos Java (Spring Boot, Java EE, WildFly).

---

## Injecao de SQL

```bash
# Concatenacao de SQL com Statement
grep -rn --include='*.java' -E '(Statement|PreparedStatement|createQuery|createNativeQuery).*\+\s*' .
grep -rn --include='*.java' -E '".*\b(SELECT|INSERT|UPDATE|DELETE)\b.*"\s*\+' .
grep -rn --include='*.java' -E 'String\.format\(.*\b(SELECT|INSERT|UPDATE|DELETE)\b' .
```

**Correcao:** Usar `PreparedStatement` com parametros (`?`). JPA/Hibernate: usar named parameters (`:param`). Nunca concatenar entrada do usuario em queries.

---

## Cross-Site Scripting (XSS)

```bash
# Saida direta em response
grep -rn --include='*.java' -E 'getWriter\(\)\.(print|write|println)\(' .
grep -rn --include='*.java' -E 'getOutputStream\(\)\.(print|write)\(' .
```

**Correcao:** Usar frameworks de template que escapam automaticamente (Thymeleaf, JSP com `<c:out>`). Em APIs REST, retornar JSON (Spring MVC ja escapa).

---

## Injecao de Comandos

```bash
# Runtime.exec e ProcessBuilder
grep -rn --include='*.java' -E 'Runtime\.getRuntime\(\)\.exec\(' .
grep -rn --include='*.java' -E 'ProcessBuilder\(' .
```

**Correcao:** Evitar `Runtime.exec()` com entrada do usuario. Se necessario, usar `ProcessBuilder` com lista de argumentos (sem shell) e validar contra allowlist.

---

## Path Traversal

```bash
# File com entrada do usuario
grep -rn --include='*.java' -E 'new\s+File\(.*request\.' .
grep -rn --include='*.java' -E 'Paths\.get\(.*request\.' .
grep -rn --include='*.java' -E 'FileInputStream\(.*request\.' .
```

**Correcao:** Usar `Path.normalize()` e validar que o caminho resultante esta dentro do diretorio esperado com `startsWith()`.

---

## SSRF (Server-Side Request Forgery)

```bash
# RestTemplate e HttpClient com URL dinamica
grep -rn --include='*.java' -E '(RestTemplate|HttpClient|WebClient|Feign).*\+\s*' .
grep -rn --include='*.java' -E 'new\s+URL\(.*request\.' .
```

**Correcao:** Validar URL contra allowlist de dominios. Bloquear IPs privados. Usar proxy HTTP com regras de acesso.

---

## Autenticacao e Autorizacao

```bash
# Spring Security desabilitado
grep -rn --include='*.java' -E '(permitAll|anonymous|@PermitAll|csrf\(\)\.disable)' .
grep -rn --include='*.java' -E 'antMatchers\(.*\)\.permitAll' .
grep -rn --include='*.java' -E '@PreAuthorize|@Secured|@RolesAllowed' .

# Comparacao de token insegura (timing attack)
grep -rn --include='*.java' -E '\.equals\(.*token' .

# Verificar uso de constant-time comparison
grep -rn --include='*.java' -E 'MessageDigest\.isEqual' .

# JWT sem verificacao de assinatura
grep -rn --include='*.java' -E 'setSigningKey\(null\)' .
```

**Correcao:** Usar `MessageDigest.isEqual()` para comparacao de tokens. Revisar `permitAll()` — garantir que apenas endpoints publicos estao listados. Nunca desabilitar CSRF sem motivo documentado.

---

## Criptografia Insegura

```bash
# Random (inseguro) vs SecureRandom
grep -rn --include='*.java' -E 'new\s+Random\(\)' .
grep -rn --include='*.java' -E 'java\.util\.Random' .

# IVs e chaves hardcoded
grep -rn -E '(iv|IV|nonce|NONCE)\s*[:=]\s*(new\s+byte|"|\x27|0x)' --include='*.java' .

# Hashing de senhas sem salt ou com algoritmo fraco
grep -rn --include='*.java' -E 'MessageDigest\.getInstance\(.*\).*password' .
```

**Correcao:** Usar `java.security.SecureRandom` para geracao de numeros aleatorios seguros. Para senhas, usar `BCryptPasswordEncoder` (Spring Security) ou `Argon2PasswordEncoder`.

---

## Tratamento de Erros e Vazamento de Informacao

```bash
# Stack trace em response
grep -rn --include='*.java' -E '(printStackTrace|getStackTrace|getMessage)\(\)' .
grep -rn --include='*.java' -E 'e\.getMessage\(\).*response' .
grep -rn --include='*.java' -E '@ExceptionHandler.*ResponseEntity.*Exception' .

# Debug mode habilitado
grep -rn --include='*.java' -E 'devtools\.restart\.enabled\s*=\s*true' .
```

**Correcao:** Usar `@ControllerAdvice` com `@ExceptionHandler` que retorna mensagens genericas. Nunca expor `getMessage()` ou stack trace em producao.

---

## Vulnerabilidades em Dependencias

```bash
# Verificar versoes conhecidamente vulneraveis
grep -rn --include='pom.xml' -E '<version>.*</version>' . | head -50
grep -rn --include='pom.xml' -E '(log4j|commons-collections|struts|spring-core)' .

# Verificar Log4Shell (CVE-2021-44228)
grep -rn --include='pom.xml' -E 'log4j.*2\.(0|1|2|3|4|5|6|7|8|9|10|11|12|13|14)\.' .
```

---

## OWASP Complementar

### Injection adicional

```bash
# XML External Entity (XXE)
grep -rn --include='*.java' -E '(SAXParser|DocumentBuilder|XMLReader|TransformerFactory)' .
grep -rn --include='*.java' -E 'setFeature.*FEATURE_SECURE_PROCESSING.*false' .
```

### Design Inseguro

```bash
# Mass assignment — binding de request direto em entidade
grep -rn --include='*.java' -E '@RequestBody\s+\w+Entity' .
```

### Configuracao de Seguranca Incorreta

```bash
# TLS inseguro
grep -rn --include='*.java' -E '(TrustAllCerts|ALLOW_ALL_HOSTNAME|SSLContext.*NONE)' .
```

### Desserializacao Insegura

```bash
grep -rn --include='*.java' -E '(ObjectInputStream|readObject|XMLDecoder|readUnshared)\(' .
```

**Correcao:** Evitar `ObjectInputStream` com dados nao confiaveis. Usar allowlist de classes com `ObjectInputFilter` (Java 9+). Preferir JSON para serializacao.

### Logging e Monitoramento

```bash
# Verificar se ha tratamento de exception global
grep -rn --include='*.java' -E '@ControllerAdvice|@ExceptionHandler' .
```
