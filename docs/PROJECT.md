# AI Engineer

> Desenvolvedor autônomo para times de engenharia. Pega tasks do Jira, implementa código, roda testes, abre PRs e resolve comentários de revisão — tudo sem intervenção humana.

---

## O que é o AI Engineer?

O AI Engineer é um agente autônomo construído sobre o [Claude Code](https://claude.ai/code) que funciona como um desenvolvedor do seu time. Ele:

1. **Busca a próxima task** no Jira (sprint ativa, label configurável)
2. **Avalia se a task está clara** o suficiente para implementar (scoring 0-18)
3. **Analisa o repositório**, entende padrões e convenções
4. **Implementa o código** seguindo os padrões do time
5. **Roda testes** e corrige falhas automaticamente
6. **Abre Pull Request** com descrição, labels e link para a task
7. **Aguarda CI/CD** e corrige falhas (até 2 tentativas)
8. **Atualiza o Jira** movendo a task e comentando o resultado

Tudo isso sem nenhuma intervenção humana.

---

## Por que usar?

### Problemas que resolve


| Antes                                         | Depois                                                   |
| --------------------------------------------- | -------------------------------------------------------- |
| Tasks acumulam na sprint sem ninguém pegar    | Agente busca automaticamente a próxima task disponível   |
| Implementações fora do padrão do time         | Aprende os padrões do repo via `CLAUDE.md` e skills      |
| PRs rejeitadas por falta de testes            | Roda testes e corrige falhas antes de abrir a PR         |
| Deploy sem confirmação pode causar incidentes | Merge só acontece com PR aprovada + homolog validada     |
| Mesmo erro acontece em várias execuções       | Registra aprendizados e consulta antes de implementar    |
| Cada máquina aprende isolada                  | Knowledge-service centralizado compartilha entre agentes |


### Para quem é?

- **Times de backend** que querem acelerar a entrega de tasks repetitivas
- **Tech leads** que querem garantir padrão mesmo com demanda alta
- **Empresas** que querem escalar capacidade de engenharia sem escalar headcount
- **Desenvolvedores** que querem delegar tarefas bem definidas e focar no que importa

---

## Como funciona?

### Visão geral do fluxo

```
 Jira            Implementar        Testar           Entregar
┌──────────┐    ┌──────────────┐   ┌──────────────┐  ┌──────────────┐
│ Busca    │    │ Analisa repo │   │ Roda testes  │  │ Abre PR      │
│ task     ├───>│ Planeja      ├──>│ Corrige      ├─>│ Aciona CI    │
│ Avalia   │    │ Implementa   │   │ falhas       │  │ Move task    │
│ clareza  │    │              │   │              │  │              │
└──────────┘    └──────────────┘   └──────────────┘  └──────────────┘
      │                │                                    │
      │ Clareza < 15?  │ Budget > limite?                   │ CI falhou?
      │ Comenta Jira   │ Interrompe                         │ Corrige (2x)
      ▼                ▼                                    ▼
   [ENCERRA]        [ENCERRA]                         [ENCERRA se 2x]
```

### Etapas detalhadas

**1. Seleção de task**
O agente conecta no Jira via MCP, busca tasks na sprint ativa com a label configurada (ex: `AI`), filtra por status "To Do" e sem bloqueios.

**2. Avaliação de clareza**
Cada task recebe uma nota de 0 a 18 em 6 dimensões (objetivo, contexto, critérios de aceite, dados, dependências, restrições). Se a nota for menor que o threshold configurado (padrão: 15), o agente comenta no Jira pedindo clarificações e encerra.

**3. Identificação do repositório**
O agente identifica qual(is) repositório(s) precisa modificar. Se não encontrar localmente, clona automaticamente. Se a task envolver 2+ repos, lança agentes paralelos.

**4. Análise e planejamento**
Examina o código, entende a arquitetura, identifica componentes reutilizáveis e cria um plano de implementação salvo em `.claude/plans/`.

**5. Implementação**
Segue o plano, reutiliza ao máximo o código existente, implementa o mínimo necessário. Respeita padrões de tratamento de erros, logging, validação.

**6. Testes**
Executa a suite de testes do repositório. Se algum teste falhar, corrige e re-executa.

**7. Pull Request**
Cria commits atômicos e semânticos, abre PR com descrição padronizada, adiciona label `ai-generated`, aciona CI/CD conforme configurado.

**8. Validação e entrega**
Aguarda CI passar, corrige falhas (máx 2 tentativas), atualiza o Jira com link da PR, custo da sessão e tokens utilizados.

---

## Flowchart completo do `/run`

O `/run` orquestra 3 skills em sequência: `engineer → pr-resolve → finalize`. Cada skill tem múltiplas etapas internas com validações e pontos de saída.

```
/run
 │
 ▼
╔══════════════════════════════════════════════════════════════════════════╗
║  FASE 1 — /engineer                                                      ║
║                                                                          ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 0: Pré-cond.  │ gh auth? jq? .mcp.json?                         ║
║  │          + Config   │ CLAUDE.md → extrai variáveis                    ║
║  └──────────┬──────────┘                                                 ║
║             │ falhou? ──────────────────────────────────── ▶ [ENCERRA]   ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 0.2: Circuit  │ >= 3 falhas consecutivas?                       ║
║  │  Breaker            │                                                 ║
║  └──────────┬──────────┘                                                 ║
║             │ ativo? (sem --force) ─────────────────────── ▶ [ENCERRA]   ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 1: Buscar     │ /jira-integration                               ║
║  │  Task               │ Sprint ativa + label AI + status To Do          ║
║  └──────────┬──────────┘                                                 ║
║             │ nenhuma task? ────────────────────────────── ▶ [ENCERRA]   ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 2: Avaliar    │ /jira-task-clarity                              ║
║  │  Clareza            │ Score 0-18 em 6 dimensões                       ║
║  └──────────┬──────────┘                                                 ║
║             │                                                            ║
║             ├── score >= threshold ──────────────── ▶ Etapa 3            ║
║             │                                                            ║
║             └── score < threshold                                        ║
║                  │                                                       ║
║                  ├── sem comentário anterior ─ ▶ comenta no Jira         ║
║                  │                               [ENCERRA]               ║
║                  ├── com comentário, sem       ─ ▶ [ENCERRA silencioso]  ║
║                  │   resposta                                            ║
║                  └── com resposta nova         ─ ▶ reavalia              ║
║                       │                                                  ║
║                       ├── agora >= threshold ── ▶ Etapa 3                ║
║                       └── ainda < threshold ─── ▶ comenta follow-up      ║
║                                                   [ENCERRA]              ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 3: Definir    │ Mover task → "Fazendo"                          ║
║  │  Alvo               │ Subtasks: filtra por AI label                   ║
║  └──────────┬──────────┘                                                 ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 4: Localizar  │ find repo ou gh clone                           ║
║  │  Repos              │                                                 ║
║  └──────────┬──────────┘                                                 ║
║             │                                                            ║
║             ├── 1 repo ────────────────────────── ▶ Etapa 5              ║
║             └── 2+ repos ─────────────────── ▶ /engineer-multi           ║
║             │                                     (fluxo paralelo)       ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 5: Setup      │ CLAUDE.md do repo (ou /init)                    ║
║  │  Worktree           │ /worktree create                                ║
║  └──────────┬──────────┘                                                 ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 6: DORA       │ git commit --allow-empty                        ║
║  │  + Exec Log         │ exec_log_start                                  ║
║  └──────────┬──────────┘                                                 ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 6.2: Buscar   │ /execution-feedback                             ║
║  │  Aprendizados       │ knowledge-service → avisos para o plano         ║
║  └──────────┬──────────┘                                                 ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 7: Planejar   │ Examina repo, cria plano em                     ║
║  │                     │ .claude/plans/plan-<TASK-ID>.md                 ║
║  └──────────┬──────────┘                                                 ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 8: Implement. │ Segue o plano                                   ║
║  │          + Budget   │ Verifica custo após implementar                 ║
║  └──────────┬──────────┘                                                 ║
║             │ budget > limite? ─────────────────────────── ▶ [ENCERRA]   ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 9: Testar     │ Roda testes, corrige falhas                     ║
║  │          + Budget   │ Verifica custo após testes                      ║
║  └──────────┬──────────┘                                                 ║
║             │ budget > limite? ─────────────────────────── ▶ [ENCERRA]   ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 9.1: Auto-    │ Default: NEEDS WORK                             ║
║  │  Review (Reality    │ Valida: acceptance criteria, testes,            ║
║  │  Check)             │ código morto, padrões, regressões               ║
║  └──────────┬──────────┘                                                 ║
║             │ bloqueante falhou (2x)? ─────────────────── ▶ [ENCERRA]    ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 10: Commits   │ /git-workflow Seção 2                           ║
║  │                     │ Commits atômicos + Co-Authored-By               ║
║  └──────────┬──────────┘                                                 ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 11: PR        │ /git-workflow Seção 3                           ║
║  │                     │ Título: <TASK-ID> | <desc>                      ║
║  │                     │ Template + label AI                             ║
║  └──────────┬──────────┘                                                 ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 12: CI        │ Trigger conforme CLAUDE.md                      ║
║  │                     │ Valida SonarQube/checks                         ║
║  │                     │ Máx $CI_MAX_RETRIES tentativas                  ║
║  └──────────┬──────────┘                                                 ║
║             │ falhou após retries? ────────────────────── ▶ [ENCERRA]    ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 12.3: Slack   │ Se Slack Auto Review = true:                    ║
║  │  (opcional)         │ /slack-review request <PR-URL>                  ║
║  │                     │ 📨 Envia pedido de review no canal              ║
║  └──────────┬──────────┘                                                 ║
║             ▼                                                            ║
║  ┌─────────────────────┐                                                 ║
║  │ Etapa 13: Jira      │ Move task → "Em Revisão"                        ║
║  │                     │ Comenta com PR-URL + custo                      ║
║  └──────────┬──────────┘                                                 ║
║             ▼                                                            ║
║  │ Etapa 14: Output    │ TASK_ID, PR_URL, BRANCH, REPO                   ║
║                                                                          ║
╚═══════════════════════════════════════════════════════════════╤══════════╝
                                                                │
          exec_handoff_save("engineer" → "pr-resolve")          │
                                                                ▼
╔════════════════════════════════════════════════════════════════════════╗
║  FASE 2 — /pr-resolve <PR-URL>                                         ║
║                                                                        ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 0: Config     │ CLAUDE.md → GITHUB_ORG, SONAR_BOT,            ║
║  │                     │ CI_MAX_RETRIES                                ║
║  └──────────┬──────────┘                                               ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 1: Contexto   │ gh pr view → state, reviews, comments         ║
║  │  da PR              │ gh pr diff → arquivos alterados               ║
║  └──────────┬──────────┘                                               ║
║             │ merged/closed? ──────────────────────────── ▶ [ENCERRA]  ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 2: Worktree   │ Localiza repo + checkout da branch            ║
║  └──────────┬──────────┘                                               ║
║             ▼                                                          ║
║  ┌─────────────────────────────────────────────────────┐               ║
║  │ Etapa 3: Polling (60s, timeout 24h)                 │               ║
║  │                                                     │               ║
║  │  ┌──────────────────┐                               │               ║
║  │  │ Verifica reviews │                               │               ║
║  │  │ + comentários    │                               │               ║
║  │  └────────┬─────────┘                               │               ║
║  │           │                                         │               ║
║  │           ├── APPROVED ──────────────────── ▶ Etapa 7               ║
║  │           ├── HAS_FEEDBACK ──────────────── ▶ Etapa 4               ║
║  │           └── nada ──── aguarda 60s ── ▶ (loop)     │               ║
║  │                                                     │               ║
║  │  timeout 24h? ──────────────────────────── ▶ [ENCERRA]              ║
║  └─────────────────────────────────────────────────────┘               ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 4: Analisar   │ 4.1: Coleta IDs dos comentários               ║
║  │  Comentários        │ 4.2: Busca threads via GraphQL                ║
║  │                     │ 4.3: Classifica cada comentário               ║
║  │                     │   → código | dúvida | ambíguo | sugestão      ║
║  └──────────┬──────────┘                                               ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 5: Agir       │ CRITICAL: reply DIRETO no comentário          ║
║  │                     │                                               ║
║  │  código  → implementa + commit + reply + resolve thread             ║
║  │  dúvida  → reply direto (NÃO resolve)                               ║
║  │  ambíguo → reply pedindo clareza (NÃO resolve)                      ║
║  │            volta ao polling Etapa 3                                 ║
║  │  sugestão → avalia, implementa ou explica                           ║
║  └──────────┬──────────┘                                               ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 6: Push + CI  │ git push                                      ║
║  │                     │ Aguarda SonarQube/checks                      ║
║  │                     │ Máx $CI_MAX_RETRIES tentativas                ║
║  └──────────┬──────────┘                                               ║
║             │ falhou? ─────────────────────────────────── ▶ [ENCERRA]  ║
║             │                                                          ║
║             ├── Se Slack Auto Review = true:                           ║
║             │   /slack-review reply <PR-URL>                           ║
║             │   📨 Notifica revisores que comentários foram resolvidos ║
║             │                                                          ║
║             └── volta ao polling Etapa 3                               ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 7: Aprovação  │ Lista revisores que aprovaram                 ║
║  │  Final              │                                               ║
║  └──────────┬──────────┘                                               ║
║             ▼                                                          ║
║  │ Etapa 8: Output     │ PR_URL, aprovadores, comments resolvidos      ║
║                                                                        ║
╚═══════════════════════════════════════════════════════════════╤════════╝
                                                                │
          exec_handoff_save("pr-resolve" → "finalize")          │
                                                                ▼
╔════════════════════════════════════════════════════════════════════════╗
║  FASE 3 — /finalize <PR-URL>                                           ║
║                                                                        ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 0: Config     │ CLAUDE.md → ORG, domínios, triggers           ║
║  └──────────┬──────────┘                                               ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 1: Validar PR │ Aberta? Aprovada?                             ║
║  │                     │ Extrai TASK_ID, serviço, tipo                 ║
║  └──────────┬──────────┘                                               ║
║             │ sem aprovação? ──────────────────────────── ▶ [ENCERRA]  ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 2: Deploy     │ Trigger conforme CLAUDE.md                    ║
║  │  Sandbox            │ (skip → pula)                                 ║
║  └──────────┬──────────┘                                               ║
║             │ falhou? ─────────────────────────────────── ▶ [ENCERRA]  ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 3: Validar    │ curl endpoint sandbox                         ║
║  │  Sandbox            │ (domínio vazio → pula)                        ║
║  └──────────┬──────────┘                                               ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 4: Deploy     │ Trigger conforme CLAUDE.md                    ║
║  │  Homolog            │ (skip → pula)                                 ║
║  └──────────┬──────────┘                                               ║
║             │ falhou? ─────────────────────────────────── ▶ [ENCERRA]  ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 5: Validar    │ curl endpoint homolog                         ║
║  │  Homolog + Evidênc. │ Salva evidence-<TASK-ID>.md                   ║
║  └──────────┬──────────┘                                               ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 6: Jira       │ Comenta evidências                            ║
║  │                     │ Move task → "Done"                            ║
║  └──────────┬──────────┘                                               ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 7: Merge PR   │ gh pr merge --squash --delete-branch          ║
║  │                     │                                               ║
║  │  Se Slack Auto Review = true:                                       ║
║  │  /slack-review reply <PR-URL>                                       ║
║  │  📨 Notifica na thread que PR foi merged                            ║
║  └──────────┬──────────┘                                               ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 8: Deploy     │ Aguarda pipeline de produção                  ║
║  │  Produção           │ Poll gh run list                              ║
║  └──────────┬──────────┘                                               ║
║             │                                                          ║
║             ├── sucesso ───────────────────── ▶ Etapa 9                ║
║             │                                                          ║
║             └── falhou                                                 ║
║                  │                                                     ║
║                  ▼                                                     ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 8.1: Rollback │ git revert HEAD                               ║
║  │  Automático         │ Abre PR de rollback                           ║
║  │                     │ Merge + aguarda deploy                        ║
║  │                     │ Jira → "Fazendo"                              ║
║  └──────────┬──────────┘                                               ║
║             └─────────────────────────────────────────── ▶ [ENCERRA]   ║
║             ▼                                                          ║
║  ┌─────────────────────┐                                               ║
║  │ Etapa 9: Validar    │ curl endpoint produção                        ║
║  │  Produção + Evidênc.│ Salva evidence-<TASK-ID>-prod.md              ║
║  └──────────┬──────────┘                                               ║
║             ▼                                                          ║
║  │ Etapa 10: Output    │ Task, PR, ambientes, status Jira              ║
║                                                                        ║
╚═══════════════════════════════════════════════════════════════╤════════╝
                                                                │
          exec_handoff_clean(TASK_ID)                           │
                                                                ▼
                                                     ┌──────────────────┐
                                                     │  ✅ CONCLUÍDO    │
                                                     │  Task: Done      │
                                                     │  PR: Merged      │
                                                     │  Prod: Validado  │
                                                     └──────────────────┘
```

### Legenda


| Elemento          | Significado                                                  |
| ----------------- | ------------------------------------------------------------ |
| `[ENCERRA]`       | Ciclo interrompido — preenche template de escalação se falha |
| `/skill-name`     | Skill invocada naquela etapa                                 |
| `exec_handoff_*`  | Persistência de estado entre fases (disco)                   |
| `CLAUDE.md →`     | Configuração lida do CLAUDE.md do time                       |
| `$CI_MAX_RETRIES` | Parametrizável via CLAUDE.md (padrão: 2)                     |
| `📨`              | Notificação Slack (se `Slack Auto Review: true`)             |


### Skills chamadas pelo `/run`

```
/run
 ├── /engineer
 │    ├── /jira-integration      (buscar task)
 │    ├── /jira-task-clarity     (avaliar clareza)
 │    ├── /init                  (gerar CLAUDE.md do repo, se necessário)
 │    ├── /execution-feedback    (consultar aprendizados)
 │    ├── /git-workflow          (branch, commits, PR, CI)
 │    ├── /engineer-multi        (se 2+ repos)
 │    └── /slack-review          (notifica review no Slack, se habilitado)
 ├── /pr-resolve
 │    ├── /git-workflow          (push, CI)
 │    └── /slack-review          (notifica resolução de comentários, se habilitado)
 └── /finalize
      ├── /git-workflow          (merge)
      └── /slack-review          (notifica merge na thread, se habilitado)
```

---

## Comandos disponíveis


| Comando                     | O que faz                                                |
| --------------------------- | -------------------------------------------------------- |
| `/engineer`                 | Implementa a próxima task do Jira (ciclo completo)       |
| `/engineer --dry-run`       | Simula tudo sem criar branch, PR ou mover task           |
| `/run`                      | Ciclo completo: engineer + resolve comentários + deploy  |
| `/run-queue --max-tasks 10` | Execução contínua — não bloqueia esperando review        |
| `/run-parallel --workers 3` | Executa múltiplas tasks em paralelo                      |
| `/pr-resolve <url>`         | Monitora PR, classifica e resolve comentários de revisão |
| `/history --stats`          | Estatísticas dos últimos 30 dias                         |
| `/init`                     | Gera CLAUDE.md analisando o repositório                  |


---

## Guardrails (mecanismos de segurança)

O agente não é uma caixa preta. Ele tem limites configuráveis:


| Guardrail                | Padrão                   | Descrição                                              |
| ------------------------ | ------------------------ | ------------------------------------------------------ |
| **Dry-run**              | `--dry-run`              | Simula sem executar ações destrutivas                  |
| **Budget limit**         | $5.00                    | Interrompe se o custo da sessão ultrapassar o limite   |
| **Confidence threshold** | 15/18                    | Não implementa se a clareza da task for insuficiente   |
| **Circuit breaker**      | 3 falhas                 | Para de pegar tasks após N falhas consecutivas         |
| **Merge automático**     | PR aprovada + homolog OK | Merge só acontece com aprovação humana                 |
| **Rollback automático**  | Ativo                    | Reverte automaticamente se o deploy em produção falhar |


Todos são configuráveis no `CLAUDE.md` do time.

---

## Aprendizado compartilhado

Um dos diferenciais do AI Engineer é que agentes em diferentes máquinas **compartilham aprendizados**.

### Como funciona

```
Agente A falha: "mock desatualizado ao adicionar campo no model"
                        │
                        ▼
            ┌──────────────────────┐
            │  Knowledge Service   │
            │  PostgreSQL+pgvector │
            │                      │
            │  pattern registrado  │
            │  times_seen: 1       │
            └──────────┬───────────┘
                       │
Agente B consulta antes de implementar:
  "⚠️ Aprendizado: verificar mocks ao alterar models (visto 3x)"
```

### Auto-promoção

Quando um pattern atinge `times_seen >= 3`, ele é listado como candidato a promoção — ou seja, deve ser avaliado para inclusão permanente no `CLAUDE.md` do repositório.

Isso cria um **ciclo de melhoria contínua**: falhas viram aprendizados, aprendizados viram regras, regras previnem falhas futuras.

---

## Multi-repo

Quando uma task envolve múltiplos repositórios (ex: backend + frontend), o agente coordena automaticamente:

1. Classifica repos: **Producer** (API) e **Consumer** (frontend)
2. Implementa o Producer primeiro
3. Exporta o contrato (endpoints, payloads)
4. Sobe o Producer localmente
5. Implementa o Consumer usando o contrato
6. Testa o Consumer contra o Producer real (localhost)
7. Abre PRs referenciando uma à outra

Tudo com agentes paralelos em worktrees isolados.

---

## CI/CD configurável

Cada time configura seu fluxo de CI/CD no `CLAUDE.md`. O agente lê e adapta:


| Trigger               | O que o agente faz                     |
| --------------------- | -------------------------------------- |
| `auto`                | CI roda sozinho, agente só aguarda     |
| `comment:/ok-to-test` | Posta o comentário na PR para disparar |
| `merge:develop`       | Faz merge para a branch alvo           |
| `skip`                | Pula a etapa inteira                   |


Exemplo para CI automático sem ambientes intermediários:

```markdown
### Testes
- Trigger: `auto`
- Validação: `checks:*`
### Sandbox
- Trigger: `skip`
### Homolog
- Trigger: `skip`
```

---

## Arquitetura do projeto

```
ai-engineer/
├── commands/           # Orquestradores (o que fazer)
│   ├── engineer.md     # Implementação de task
│   ├── run.md          # Ciclo completo
│   ├── run-parallel.md # Execução paralela
│   ├── pr-resolve.md   # Resolução de comentários
│   ├── finalize.md     # Deploy e merge
│   ├── history.md      # Histórico e estatísticas
│   └── init.md         # Gera CLAUDE.md do repo
├── skills/             # Conhecimento (como fazer)
│   ├── jira-integration/     # Buscar, mover, comentar no Jira
│   ├── jira-task-clarity/    # Avaliar clareza de tasks
│   ├── git-workflow/         # Worktree, commits, PR, CI
│   ├── execution-feedback/   # Aprendizado entre execuções
│   └── knowledge-query/      # Busca semântica
├── knowledge-service/  # API Go + PostgreSQL + pgvector
├── scripts/            # Automação (bash)
├── tests/              # Testes de estrutura e integração
└── install.sh          # Instalador interativo
```

### Commands vs Skills

- **Commands** = orquestradores de alto nível. Definem *o que* fazer e em qual ordem.
- **Skills** = conhecimento especializado. Definem *como* fazer cada etapa.

O `/engineer` (command) chama a skill `jira-integration` para buscar tasks, a skill `jira-task-clarity` para avaliar clareza, e a skill `git-workflow` para criar branches e PRs.

---

## Instalação

### Pré-requisitos


| Dependência                                  | Obrigatório | Para que                  |
| -------------------------------------------- | ----------- | ------------------------- |
| [Git](https://git-scm.com/)                  | Sim         | Worktrees, clone, commits |
| [Claude Code](https://claude.ai/code)        | Sim         | Runtime do agente         |
| [GitHub CLI](https://cli.github.com/) (`gh`) | Sim         | PRs, CI, MCP do GitHub    |
| [jq](https://jqlang.github.io/jq/)           | Sim         | Parsing de JSON           |
| [Docker](https://docker.com)                 | Opcional    | Knowledge-service         |


### Um comando

```bash
git clone https://github.com/wallacehenriquesilva/ai-engineer.git
cd ai-engineer
./install.sh
```

O instalador guia por 7 etapas: dependências, autenticação, MCPs (GitHub + Jira), skills, knowledge-service e finalização.

### Verificar

```bash
make check
```

Valida tudo de uma vez: dependências, autenticação, MCPs, skills, knowledge-service.

---

## Início rápido

```bash
# 1. Instale
./install.sh

# 2. Verifique
make check

# 3. Vá para a raiz dos seus repos e abra o Claude Code
cd ~/git
claude

# 4. Teste sem risco
/engineer --dry-run

# 5. Execute de verdade
/engineer
```

---

## Execução contínua

### Uma task por vez (bloqueante)

```
/run
```

Executa o ciclo completo: busca task, implementa, resolve comentários, faz deploy. **Bloqueia** esperando revisão — ideal para uma task isolada.

### Execução contínua com work queue (recomendado)

```
/run-queue --max-tasks 10 --max-active 5
```

Implementa tasks sem bloquear esperando review. O agente:
1. Pega uma task, implementa, abre PR
2. Em vez de esperar revisão, pega a próxima task
3. Monitora todas as PRs em background
4. Quando uma PR recebe feedback → resolve imediatamente (prioridade)
5. Quando uma PR é aprovada → finaliza e faz deploy (prioridade)
6. Repete até processar `--max-tasks` ou esgotar tasks disponíveis

O estado persiste em SQLite (`~/.ai-engineer/queue.db`) — se a sessão cair, execute `/run-queue` novamente para retomar.

```
Prioridade: resolver feedback > finalizar aprovadas > implementar nova task
```

### Múltiplas tasks em paralelo

```
/run-parallel --workers 3
```

Busca N tasks, reserva todas, lança agentes paralelos em worktrees isolados.

### Loop contínuo (fora do Claude Code)

```bash
./scripts/run-loop.sh --max-tasks 10
```

Executa tasks em loop com contexto limpo a cada iteração. Cada task roda em uma sessão independente do Claude Code.

---

## Configuração do time

Na primeira execução, o agente pergunta as configurações e gera um `CLAUDE.md`:

- Board e projeto do Jira
- Label que marca tasks para o agente
- Organização e time de revisão no GitHub
- Pipeline de CI/CD (triggers e validações)
- Guardrails (budget, clareza mínima, circuit breaker)

Esse arquivo é o "cérebro" do agente — ele nunca usa valores hardcoded.

---

## Extensibilidade

### Adicionar uma nova skill

Crie uma pasta em `skills/` com um `SKILL.md`:

```
skills/minha-skill/
├── SKILL.md              # Instruções para o agente
├── examples/             # Código de referência (opcional)
└── references/           # Docs auxiliares (opcional)
```

O `SKILL.md` usa frontmatter YAML:

```markdown
---
name: minha-skill
description: >
  Quando o agente deve acionar esta skill.
context: default
allowed-tools:
  - Bash
  - Read
  - Edit
---

# Instruções detalhadas...
```

Depois instale:

```bash
make install-skills
make test-skills
```

### Roteamento automático

O agente escolhe a skill com base no repositório:


| Indicador                  | Skill acionada             |
| -------------------------- | -------------------------- |
| `go.mod`                   | Skill Go                   |
| `package.json` + React     | Skill frontend             |
| `pom.xml` / `build.gradle` | Skill Java                 |
| Nenhum match               | Gera CLAUDE.md via `/init` |


---

## Perguntas frequentes

**O agente pode fazer deploy em produção sem aprovação?**
Não. O merge só acontece quando um humano aprova a PR e homologação valida. Se o deploy em produção falhar, o agente faz rollback automático.

**Funciona sem Docker?**
Sim. O agente funciona normalmente. Apenas busca semântica e aprendizados compartilhados ficam indisponíveis.

**Funciona com qualquer linguagem?**
Sim. O agente analisa o repositório e se adapta. Skills especializadas (Go, Java, etc.) melhoram a qualidade, mas não são obrigatórias.

**Quanto custa cada execução?**
Depende da complexidade da task. O agente calcula e reporta o custo no final. O budget limit (padrão: $5) impede surpresas.

**E se a task não estiver clara?**
O agente avalia a clareza em 6 dimensões. Se a nota for menor que o threshold, ele comenta no Jira pedindo clarificações e não implementa.

**Posso usar com GitLab/Bitbucket em vez de GitHub?**
Atualmente só GitHub é suportado via MCP. Contribuições para outros providers são bem-vindas.

**Posso usar com Linear/Asana em vez de Jira?**
Atualmente só Jira é suportado via MCP. A arquitetura de skills permite adicionar outros providers.

---

## Links

- **Repositório:** [github.com/wallacehenriquesilva/ai-engineer](https://github.com/wallacehenriquesilva/ai-engineer)
- **Claude Code:** [claude.ai/code](https://claude.ai/code)
- **Licença:** MIT

