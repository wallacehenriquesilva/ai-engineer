# Contribuindo

Obrigado por considerar contribuir com o AI Engineer!

## Como contribuir

### Reportar bugs

Abra uma [issue](https://github.com/wallacehenriquesilva/ai-engineer/issues/new) com:
- Descrição do problema
- Passos para reproduzir
- Output/erro observado
- Versão (`make version`)

### Sugerir melhorias

Abra uma issue com a tag `enhancement` descrevendo:
- O que você gostaria que o agente fizesse
- Por que seria útil
- Como imagina o comportamento

### Enviar código

1. Fork o repositório
2. Crie uma branch: `git checkout -b feat/minha-feature`
3. Faça suas mudanças
4. Rode os testes: `make test-all`
5. Commit com mensagem semântica: `feat: add minha feature`
6. Push e abra um PR

### Criar uma nova skill

Veja a seção "Criando uma nova skill" no [README.md](README.md).

## Padrões

### Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):
- `feat:` nova funcionalidade
- `fix:` correção de bug
- `docs:` documentação
- `test:` testes
- `chore:` manutenção

### Testes

Antes de abrir um PR, garanta que:

```bash
make test-all    # Go + skills + execution-log
```

Todos os testes devem passar com 0 falhas.

### Skills

- `SKILL.md` deve ter frontmatter com `name`, `description` e `allowed-tools`
- Referências a `examples/` e `references/` devem apontar para arquivos existentes
- Rode `make test-skills` para validar

### Commands

- Frontmatter com `description` e `allowed-tools`
- Instruções claras e numeradas
- Seção "Regras Gerais" ao final

## Estrutura do projeto

```
skills/          → conhecimento do agente (stacks, ferramentas, processos)
commands/        → orquestradores (engineer, pr-resolve, finalize, run)
scripts/         → utilitários bash (execution-log, knowledge-client)
knowledge-service/ → API Go para busca semântica e aprendizados compartilhados
tests/           → validação de estrutura e lógica
```

## Code of Conduct

Este projeto segue o [Contributor Covenant](https://www.contributor-covenant.org/). Ao participar, você concorda em manter um ambiente respeitoso e inclusivo.
