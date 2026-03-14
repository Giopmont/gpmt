# CODEX.md

Leia `AGENTS.md` antes de alterar código ou documentação.

## Papel Deste Arquivo

Este arquivo registra preferências específicas para uso com agentes orientados a terminal, como Codex. O contexto comum do projeto está em `AGENTS.md`.

## Diretrizes

- Trabalhar em PT-BR nas respostas e nos textos do produto.
- Preferir mudanças pequenas, verificáveis e com baixo risco de regressão.
- Preservar a experiência desktop atual enquanto o projeto ainda estiver concentrado em `lib/main.dart`.
- Ao tocar build ou instalação, validar o fluxo completo, não apenas o código-fonte.
- Ao tocar documentação, manter consistência entre `README.md`, `AGENTS.md` e os arquivos específicos de IA.

## Checklist Prático

- usar `flutter analyze`
- usar `flutter test`
- se mexer em instalação: `flutter build linux --release`
- se mexer em documentação de setup: revisar comandos e caminhos citados

## Riscos Que Merecem Atenção

- parsing de saída de `7z` e `unrar`
- arquivos protegidos por senha
- integração de `.desktop` no Linux
- coexistência entre instalação em `/opt` e instalações antigas em `~/.local`
