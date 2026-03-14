# AGENTS.md

Este arquivo é a referência principal para agentes de IA que contribuírem com o projeto. Arquivos específicos como `CLAUDE.md`, `CODEX.md` e `GEMINI.md` devem complementar este documento, não contradizê-lo.

## Resumo do Projeto

- Nome: `GPMT`
- Tipo: gerenciador desktop de arquivos compactados
- Stack principal: Flutter / Dart
- Plataformas alvo: Linux e macOS
- Idioma obrigatório para textos visíveis ao usuário: PT-BR

## Objetivo do Produto

O GPMT busca oferecer uma experiência de uso semelhante à de gerenciadores clássicos de arquivos compactados, com navegação simples, ações diretas e integração real com o desktop.

O foco atual não é mobile, web ou sincronização em nuvem. O foco é desktop local.

## Princípios de Produto

- Priorizar UX desktop clara e direta.
- Evitar travamento de interface em operações de I/O.
- Manter comportamento previsível ao abrir, navegar e extrair arquivos.
- Preferir feedback visível ao usuário em vez de falha silenciosa.
- Tratar arquivos protegidos por senha pela interface, nunca por prompt preso ao terminal.

## Arquitetura Atual

- `lib/main.dart`: UI principal, navegação, seleção, diálogos e orquestração.
- `lib/worker.dart`: trabalho pesado de extração via `Isolate`.
- `lib/services/binary_locator.dart`: localização e validação de `7z`, `unrar` e `rar`.
- `lib/services/archive_parser.dart`: parsing da saída de ferramentas externas.
- `lib/models/archive_entry.dart`: modelo comum para entradas de compactados.
- `tool/install_desktop.sh`: build e instalação desktop.

## Regras Técnicas

- Textos de UI, mensagens, labels e diálogos devem ficar em PT-BR.
- Não bloquear a UI com operações pesadas; preferir async e `Isolate`.
- Preservar compatibilidade com Linux e macOS.
- Não remover o suporte a binários empacotados em `assets/bin/...` sem substituição equivalente.
- `RAR` depende de CLI (`unrar`/`rar`), então fluxos de listagem, extração e reparo precisam respeitar essa restrição.
- Para `7z`, evitar comandos interativos; quando houver senha, o fluxo deve ser conduzido pela interface.

## Restrições de Mudança

- Mudanças grandes devem ser incrementais e verificáveis.
- Evite introduzir nova arquitetura de estado sem necessidade concreta.
- Se mexer em comandos de build, instalação ou distribuição, atualize o `README.md`.
- Se mexer em regras ou fluxo esperado para agentes, atualize este arquivo.

## Fluxo de Validação

Sempre que a mudança tocar código Dart ou comportamento do app, validar com:

```bash
flutter analyze
flutter test
```

Se a mudança tocar empacotamento ou instalação, validar também:

```bash
flutter build linux --release
./tool/install_desktop.sh --skip-build
```

No macOS, quando aplicável:

```bash
flutter build macos --release
```

## Padrão de Documentação

- README: orientado a público externo e contribuidores.
- AGENTS: fonte canônica para agentes.
- Arquivos específicos de IA: camadas finas com instruções por ferramenta.

## Boas Práticas Para Contribuições

- Preferir diffs pequenos e rastreáveis.
- Explicar riscos reais quando houver mudança em parsing, senha, instalação ou integração nativa.
- Não deixar instruções duplicadas divergirem entre documentação pública e arquivos de IA.
