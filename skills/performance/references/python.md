# Anti-Padroes de Performance — Python

Referencia especifica para projetos Python (FastAPI, Django, scripts). Parte da skill `/performance`.

---

## Anti-Padroes Comuns

| Anti-padrao | Impacto | Solucao |
|---|---|---|
| GIL em operacoes CPU-bound | Sem paralelismo real | Use `multiprocessing` ou C extensions |
| Listas grandes quando generator basta | Consumo de memoria | Use generator expressions |
| Copias desnecessarias de listas/dicts | Memoria + CPU | Use views, iteradores, `copy()` apenas quando necessario |
| `import` dentro de funcoes chamadas frequentemente | Overhead de lookup | Importe no topo do modulo |
| f-strings com expressoes complexas | Avaliacao repetida | Pre-compute e armazene |

---

## GIL (Global Interpreter Lock)

O GIL do CPython impede que multiplas threads executem bytecode Python simultaneamente. Isso significa que threads nao oferecem paralelismo real para operacoes CPU-bound.

### Quando o GIL e Problema

- Processamento de dados pesado (parsing, transformacao, calculos)
- Criptografia e compressao em Python puro
- Loops computacionais intensivos

### Quando o GIL NAO e Problema

- Operacoes de I/O (HTTP, banco de dados, arquivo) — o GIL e liberado durante I/O
- Chamadas a bibliotecas C (NumPy, Pandas) — o GIL e liberado durante execucao C
- `asyncio` para I/O concorrente — nao depende de threads

### Solucoes para CPU-bound

```python
# Use multiprocessing para paralelismo real
from multiprocessing import Pool

def heavy_computation(data):
    # processamento pesado
    return result

with Pool(processes=4) as pool:
    results = pool.map(heavy_computation, data_chunks)
```

```python
# concurrent.futures para interface mais simples
from concurrent.futures import ProcessPoolExecutor

with ProcessPoolExecutor(max_workers=4) as executor:
    futures = [executor.submit(heavy_computation, chunk) for chunk in chunks]
    results = [f.result() for f in futures]
```

```python
# Para I/O-bound, use asyncio
import asyncio
import aiohttp

async def fetch_all(urls):
    async with aiohttp.ClientSession() as session:
        tasks = [session.get(url) for url in urls]
        return await asyncio.gather(*tasks)
```

---

## Generators vs Listas

Generators produzem valores sob demanda, sem carregar tudo na memoria.

### Quando Usar Generators

```python
# RUIM: cria lista inteira na memoria
def get_all_records(db):
    return [transform(row) for row in db.fetch_all()]  # N objetos na memoria

# BOM: gera um por vez
def get_all_records(db):
    for row in db.fetch_all():
        yield transform(row)  # 1 objeto por vez na memoria
```

### Generator Expressions

```python
# RUIM: lista intermediaria desnecessaria
total = sum([x * x for x in range(1_000_000)])  # cria lista de 1M itens

# BOM: generator expression — sem lista intermediaria
total = sum(x * x for x in range(1_000_000))  # calcula sob demanda
```

### itertools para Composicao

```python
import itertools

# Em vez de criar listas intermediarias grandes
# Use itertools para compor transformacoes lazy
filtered = itertools.filterfalse(lambda x: x.deleted, records)
mapped = map(transform, filtered)
batched = itertools.batched(mapped, 100)  # Python 3.12+
```

---

## Profiling com py-spy

[py-spy](https://github.com/benfred/py-spy) e um sampling profiler que nao requer modificacao no codigo e tem overhead minimo.

### Uso

```bash
# Instalar
pip install py-spy

# Profile um processo em execucao (por PID)
py-spy top --pid 12345

# Gravar flamegraph
py-spy record -o profile.svg --pid 12345

# Profile um script diretamente
py-spy record -o profile.svg -- python app.py
```

### cProfile para Analise Detalhada

```python
import cProfile
import pstats

# Profile uma funcao
cProfile.run('main()', 'output.prof')

# Analisar resultados
stats = pstats.Stats('output.prof')
stats.sort_stats('cumulative')
stats.print_stats(20)  # top 20 funcoes
```

### memory_profiler para Memoria

```python
# pip install memory_profiler
from memory_profiler import profile

@profile
def memory_hungry_function():
    big_list = [i for i in range(1_000_000)]
    del big_list
    return "done"
```

```bash
# Ou via CLI
python -m memory_profiler script.py
```

### line_profiler para Tempo por Linha

```python
# pip install line_profiler
# Decore a funcao com @profile e execute com kernprof

@profile
def slow_function():
    a = [i for i in range(10000)]
    b = sorted(a, reverse=True)
    return sum(b)
```

```bash
kernprof -l -v script.py
```

---

## Copias Desnecessarias

### Problema

```python
# RUIM: copia desnecessaria
def process(items):
    items_copy = list(items)  # copia inteira — necessario?
    for item in items_copy:
        transform(item)

# BOM: itere diretamente se nao precisa modificar a lista
def process(items):
    for item in items:
        transform(item)
```

### Quando Copiar e Necessario

```python
# Copie quando for modificar durante iteracao
for item in list(items):  # copia necessaria: remove durante iteracao
    if item.expired:
        items.remove(item)

# Ou melhor: crie nova lista
items = [item for item in items if not item.expired]
```

### Dict Views em vez de Copias

```python
# RUIM: cria lista de chaves
for key in list(my_dict.keys()):  # copia desnecessaria
    process(key)

# BOM: view e lazy
for key in my_dict:  # itera diretamente
    process(key)

# Para verificar intersecao de chaves
common = dict_a.keys() & dict_b.keys()  # views suportam operacoes de set
```

---

## Import em Funcoes

```python
# RUIM: import dentro de funcao chamada frequentemente
def process_request(data):
    import json  # lookup a cada chamada
    return json.loads(data)

# BOM: import no topo do modulo
import json

def process_request(data):
    return json.loads(data)
```

Excecao: imports condicionais para dependencias opcionais sao aceitaveis, desde que a funcao nao seja chamada em hot paths.

---

## Serializacao Rapida

```python
# stdlib json e lento
import json
data = json.dumps(obj)

# orjson e ~10x mais rapido
import orjson
data = orjson.dumps(obj)  # retorna bytes, nao str

# msgspec para validacao + serializacao
import msgspec

class User(msgspec.Struct):
    name: str
    age: int

encoder = msgspec.json.Encoder()
data = encoder.encode(User(name="test", age=30))
```

---

## Benchmarking em Python

```python
# timeit para microbenchmarks
import timeit

result = timeit.timeit(
    'sum(range(1000))',
    number=10000
)
print(f"{result:.4f}s para 10000 iteracoes")
```

```python
# pytest-benchmark para testes integrados
def test_performance(benchmark):
    result = benchmark(my_function, arg1, arg2)
    assert result is not None
```

```bash
# Executar benchmarks com pytest
pytest --benchmark-only --benchmark-sort=mean
```
