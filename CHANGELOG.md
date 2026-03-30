# Changelog

Todas as mudanças notáveis deste projeto serão documentadas neste arquivo.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

---

## [0.1.0] - 2026-03-30

Primeira versão pública.

### Adicionado

- **Commands:** `/engineer`, `/engineer-multi`, `/run`, `/run-parallel`, `/pr-resolve`, `/finalize`, `/history`, `/init`
- **Skills:** `jira-integration`, `jira-task-clarity`, `git-workflow`, `execution-feedback`, `knowledge-query`
- **Knowledge-service:** API Go com PostgreSQL + pgvector para busca semântica, aprendizados compartilhados e histórico de execuções
- **CI/CD Pipeline configurável:** triggers (`auto`, `comment:X`, `merge:X`, `skip`) e validações definidos no CLAUDE.md de cada time
- **Guardrails:** dry-run, budget limit, confidence threshold, circuit breaker, rollback automático
- **Multi-repo:** coordenação Producer→Consumer com contrato exportado e teste de integração cross-repo
- **Aprendizado compartilhado:** agentes em diferentes máquinas compartilham learnings via knowledge-service
- **Installer interativo:** setup de 7 etapas com onboarding de MCPs, autenticação e knowledge-service (Mac/Linux/Windows)
- **Diagnóstico:** `make check` valida dependências, MCPs, auth, skills, knowledge-service e versão
- **Execução contínua:** `make run-loop` com contexto limpo a cada task
- **Testes:** 162 checks (87 skills + 60 Go + 15 bash)
- **CI/CD:** GitHub Actions (testes + release automático por tag)
- **`/init`:** gera CLAUDE.md automaticamente analisando o repo (stack, estrutura, testes, comandos)
