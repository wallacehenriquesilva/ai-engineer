# Anti-Padroes de Performance — JavaScript / Node.js

Referencia especifica para projetos JavaScript e Node.js. Parte da skill `/performance`.

---

## Anti-Padroes Comuns

| Anti-padrao | Impacto | Solucao |
|---|---|---|
| Bloquear o event loop | Todo o servidor trava | Use `worker_threads` para CPU-bound |
| Memory leaks em closures | Consumo de memoria crescente | Evite capturar objetos grandes |
| Re-renders desnecessarios (React) | UI lenta, jank | `React.memo`, `useMemo`, `useCallback` |
| `await` sequencial desnecessario | Latencia cumulativa | Use `Promise.all` para chamadas independentes |
| Criar `new Date()` em loops | Alocacao excessiva | Cache o timestamp fora do loop |

---

## Event Loop Blocking

O event loop do Node.js e single-threaded. Qualquer operacao sincrona longa bloqueia TODAS as requisicoes.

### Operacoes que Bloqueiam

- Computacao pesada (parsing de JSON grande, criptografia, compressao)
- `fs.readFileSync` e outras operacoes sync de I/O
- Loops longos sobre grandes datasets
- Regex complexas (ReDoS — Regular Expression Denial of Service)
- `JSON.parse` / `JSON.stringify` em objetos muito grandes

### Como Detectar

```javascript
// Monitore o event loop lag
const start = process.hrtime.bigint();
setImmediate(() => {
  const lag = Number(process.hrtime.bigint() - start) / 1e6;
  if (lag > 100) console.warn(`Event loop lag: ${lag}ms`);
});
```

### Solucoes

```javascript
// Use worker_threads para operacoes CPU-bound
const { Worker, isMainThread, parentPort } = require('worker_threads');

if (isMainThread) {
  const worker = new Worker(__filename, { workerData: heavyData });
  worker.on('message', (result) => {
    // resultado do processamento pesado
  });
} else {
  const result = heavyComputation(workerData);
  parentPort.postMessage(result);
}
```

```javascript
// Quebre loops longos em chunks
async function processLargeArray(items, chunkSize = 1000) {
  for (let i = 0; i < items.length; i += chunkSize) {
    const chunk = items.slice(i, i + chunkSize);
    chunk.forEach(process);
    // Libere o event loop entre chunks
    await new Promise(resolve => setImmediate(resolve));
  }
}
```

---

## Memory Leaks em Closures

Closures em JavaScript capturam referencias ao escopo externo. Se a closure sobrevive ao escopo, os objetos capturados nao sao coletados pelo GC.

### Causas Comuns

```javascript
// RUIM: closure captura 'largeData' inteiro
function createHandler(largeData) {
  return function handler(req, res) {
    // usa apenas largeData.id, mas captura tudo
    res.json({ id: largeData.id });
  };
}

// BOM: capture apenas o necessario
function createHandler(largeData) {
  const id = largeData.id; // extrai apenas o que precisa
  return function handler(req, res) {
    res.json({ id });
  };
}
```

### Event Listeners nao Removidos

```javascript
// RUIM: listener acumula a cada chamada
function setup(emitter) {
  emitter.on('data', (data) => process(data));
  // Se setup() e chamado multiplas vezes, listeners acumulam
}

// BOM: remova listeners quando nao mais necessarios
function setup(emitter) {
  const handler = (data) => process(data);
  emitter.on('data', handler);
  return () => emitter.removeListener('data', handler);
}
```

### Timers nao Limpos

```javascript
// RUIM: setInterval sem clearInterval
function startPolling() {
  setInterval(() => fetchData(), 5000);
  // Se a funcao e chamada novamente, acumula intervals
}

// BOM: guarde a referencia e limpe
let pollInterval;
function startPolling() {
  if (pollInterval) clearInterval(pollInterval);
  pollInterval = setInterval(() => fetchData(), 5000);
}
```

---

## Profiling com clinic.js

[clinic.js](https://clinicjs.org/) e uma suite de ferramentas de profiling para Node.js.

### Ferramentas Disponveis

| Ferramenta | O que analisa | Quando usar |
|---|---|---|
| `clinic doctor` | Saude geral (CPU, event loop, memoria) | Primeiro diagnostico |
| `clinic flame` | Flamegraph de CPU | Identificar funcoes lentas |
| `clinic bubbleprof` | Async operations e delays | Problemas de I/O e concorrencia |

### Uso

```bash
# Instalar
npm install -g clinic

# Diagnostico geral
clinic doctor -- node server.js

# Flamegraph de CPU
clinic flame -- node server.js

# Analise de async
clinic bubbleprof -- node server.js
```

### Chrome DevTools

```bash
# Inicie o Node com inspector
node --inspect server.js

# Ou para pausar no inicio
node --inspect-brk server.js

# Acesse chrome://inspect no Chrome
# Use a aba "Performance" para gravar profiles
# Use a aba "Memory" para snapshots de heap
```

---

## Padroes de Async/Await

### Chamadas Paralelas

```javascript
// RUIM: sequencial desnecessario — soma das latencias
const user = await getUser(id);
const orders = await getOrders(id);
const notifications = await getNotifications(id);

// BOM: paralelo — latencia do mais lento
const [user, orders, notifications] = await Promise.all([
  getUser(id),
  getOrders(id),
  getNotifications(id),
]);
```

### Promise.allSettled para Tolerancia a Falhas

```javascript
// Se uma falha nao deve impedir as outras
const results = await Promise.allSettled([
  fetchA(),
  fetchB(),
  fetchC(),
]);

results.forEach((result) => {
  if (result.status === 'fulfilled') {
    process(result.value);
  } else {
    logError(result.reason);
  }
});
```

---

## Operacoes com Strings

```javascript
// RUIM: concatenacao em loops
let html = '';
for (const item of items) {
  html += `<li>${item.name}</li>`;
}

// BOM: array + join
const html = items.map(item => `<li>${item.name}</li>`).join('');
```

---

## React — Performance no Frontend

### Evitando Re-renders

```jsx
// Use React.memo para componentes puros
const Item = React.memo(({ name, onClick }) => {
  return <div onClick={onClick}>{name}</div>;
});

// Use useMemo para calculos caros
const sortedList = useMemo(() => {
  return items.sort((a, b) => a.name.localeCompare(b.name));
}, [items]);

// Use useCallback para funcoes passadas como props
const handleClick = useCallback((id) => {
  selectItem(id);
}, [selectItem]);
```

### Lazy Loading de Componentes

```jsx
const HeavyComponent = React.lazy(() => import('./HeavyComponent'));

function App() {
  return (
    <Suspense fallback={<Loading />}>
      <HeavyComponent />
    </Suspense>
  );
}
```

---

## Benchmarking em Node.js

```javascript
// Usando tinybench
import { Bench } from 'tinybench';

const bench = new Bench({ time: 1000 });

bench
  .add('JSON.parse', () => JSON.parse(jsonStr))
  .add('custom parser', () => customParse(jsonStr));

await bench.run();
console.table(bench.table());
```

### HTTP Load Testing com k6

```javascript
// k6 script
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 50,
  duration: '30s',
};

export default function () {
  const res = http.get('http://localhost:3000/api/data');
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.1);
}
```
