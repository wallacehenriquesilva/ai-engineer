# Integração com Outras Skills

A skill `slack-review` pode ser chamada por outras skills do fluxo de engenharia
para automatizar a comunicação de code review.

## Fluxos de integração

### /engineer → slack-review

Após o `/engineer` abrir uma PR, ele pode acionar `slack-review request` automaticamente.

**Quando acionar:** Após a PR ser criada com sucesso e o CI passar.

**Como:** A skill `/engineer` pode invocar `/slack-review request <PR-URL>` como
último passo antes de mover a task no Jira.

### /pr-resolve → slack-review

Quando o `/pr-resolve` termina de resolver comentários de revisão, pode acionar
`slack-review reply` para notificar os revisores no Slack.

**Quando acionar:** Após todos os comentários serem resolvidos e os commits pushados.

**Como:** A skill `/pr-resolve` pode invocar `/slack-review reply <PR-URL>` com
uma mensagem resumindo as alterações feitas.

### /finalize → slack-review

Após o merge e deploy, pode notificar na thread original que a PR foi mergeada.

**Quando acionar:** Após o merge ser confirmado.

**Como:** `/slack-review reply <PR-URL>` — a skill detecta automaticamente que a
PR está merged e adiciona o indicador :merged:.

## Configuração no CLAUDE.md

Para habilitar a integração automática, o usuário pode adicionar ao CLAUDE.md:

```
Slack Auto Review: true
```

Quando habilitado, as skills do fluxo de engenharia acionam `slack-review`
automaticamente nos pontos descritos acima. Quando desabilitado (padrão),
o usuário precisa invocar manualmente.
