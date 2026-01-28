# Codex/Copilot Context

## Project: GPMT (WinRAR-like Archive Manager)

### Idioma obrigatório
**PT-BR em todas as respostas e em qualquer texto de UI.**

### Contexto
Gerenciador de arquivos e arquivador em Flutter (Desktop Linux/macOS), com UI retro inspirada no WinRAR.

### Componentes-chave
- `lib/main.dart`: UI, estado, listagem e navegação.
- `lib/worker.dart`: Isolate para extração (7z/`archive`).
- `macos/Runner/AppDelegate.swift`: bridge de arquivos abertos no Finder.
- `linux/gpmt.desktop`: integração de menu/ações no Linux.

### Regras
1. **Não bloquear UI:** operações pesadas sempre async/isolate.
2. **Dependências:** `unrar` e `7z` podem ser system ou empacotados em `assets/bin/...`.
3. **Estilo:** visual retro, com feedback claro (SnackBar/AlertDialog).
4. **Segurança:** trate permissões/erros silenciosamente, mas informe o usuário.

### Padrões comuns
- **Abrir arquivo:** checar extensão -> `unrar l` (RAR) ou `ZipDecoder` (ZIP) -> listar entradas.
- **Extrair:** dialog + overwrite -> Isolate -> progresso -> fechar dialog.
- **Drag & Drop:** extrair arquivo específico para temp e devolver caminho ao SO.
