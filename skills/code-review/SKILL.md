---
name: code-review
version: 1.0.0
description: >
  Realiza revisao de codigo estruturada e rigorosa antes de abrir PRs ou ao revisar codigo de terceiros. Detecta problemas de corretude, seguranca, performance, legibilidade, manutenibilidade e cobertura de testes. Postura padrao: Reality Checker — assume que o codigo PRECISA de trabalho ate que se prove o contrario.
depends-on: []
triggers:
  - called-by: engineer
  - user-command: /code-review
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Code Review — Revisao Estruturada de Codigo

**IMPORTANTE:** Antes de aplicar qualquer recomendacao desta skill, verifique se o `CLAUDE.md` do repositorio define convencoes especificas (libs internas, frameworks, padroes do time). As convencoes do repo TEM PRIORIDADE sobre as recomendacoes genericas desta skill. Exemplo: se esta skill recomenda uma lib padrao mas o repo usa uma lib interna, siga o padrao do repo.

## Filosofia: Reality Checker

A postura padrao desta skill e de **ceticismo construtivo**. O codigo e considerado **culpado ate que se prove inocente**. Isso combate o problema de "aprovacoes fantasiosas" onde o revisor aprova sem realmente analisar.

Regras fundamentais:

1. **Nunca assuma que o codigo esta correto** — verifique cada caminho logico.
2. **Nunca assuma que testes existem** — confirme com grep/glob antes de afirmar.
3. **Nunca assuma que erros sao tratados** — rastreie cada retorno de erro.
4. **Se nao conseguir provar que funciona, reporte como problema.**
5. **Elogios devem ser raros e especificos** — nao elogie o que e apenas "adequado".

---

## Etapa 1 — Coletar Contexto

Antes de qualquer analise, colete o diff completo e o contexto do repositorio.

### 1.1 Obter o diff

```bash
# Se revisando uma PR
gh pr diff <PR_NUMBER> --repo <OWNER/REPO>

# Se revisando mudancas locais antes de abrir PR
git diff $(git merge-base HEAD origin/main)..HEAD
```

### 1.2 Identificar arquivos alterados

```bash
git diff --name-only $(git merge-base HEAD origin/main)..HEAD
```

### 1.3 Entender o escopo

- Quantos arquivos foram alterados?
- Quais pacotes/modulos foram tocados?
- A mudanca e localizada ou espalhada?
- Existe um padrao claro (feature nova, bugfix, refatoracao)?

---

## Etapa 2 — Checklist Estruturado de Revisao

Execute cada categoria do checklist abaixo. Para cada item, classifique como PASS, FAIL ou N/A.

### 2.1 Corretude

- [ ] A logica implementada corresponde ao requisito da task?
- [ ] Todos os caminhos condicionais (if/else/switch) estao cobertos?
- [ ] Loops possuem condicoes de saida corretas? Ha risco de loop infinito?
- [ ] Valores de borda (nil, zero, string vazia, lista vazia) sao tratados?
- [ ] Conversoes de tipo sao seguras? Ha risco de overflow ou truncamento?
- [ ] A ordem de operacoes esta correta? (ex: validar antes de persistir)
- [ ] Queries SQL retornam os dados esperados? Filtros estao corretos?
- [ ] Transacoes de banco sao commitadas/rollbackadas corretamente?

**Padrao de verificacao:**

```bash
# Buscar condicionais sem else ou default
grep -rn 'switch\|select {' --include="*.go" | head -20
grep -rn 'if.*{' --include="*.go" | grep -v 'else' | head -20

# Buscar conversoes de tipo potencialmente inseguras
grep -rn 'int(.*float\|float(.*int\|int32(.*int64' --include="*.go"
```

### 2.2 Seguranca

- [ ] Inputs do usuario sao validados e sanitizados?
- [ ] Queries SQL usam parametros preparados (sem concatenacao)?
- [ ] Segredos (tokens, senhas, chaves) nao estao hardcoded?
- [ ] Endpoints novos possuem autenticacao/autorizacao?
- [ ] Dados sensiveis nao sao logados (CPF, email, senha, tokens)?
- [ ] Headers de seguranca estao configurados (CORS, CSP)?
- [ ] Dependencias adicionadas possuem vulnerabilidades conhecidas?

**Padrao de verificacao:**

```bash
# Buscar SQL injection potencial
grep -rn 'fmt.Sprintf.*SELECT\|fmt.Sprintf.*INSERT\|fmt.Sprintf.*UPDATE\|fmt.Sprintf.*DELETE' --include="*.go"
grep -rn 'Sprintf.*WHERE' --include="*.go"

# Buscar segredos hardcoded
grep -rni 'password\|secret\|token\|api_key\|apikey' --include="*.go" | grep -v '_test.go' | grep -v 'func\|type\|struct\|interface'

# Buscar dados sensiveis em logs
grep -rn 'log\.\|logger\.\|zap\.\|slog\.' --include="*.go" | grep -i 'cpf\|email\|senha\|password\|token'
```

### 2.3 Performance

- [ ] Queries SQL possuem indices adequados? Ha queries N+1?
- [ ] Chamadas externas (HTTP, banco, cache) estao dentro de loops?
- [ ] Alocacoes excessivas de memoria (slices sem pre-alocacao, copia de structs grandes)?
- [ ] Existe cache onde deveria existir? O cache tem TTL e invalidacao?
- [ ] Timeouts estao configurados para chamadas externas?
- [ ] Paginacao esta implementada para listagens?
- [ ] Goroutines/threads sao finalizadas corretamente?

**Padrao de verificacao:**

```bash
# Buscar chamadas de banco dentro de loops
grep -rn 'for.*{' --include="*.go" -A 20 | grep -E 'db\.|repo\.|repository\.|\.Query|\.Exec|\.Find'

# Buscar chamadas HTTP sem timeout
grep -rn 'http.Get\|http.Post\|http.DefaultClient' --include="*.go"

# Buscar slices sem pre-alocacao em loops
grep -rn 'append(' --include="*.go" | grep -v 'make('
```

### 2.4 Legibilidade

- [ ] Nomes de variaveis, funcoes e arquivos sao auto-documentaveis?
- [ ] Funcoes tem uma unica responsabilidade clara?
- [ ] Comentarios explicam o "por que", nao o "o que"?
- [ ] A estrutura do codigo segue o padrao do repositorio?
- [ ] Nao ha codigo comentado que deveria ser removido?
- [ ] Constantes magicas sao nomeadas?
- [ ] A indentacao e formatacao estao consistentes?

**Padrao de verificacao:**

```bash
# Buscar numeros magicos
grep -rn '[^0-9][0-9][0-9][0-9][^0-9]' --include="*.go" | grep -v '_test.go' | grep -v 'const\|port\|status\|http\.\|time\.' | head -20

# Buscar codigo comentado
grep -rn '^\s*//.*func \|^\s*//.*if \|^\s*//.*for \|^\s*//.*return ' --include="*.go"

# Buscar variaveis com nomes curtos demais (1-2 caracteres, exceto i/j/k)
grep -rn '\b[a-hm-z][a-z]\?\b\s*:=' --include="*.go" | grep -v 'ok\|id\|db\|tx\|wg\|mu\|rw\|_' | head -20
```

### 2.5 Manutenibilidade

- [ ] O codigo segue os principios SOLID? (ver Etapa 4)
- [ ] Nao ha duplicacao de codigo? (ver Etapa 5 — DRY)
- [ ] Dependencias sao injetadas, nao criadas internamente?
- [ ] Interfaces sao usadas para desacoplar componentes?
- [ ] Configuracoes sao externalizadas (env vars, config files)?
- [ ] O codigo e testavel? (funcoes puras, sem efeitos colaterais ocultos)
- [ ] Ha separacao clara entre camadas (handler/service/repository)?

### 2.6 Testes

- [ ] Testes unitarios existem para a logica adicionada/alterada?
- [ ] Testes cobrem os caminhos felizes E os caminhos de erro?
- [ ] Mocks sao usados corretamente (nao mockam a implementacao real)?
- [ ] Testes sao deterministicos (sem dependencia de tempo, rede, ordem)?
- [ ] Edge cases estao cobertos (nil, vazio, maximo, concorrencia)?
- [ ] Testes de integracao existem para fluxos criticos?
- [ ] Os testes realmente passam?

**Padrao de verificacao:**

```bash
# Verificar se existem testes para os arquivos alterados
for f in $(git diff --name-only HEAD~1 | grep '\.go$' | grep -v '_test.go'); do
  test_file="${f%.go}_test.go"
  if [ ! -f "$test_file" ]; then
    echo "SEM TESTE: $f"
  fi
done

# Verificar cobertura de erro nos testes
grep -rn 'func Test' --include="*_test.go" | wc -l
grep -rn 'Error\|error\|Err\|err' --include="*_test.go" | grep 'assert\|require\|expect' | wc -l

# Executar testes
go test ./... -count=1 -race -timeout 60s
```

---

## Etapa 3 — Deteccao de Code Smells

Analise o codigo em busca dos seguintes code smells. Para cada smell encontrado, registre a localizacao e a severidade.

### 3.1 Metodos Longos

Funcoes com mais de 40 linhas sao suspeitas. Mais de 80 linhas e quase certamente um problema.

```bash
# Contar linhas por funcao em Go
grep -rn '^func ' --include="*.go" | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  linenum=$(echo "$line" | cut -d: -f2)
  echo "$file:$linenum"
done
```

### 3.2 God Class / God Package

Um arquivo ou pacote que faz tudo. Sinais: muitas dependencias importadas, muitos metodos publicos, nenhuma coesao entre os metodos.

```bash
# Contar imports por arquivo
for f in $(find . -name "*.go" -not -name "*_test.go"); do
  count=$(grep -c 'import' "$f" 2>/dev/null)
  if [ "$count" -gt 0 ]; then
    imports=$(awk '/import \(/,/\)/' "$f" | wc -l)
    if [ "$imports" -gt 15 ]; then
      echo "SUSPEITO ($imports imports): $f"
    fi
  fi
done
```

### 3.3 Feature Envy

Um metodo que usa mais dados de outra struct/pacote do que dos proprios. Indica que o metodo esta no lugar errado.

```bash
# Buscar funcoes que acessam muitos campos de outra struct
grep -rn '\.[A-Z][a-zA-Z]*\.[A-Z]' --include="*.go" | head -20
```

### 3.4 Obsessao por Primitivos

Usar string/int onde deveria existir um tipo de dominio (ex: `string` para CPF, `int` para status).

```bash
# Buscar funcoes com muitos parametros primitivos
grep -rn 'func.*string.*string.*string\|func.*int.*int.*int' --include="*.go" | head -20
```

### 3.5 Listas de Parametros Longas

Funcoes com mais de 4 parametros sao candidatas a refatoracao (agrupar em struct).

```bash
# Buscar funcoes com muitos parametros
grep -rn 'func.*,.*,.*,.*,' --include="*.go" | grep -v '_test.go' | head -20
```

### 3.6 Mudanca Divergente e Cirurgia de Espingarda

- **Mudanca Divergente:** um arquivo que muda por muitas razoes diferentes.
- **Cirurgia de Espingarda:** uma unica mudanca que exige alteracoes em muitos arquivos.

```bash
# Verificar quantos arquivos a mudanca toca
git diff --stat HEAD~1 | tail -1
```

---

## Etapa 4 — Violacoes de Principios SOLID

### 4.1 Single Responsibility Principle (SRP)

- O arquivo/struct tem uma unica razao para mudar?
- Se o nome do arquivo contem "and" ou "utils" ou "helpers", provavelmente viola SRP.

```bash
grep -rl 'utils\|helpers\|common\|misc' --include="*.go" | grep -v vendor | grep -v _test
```

### 4.2 Open/Closed Principle (OCP)

- O codigo pode ser estendido sem modificacao?
- Ha uso de interfaces e composicao em vez de condicionais crescentes?

```bash
# Buscar switch/case longos que poderiam ser polimorfismo
grep -rn 'case ' --include="*.go" -A 0 | cut -d: -f1 | sort | uniq -c | sort -rn | head -10
```

### 4.3 Liskov Substitution Principle (LSP)

- Implementacoes de interface sao verdadeiramente substituiveis?
- Ha verificacoes de tipo concreto onde deveria haver polimorfismo?

```bash
# Buscar type assertions que podem violar LSP
grep -rn '\.(type)\|\.(\*' --include="*.go" | grep -v '_test.go' | head -20
```

### 4.4 Interface Segregation Principle (ISP)

- Interfaces sao focadas? Mais de 5 metodos e suspeito.
- Consumidores usam todos os metodos da interface?

```bash
# Buscar interfaces com muitos metodos
awk '/type.*interface/,/\}/' $(find . -name "*.go" -not -name "*_test.go") 2>/dev/null | grep -c 'func\|^\}' | head -20
```

### 4.5 Dependency Inversion Principle (DIP)

- Modulos de alto nivel dependem de abstracoes (interfaces)?
- Ha imports de pacotes concretos onde deveria haver interfaces?

```bash
# Buscar instanciacoes diretas em vez de injecao
grep -rn 'new(\|:= &\|= &' --include="*.go" | grep -v '_test.go' | grep -v 'vendor' | head -20
```

---

## Etapa 5 — DRY vs Abstracao Prematura

### Regra dos Tres

- **1 ocorrencia:** Escreva o codigo.
- **2 ocorrencias:** Anote a duplicacao, mas nao abstraia ainda.
- **3+ ocorrencias:** Agora sim, considere abstrair.

### Sinais de abstracao prematura

- Funcao generica que so e chamada de um lugar.
- Interface com uma unica implementacao (e sem plano de extensao).
- Parametros booleanos que mudam o comportamento da funcao.
- "Framework interno" que ninguem pediu.

### Verificacao

```bash
# Buscar blocos de codigo duplicados (heuristica simples)
# Procura linhas identicas em arquivos diferentes
sort $(find . -name "*.go" -not -name "*_test.go" -not -path "*/vendor/*") | uniq -d | grep -v '^\s*$\|^\s*//\|^\s*}\|^\s*{' | head -30

# Buscar interfaces com uma unica implementacao
for iface in $(grep -rh 'type .* interface' --include="*.go" | awk '{print $2}'); do
  count=$(grep -rl "$iface" --include="*.go" | wc -l)
  if [ "$count" -le 2 ]; then
    echo "INTERFACE SOLITARIA: $iface (aparece em $count arquivos)"
  fi
done
```

---

## Etapa 6 — Revisao de Tratamento de Erros

### Checklist

- [ ] Todo `error` retornado e verificado? (`if err != nil`)
- [ ] Erros sao enriquecidos com contexto? (`fmt.Errorf("ao fazer X: %w", err)`)
- [ ] Erros nao sao silenciados? (sem `_ = funcaoQueRetornaErro()`)
- [ ] Erros de negocio sao distinguidos de erros de infraestrutura?
- [ ] Status HTTP corresponde ao tipo de erro? (400 vs 500)
- [ ] Panics sao usados apenas para bugs irrecuperaveis?
- [ ] Erros sao logados no nivel correto? (warn vs error)

### Verificacao

```bash
# Buscar erros ignorados
grep -rn '_ = \|_ :=' --include="*.go" | grep -v '_test.go' | grep -v 'vendor'

# Buscar erros sem contexto (return err puro)
grep -rn 'return err$\|return nil, err$' --include="*.go" | grep -v '_test.go' | head -20

# Buscar panic fora de init/main
grep -rn 'panic(' --include="*.go" | grep -v '_test.go' | grep -v 'func init\|func main' | head -10
```

---

## Etapa 7 — Revisao de Nomenclatura

### Principios

- Nomes devem revelar intencao sem necessidade de comentario.
- Nomes de funcoes devem ser verbos ou frases verbais (`GetUser`, `ValidateCPF`).
- Nomes de variaveis devem ser substantivos (`user`, `validationResult`).
- Evitar abreviacoes exceto as universais (`ctx`, `err`, `req`, `resp`, `cfg`).
- Nomes booleanos devem ser perguntas (`isValid`, `hasPermission`, `canRetry`).

### Verificacao

```bash
# Buscar nomes com abreviacoes nao padrao
grep -rn 'func [A-Z]' --include="*.go" | grep -v '_test.go' | awk -F'func ' '{print $2}' | cut -d'(' -f1 | grep -E '^[A-Z][a-z]{0,2}[A-Z]' | head -20

# Buscar variaveis booleanas sem prefixo is/has/can/should
grep -rn 'bool' --include="*.go" | grep -v '_test.go' | grep -v 'is\|has\|can\|should\|was\|will\|enable\|disable\|allow' | head -20
```

---

## Etapa 8 — Analise de Complexidade

### Limites recomendados

| Metrica | Aceitavel | Alerta | Critico |
|---|---|---|---|
| Complexidade ciclomatica | <= 10 | 11-20 | > 20 |
| Profundidade de aninhamento | <= 3 | 4 | > 4 |
| Linhas por funcao | <= 40 | 41-80 | > 80 |
| Parametros por funcao | <= 4 | 5-6 | > 6 |
| Imports por arquivo | <= 10 | 11-15 | > 15 |

### Verificacao

```bash
# Buscar aninhamento excessivo (heuristica: contar tabs/espacos)
awk '/^\t\t\t\t/ || /^                / {print FILENAME ":" NR ": " $0}' $(find . -name "*.go" -not -name "*_test.go" -not -path "*/vendor/*") | head -20

# Contar complexidade ciclomatica (heuristica: if + for + case + && + ||)
for f in $(find . -name "*.go" -not -name "*_test.go" -not -path "*/vendor/*"); do
  complexity=$(grep -c 'if \|for \|case \|&&\|||' "$f" 2>/dev/null)
  lines=$(wc -l < "$f")
  if [ "$complexity" -gt 20 ]; then
    echo "COMPLEXO ($complexity pontos de decisao, $lines linhas): $f"
  fi
done
```

---

## Etapa 9 — Compatibilidade Retroativa

### Checklist

- [ ] Campos removidos de structs publicas?
- [ ] Campos renomeados em structs com tags JSON/DB?
- [ ] Assinaturas de funcoes publicas alteradas?
- [ ] Variaveis de ambiente removidas ou renomeadas?
- [ ] Migracoes de banco sao reversiveis?
- [ ] Mensagens SNS/SQS mantêm o formato anterior?
- [ ] Endpoints removidos ou com path alterado?

### Verificacao

```bash
# Buscar campos removidos de structs JSON
git diff HEAD~1 --unified=0 | grep '^-.*json:"' | grep -v '^---'

# Buscar endpoints removidos
git diff HEAD~1 --unified=0 | grep '^-.*\.Get\|^-.*\.Post\|^-.*\.Put\|^-.*\.Delete\|^-.*\.Patch' | grep -v '^---'

# Buscar variaveis de ambiente removidas
git diff HEAD~1 --unified=0 | grep '^-.*os.Getenv\|^-.*viper\.' | grep -v '^---'
```

---

## Etapa 10 — Contratos de API

### Mudancas quebrantes (BLOQUEADOR)

- Remocao de campo obrigatorio da resposta
- Alteracao de tipo de campo existente
- Remocao de endpoint
- Alteracao de metodo HTTP
- Mudanca de path do endpoint
- Remocao de query parameter obrigatorio

### Mudancas nao quebrantes (OK)

- Adicao de campo opcional na resposta
- Adicao de endpoint novo
- Adicao de query parameter opcional
- Adicao de header opcional

### Verificacao

```bash
# Buscar mudancas em structs de request/response
git diff HEAD~1 -- '*.go' | grep -E '^\+.*type .*(Request|Response|Input|Output|Payload)' | head -20
git diff HEAD~1 -- '*.go' | grep -E '^-.*json:"' | head -20
```

---

## Etapa 11 — Problemas de Concorrencia

### Checklist

- [ ] Variaveis compartilhadas sao protegidas por mutex ou canais?
- [ ] Goroutines tem mecanismo de cancelamento (context)?
- [ ] WaitGroups sao usados corretamente? (Add antes do go, Done no defer)
- [ ] Canais sao fechados pelo produtor, nao pelo consumidor?
- [ ] Maps nao sao acessados concorrentemente sem sync.Map ou mutex?
- [ ] Ha risco de goroutine leak? (goroutine sem condicao de saida)
- [ ] defer mu.Unlock() e usado logo apos mu.Lock()?

### Verificacao

```bash
# Buscar maps sem protecao de concorrencia
grep -rn 'map\[' --include="*.go" | grep -v '_test.go' | grep -v 'sync.Map\|Mutex\|RWMutex' | head -20

# Buscar goroutines sem context
grep -rn 'go func\|go .*(' --include="*.go" | grep -v 'ctx\|context\|cancel' | grep -v '_test.go' | head -20

# Buscar potenciais race conditions (escrita sem lock)
grep -rn '\.Lock()\|\.RLock()' --include="*.go" | grep -v '_test.go' | head -20
```

---

## Etapa 12 — Gerar Relatorio de Revisao

### Formato de Comentarios

Cada finding deve seguir o formato:

```
[SEVERIDADE] CATEGORIA: Descricao do problema

Arquivo: path/to/file.go:42
Codigo:
  <trecho relevante>

Sugestao:
  <como corrigir>
```

### Classificacao de Severidade

| Nivel | Tag | Significado | Acao |
|---|---|---|---|
| 1 | `[BLOQUEADOR]` | Bug confirmado, vulnerabilidade de seguranca, quebra de contrato, perda de dados | PR nao pode ser aprovada |
| 2 | `[GRAVE]` | Bug potencial, problema de performance critico, erro silenciado, race condition | PR nao deveria ser aprovada |
| 3 | `[SUGESTAO]` | Melhoria de legibilidade, refatoracao, padrao melhor, teste adicional | Autor decide se aplica |
| 4 | `[NIT]` | Estilo, formatacao, nomenclatura menor, preferencia pessoal | Opcional, nao bloqueia |

### Tipos de Comentario

**BLOQUEADOR** — Requer correcao antes do merge:
```
[BLOQUEADOR] SEGURANCA: SQL injection via concatenacao de string

Arquivo: internal/repository/user.go:87
Codigo:
  query := fmt.Sprintf("SELECT * FROM users WHERE email = '%s'", email)

Sugestao:
  Use prepared statements:
  query := "SELECT * FROM users WHERE email = $1"
  row := db.QueryRow(query, email)
```

**SUGESTAO** — Melhoria recomendada:
```
[SUGESTAO] LEGIBILIDADE: Funcao ProcessOrder faz validacao, persistencia e notificacao

Arquivo: internal/service/order.go:23
Sugestao:
  Extraia em 3 funcoes: ValidateOrder, PersistOrder, NotifyOrderCreated
  Cada uma com responsabilidade unica.
```

**NIT** — Observacao menor:
```
[NIT] NOMENCLATURA: Variavel 'd' nao e auto-documentavel

Arquivo: internal/handler/report.go:15
Codigo:
  d := time.Now().Sub(startTime)

Sugestao:
  elapsed := time.Since(startTime)
```

---

## Etapa 13 — Decisao Final

Apos completar todas as etapas, emita um veredito:

### APROVADO

Somente se:
- Zero findings BLOQUEADOR
- Zero findings GRAVE
- Testes existem e passam
- Codigo e compreensivel sem explicacao do autor

### APROVADO COM RESSALVAS

Se:
- Zero findings BLOQUEADOR
- Ate 2 findings GRAVE que o autor reconhece
- Sugestoes registradas para melhoria futura

### REPROVADO

Se:
- Qualquer finding BLOQUEADOR
- 3+ findings GRAVE
- Testes nao existem ou nao passam
- Mudanca quebrante nao documentada

### Formato do veredito

```
## Resultado da Revisao

**Veredito:** [APROVADO | APROVADO COM RESSALVAS | REPROVADO]

### Resumo
- Arquivos analisados: X
- Findings BLOQUEADOR: X
- Findings GRAVE: X
- Findings SUGESTAO: X
- Findings NIT: X

### Findings
<lista de findings ordenada por severidade>

### Pontos Positivos
<maximo 3 pontos que merecem destaque genuino>
```

---

## Notas de Integracao

### Chamado pelo engineer

Quando chamado pelo skill `engineer`, esta skill executa a revisao sobre o proprio codigo gerado ANTES de abrir a PR. Se o veredito for REPROVADO, o engineer deve corrigir os findings BLOQUEADOR e GRAVE antes de prosseguir.

### Chamado pelo usuario

Quando chamado diretamente via `/code-review`, aceita como argumento:
- URL de PR: `/code-review https://github.com/org/repo/pull/123`
- Path local: `/code-review ./path/to/files`
- Sem argumento: revisa o diff atual contra a branch base
