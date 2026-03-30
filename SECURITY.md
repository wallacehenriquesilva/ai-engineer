# Segurança

## Reportar vulnerabilidades

Se encontrar uma vulnerabilidade de segurança, **não abra uma issue pública**.

Envie um email para o mantenedor do projeto ou abra uma issue privada no GitHub.

Inclua:
- Descrição da vulnerabilidade
- Passos para reproduzir
- Impacto potencial

Responderemos em até 48 horas.

## Escopo

O AI Engineer manipula:
- Credenciais de API (Jira, GitHub, Gemini) via `.env` e MCPs
- Código fonte dos repositórios do time
- Tasks e comentários no Jira
- Pull requests e branches no GitHub

## Boas práticas

- Nunca commite `.env` com credenciais reais
- Use API tokens com escopo mínimo (read-only quando possível)
- Revise PRs geradas pelo agente antes do merge
- Configure o budget limit para evitar custos inesperados
- O gate de segurança no `/finalize` exige aprovação humana antes do merge
