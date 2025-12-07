# Codex/Copilot Context

## Project: GPMT (WinRAR Replica on Linux)

### Context
Building a file manager and archive utility in Flutter that mimics WinRAR.

### Key Components
- `lib/main.dart`: Main UI, State, File listing logic.
- `lib/worker.dart`: Background Isolate for extraction (supports 7z and Dart Archive).

### Rules
1.  **Do not block UI:** File operations > 10MB should be async or isolated.
2.  **Dependencies:** `unrar` (system), `7z` (system), `super_drag_and_drop` (pub), `archive` (pub).
3.  **Style:** Retro Windows styling (Colors, Fonts).

### Common Patterns
- **Opening Archive:** Check extension -> `unrar l` (if rar) OR `ZipDecoder` (if zip) -> Populate list.
- **Extraction:** Show Progress Dialog -> Spawn Isolate -> Stream Progress -> Close Dialog.
- **Drag & Drop:** Intercept drag -> Extract specific file to `/tmp` -> Return path to OS.
