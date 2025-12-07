# Claude Context & Project Guidelines

## Project: GPMT (WinRAR Clone)

### Tech Stack
*   **Flutter (Linux)**
*   **Dart FFI / Shell:** Relies on `unrar` and `7z` binaries.
*   **Concurrency:** `Isolate` for heavy I/O.

### Architectural Constraints
1.  **Isolates:** Extraction logic resides in `lib/worker.dart`. Main UI (`lib/main.dart`) spawns isolates to prevent freezing.
2.  **Navigation:** `_currentPath` tracks the file system. `_archivePath` + `_isViewingArchive` tracks virtual archive navigation.
3.  **Drag & Drop:** Implemented via `super_drag_and_drop`. Requires "Just-in-Time" extraction to a temp folder when dragging out of an archive.

### Coding Standards
*   **Safety:** Prioritize Null Safety.
*   **UX:** Mimic WinRAR's behavior (modal dialogs for wizards/info, status bar updates).
*   **FileSystem:** Handle Linux paths correctly.

### Critical Logic
*   **RAR Support:** Strictly via `unrar` CLI (Dart `archive` package doesn't support RAR5).
*   **Zip Support:** Prefer `7z` CLI if available, fallback to Dart `archive`.
