# Anti-Padroes de Performance — Go

Referencia especifica para projetos Go. Parte da skill `/performance`.

---

## Anti-Padroes Comuns

| Anti-padrao | Impacto | Solucao |
|---|---|---|
| Alocacoes desnecessarias em hot paths | Pressao no GC, latencia | Pre-aloque, use `sync.Pool` |
| `defer` dentro de loops | Acumula defers ate o fim da funcao | Extraia para funcao separada |
| Goroutines sem limite | OOM, sobrecarga do scheduler | Use semaforo ou worker pool |
| Conversao `[]byte` <-> `string` repetida | Copia a cada conversao | Trabalhe com `[]byte` diretamente |
| `fmt.Sprintf` em hot paths | Alocacao + reflection | Use `strconv` ou `strings.Builder` |
| `json.Marshal/Unmarshal` em hot paths | Reflection pesada | Use `jsoniter`, `sonic` ou code-gen |

---

## Goroutine Leaks

Goroutines que nunca terminam sao uma das causas mais comuns de memory leaks em Go.

### Causas Comuns

- Channel sem consumidor: goroutine bloqueada em `ch <- value` para sempre.
- Select sem `case <-ctx.Done()`: goroutine nao responde a cancelamento.
- Loop infinito sem condicao de saida.
- HTTP request sem timeout: goroutine presa esperando resposta.

### Como Detectar

```go
// Exponha o numero de goroutines ativas
runtime.NumGoroutine()

// Use pprof para inspecionar goroutines
import _ "net/http/pprof"
// Acesse: http://localhost:6060/debug/pprof/goroutine?debug=1
```

### Como Prevenir

```go
// SEMPRE use context com timeout/cancelamento
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()

// SEMPRE trate o caso de cancelamento em selects
select {
case result := <-ch:
    process(result)
case <-ctx.Done():
    return ctx.Err()
}
```

---

## sync.Pool

Use `sync.Pool` para objetos temporarios que sao frequentemente alocados e descartados.

### Quando Usar

- Buffers (`bytes.Buffer`) em hot paths.
- Structs temporarias usadas em serializacao/desserializacao.
- Objetos caros de alocar que podem ser reutilizados.

### Exemplo

```go
var bufPool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}

func process(data []byte) {
    buf := bufPool.Get().(*bytes.Buffer)
    buf.Reset()
    defer bufPool.Put(buf)
    // use buf...
}
```

### Cuidados

- `sync.Pool` pode ser limpo a qualquer momento pelo GC — nao dependa dele para persistencia.
- Sempre chame `Reset()` antes de reutilizar o objeto.
- Nao armazene objetos com referencias externas no pool.

---

## Profiling com pprof

### Habilitando em Servicos HTTP

```go
import _ "net/http/pprof"

// Em desenvolvimento, exponha o servidor de debug:
go func() {
    log.Println(http.ListenAndServe("localhost:6060", nil))
}()
```

### Tipos de Profile

| Profile | URL | O que mostra |
|---|---|---|
| CPU | `/debug/pprof/profile?seconds=30` | Onde o CPU esta sendo gasto |
| Heap | `/debug/pprof/heap` | Alocacoes de memoria ativas |
| Goroutine | `/debug/pprof/goroutine` | Stack traces de todas as goroutines |
| Block | `/debug/pprof/block` | Onde goroutines estao bloqueadas |
| Mutex | `/debug/pprof/mutex` | Contencao de mutex |

### Analisando via CLI

```bash
# CPU profile
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30

# Heap profile
go tool pprof http://localhost:6060/debug/pprof/heap

# Dentro do pprof:
# top10       — funcoes que mais consomem
# list func   — codigo anotado com custos
# web         — grafo visual (requer graphviz)
```

### Benchmarks com Profiling

```bash
go test -bench=BenchmarkX -benchmem -cpuprofile cpu.prof -memprofile mem.prof
go tool pprof cpu.prof
```

---

## defer em Loops

`defer` so executa quando a funcao retorna, nao quando o bloco do loop termina.

### Problema

```go
// RUIM: acumula N defers, recursos ficam abertos ate o fim da funcao
for _, file := range files {
    f, err := os.Open(file)
    if err != nil {
        return err
    }
    defer f.Close() // so fecha quando a funcao retorna!
    process(f)
}
```

### Solucao

```go
// BOM: extraia para funcao separada
for _, file := range files {
    if err := processFile(file); err != nil {
        return err
    }
}

func processFile(path string) error {
    f, err := os.Open(path)
    if err != nil {
        return err
    }
    defer f.Close() // fecha ao retornar desta funcao
    return process(f)
}
```

---

## Alocacoes Desnecessarias

### Pre-alocacao de Slices

```go
// RUIM: multiplas realocacoes conforme o slice cresce
var results []Result
for _, item := range items {
    results = append(results, transform(item))
}

// BOM: pre-aloca com capacidade conhecida
results := make([]Result, 0, len(items))
for _, item := range items {
    results = append(results, transform(item))
}
```

### Evitando Conversoes Repetidas

```go
// RUIM: cada conversao cria uma copia
for _, b := range data {
    s := string(b) // copia []byte para string
    process(s)
}

// BOM: trabalhe com []byte diretamente quando possivel
for _, b := range data {
    processBytes(b)
}
```

### Strings em Hot Paths

```go
// RUIM: alocacao + reflection
msg := fmt.Sprintf("user_%d", id)

// BOM: sem reflection, menos alocacoes
msg := "user_" + strconv.Itoa(id)

// MELHOR para muitas concatenacoes: strings.Builder
var b strings.Builder
b.Grow(estimatedSize)
b.WriteString("user_")
b.WriteString(strconv.Itoa(id))
msg := b.String()
```

---

## Benchmarking em Go

```bash
# Executar benchmarks com informacao de alocacoes
go test -bench=. -benchmem -count=5

# Comparar antes/depois com benchstat
go install golang.org/x/perf/cmd/benchstat@latest
go test -bench=. -benchmem -count=10 > old.txt
# (aplique mudancas)
go test -bench=. -benchmem -count=10 > new.txt
benchstat old.txt new.txt
```

### Exemplo de Benchmark

```go
func BenchmarkProcess(b *testing.B) {
    data := generateTestData()
    b.ResetTimer()
    for i := 0; i < b.N; i++ {
        process(data)
    }
}
```
