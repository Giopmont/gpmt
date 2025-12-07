# Gemini Context & Project Guidelines

## Project Overview
**Name:** GPMT (WinRAR Replica)
**Framework:** Flutter (Linux Desktop)
**Goal:** Create a functional, visual replica of WinRAR for Linux, handling real file operations, archiving, and extraction.

## Core Technologies
- **Flutter/Dart:** UI and Logic.
- **Isolates:** heavy lifting (extraction/compression) must run in background Isolates (`lib/worker.dart`) to prevent UI freezes.
- **External Tools:**
  - `unrar`: Required for RAR extraction and listing (proprietary format support).
  - `7z` (p7zip): Preferred for Zip/7z handling due to performance and Zip64 support.
  - `dart:io`: File system operations.
- **UI:** Custom retro-style (Windows 95/XP era gray themes, specific icons).
- **Drag & Drop:** Uses `super_drag_and_drop`. Critical: drag-out requires extracting files to a temp directory synchronously (awaited) before the drop completes.

## Essential Instructions
1.  **Null Safety:** Strict null safety. Always check `_archivePath` or `sourceArchive` before usage. Avoid `!` bang operators unless guaranteed by a preceding guard clause.
2.  **Platform:** Linux is the primary target. Ensure paths (`/`), shell commands (`which`, `unrar`, `7z`), and file permissions are handled correctly.
3.  **State Management:** Currently using `setState` within `main.dart`. Keep it simple but clean.
4.  **Error Handling:** Never crash the app. Wrap file operations in `try-catch`. Show user-friendly `SnackBar` or `AlertDialog` on errors.
5.  **Performance:**
    - List directories synchronously is fine for small folders, but consider async for huge ones.
    - **ALWAYS** use `extractWorker` (Isolate) for extraction operations. Do not block the main thread.
6.  **Code Style:**
    - Variable names: camelCase (e.g., `_currentPath`).
    - File structure: Keep `main.dart` for UI and `worker.dart` for background tasks.
    - Comments: Explain *why*, not just *what*.

## Known Behaviors
- **Drag & Drop:** We use a "flatten" approach for single file drags from archives to ensure they appear at the root of the destination drop, matching user expectation.
- **Archives:** We treat entering an archive (Zip/Rar) like entering a directory in the UI (`_isViewingArchive` flag).

## Debugging
- Use `ScaffoldMessenger` for quick status updates.
- Logs should be meaningful.
