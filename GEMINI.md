# Gemini Context & Project Guidelines

## Idioma obrigatório
**PT-BR em respostas, mensagens de UI e labels.**  
Sem inglês em strings visíveis ao usuário.

## Project Overview
**Name:** GPMT (WinRAR-like Archive Manager)  
**Framework:** Flutter (Linux/macOS Desktop)  
**Goal:** Gerenciador de arquivos e compactador/extração com UX retro e operações reais.

## Core Technologies
- **Flutter/Dart:** UI e lógica.
- **Isolates:** extração/compactação em background (`lib/worker.dart`) para evitar travamentos.
- **External Tools:**
  - `unrar`: obrigatório para RAR (lista/extração).
  - `7z` (p7zip): preferido para ZIP/7Z (performance e Zip64).
  - **Empacotados:** binários podem vir de `assets/bin/linux|macos/`.
- **UI:** estilo retro (Windows 95/XP).
- **Drag & Drop:** `super_drag_and_drop`, com extração para temp antes de concluir drop.

## Essential Instructions
1. **Null Safety:** evite `!` sem guarda explícita.
2. **Plataformas:** Linux e macOS. Trate permissões e paths corretamente.
3. **Estado:** `setState` em `main.dart` (simples, direto).
4. **Erros:** nunca travar; `try-catch` e feedback ao usuário.
5. **Performance:** use `Isolate` em extrações; considere async em diretórios grandes.
6. **Estilo de código:** camelCase; `main.dart` UI, `worker.dart` tarefas pesadas; comentários explicam o porquê.

## Comportamentos Conhecidos
- **Drag & Drop:** modo “flatten” para arquivos individuais extraídos de dentro do archive.
- **Arquivos como pastas:** `_isViewingArchive` simula navegação interna.

## Integrações
- **macOS:** `AppDelegate.swift` envia arquivo aberto via channel `com.gpmt/file_handler`.
- **Linux:** `linux/gpmt.desktop` fornece ação “Extract Here (GPMT)”.

## Debugging
- Use `ScaffoldMessenger` para feedback rápido.
- Logs devem ser úteis e concisos.
