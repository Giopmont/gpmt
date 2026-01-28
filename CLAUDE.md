# Claude Context & Project Guidelines

## Project: GPMT (WinRAR-like Archive Manager)

### Idioma obrigatório
* **Todas as respostas e mudanças devem estar em PT-BR.**
* **Textos de UI, mensagens de erro e rótulos devem ser PT-BR.**

### Tech Stack
* **Flutter (Desktop: Linux/macOS)**.
* **Shell/Process:** depende de binários `unrar` e `7z` (system ou empacotados em `assets/bin/...`).
* **Concorrência:** `Isolate` para I/O pesado.

### Arquitetura
1. **Isolates:** extração em `lib/worker.dart`; UI (`lib/main.dart`) apenas orquestra.
2. **Navegação:** `_currentPath` = FS real; `_archivePath` + `_isViewingArchive` = navegação virtual em arquivo.
3. **Drag & Drop:** `super_drag_and_drop`, extração “just-in-time” para temp ao arrastar para fora do arquivo.
4. **Integrações nativas:**
   - macOS: `AppDelegate.swift` envia arquivo via channel `com.gpmt/file_handler`.
   - Linux: `.desktop` define “Open” e ação “Extract Here (GPMT)”.

### Padrões de Código
* **Null Safety:** evite `!` sem guarda explícita.
* **UX:** comportamento similar ao WinRAR (modais, status bar, feedback).
* **I/O:** operações grandes sempre async/isolate.
* **Paths:** suporte a Linux/macOS, tratar permissões e symlinks com cuidado.

### Lógica Crítica
* **RAR:** somente `unrar` CLI.
* **ZIP/TAR:** use `7z` quando disponível; fallback `archive` para casos simples.
* **Fallback de binários:** preferir empacotados quando presentes e marcados como executáveis.
