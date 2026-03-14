# CLAUDE.md

Leia `AGENTS.md` antes de propor ou aplicar qualquer mudança.

## Papel Deste Arquivo

Este documento adiciona observações específicas para uso com Claude. O contexto compartilhado do projeto fica em `AGENTS.md`.

## Diretrizes

- Responder e documentar em PT-BR.
- Manter todo texto de UI em PT-BR.
- Em mudanças grandes, começar por um plano curto e objetivo.
- Ao revisar código, dar prioridade a regressões de UX, I/O bloqueante e compatibilidade Linux/macOS.
- Em documentação, escrever para público externo com linguagem clara e sem texto de template.

## Pontos de Atenção

- Não tratar fluxo de senha por prompt de terminal.
- Não assumir que `RAR` pode ser manipulado sem CLI apropriada.
- Não substituir comportamento desktop por abstrações genéricas sem ganho real.

## Validação Esperada

Quando houver alteração funcional:

```bash
flutter analyze
flutter test
```
