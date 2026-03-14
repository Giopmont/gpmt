# GPMT

Gerenciador de arquivos compactados para Linux e macOS, desenvolvido em Flutter, com navegação inspirada em ferramentas clássicas como WinRAR e foco em integração desktop.

> Status atual: desktop-first, Linux e macOS, em evolução ativa.

## Visão Geral

O GPMT foi criado para abrir, navegar, extrair e montar arquivos compactados com uma UX direta, orientada a desktop, sem depender de interfaces web ou wrappers genéricos. O projeto combina Flutter para a interface com ferramentas reais de compressão no sistema operacional quando necessário.

## Funcionalidades

- Abrir e navegar por diretórios do sistema de arquivos.
- Abrir arquivos `RAR`, `ZIP`, `TAR` e `7Z`.
- Navegar dentro do arquivo compactado como se fosse uma pasta.
- Extrair o arquivo inteiro ou apenas itens selecionados.
- Suporte a arquivos protegidos por senha, com prompt visual na interface.
- Arrastar arquivos para fora do compactado com extração temporária.
- Arrastar arquivos para dentro do aplicativo para copiar ou compactar.
- Integração com Linux via arquivo `.desktop` e ação de extração.
- Instalador para desktop em Linux e macOS via script.

## Plataformas Suportadas

- Linux desktop
- macOS desktop

O projeto não está organizado hoje como produto mobile ou web. O foco atual é desktop.

## Stack Técnica

- Flutter / Dart
- `Isolate` para operações pesadas sem travar a UI
- `unrar` para operações com `RAR`
- `7z` para `7Z` e como backend preferencial para alguns fluxos de extração/listagem
- pacote `archive` como fallback em cenários simples
- `super_drag_and_drop` para drag and drop desktop

## Arquitetura

Arquivos principais do projeto:

- `lib/main.dart`: interface, estado principal, navegação e orquestração dos fluxos.
- `lib/worker.dart`: extração em background via `Isolate`.
- `lib/services/binary_locator.dart`: detecção de binários empacotados ou do sistema.
- `lib/services/archive_parser.dart`: parsing de saída de `7z` e `unrar`.
- `lib/models/archive_entry.dart`: modelo unificado para entradas do compactado.
- `tool/install_desktop.sh`: build e instalação desktop.

## Requisitos de Desenvolvimento

### Linux

- Flutter estável
- `clang`
- `cmake`
- `ninja-build`
- `pkg-config`
- `libgtk-3-dev`

### macOS

- Flutter estável
- Xcode
- CocoaPods

## Execução Local

```bash
flutter pub get
flutter run -d linux
```

No macOS:

```bash
flutter pub get
flutter run -d macos
```

## Build

### Linux

```bash
flutter build linux --release
```

### macOS

```bash
flutter build macos --release
```

## Instalação Desktop

O projeto possui um instalador próprio para ambiente desktop:

```bash
./tool/install_desktop.sh
```

Opções úteis:

```bash
./tool/install_desktop.sh --build-only
./tool/install_desktop.sh --skip-build
```

No Linux, o script instala em `/opt/gpmt` e cria integração tanto em `/usr/local` quanto em `~/.local`, evitando conflito com instalações antigas no diretório do usuário.

## Binários Externos

O aplicativo pode usar binários empacotados em `assets/bin/linux/` e `assets/bin/macos/`, com fallback para ferramentas disponíveis no sistema.

Para atualizar os binários empacotados:

```bash
./tool/download_dependencies.sh
```

## Qualidade e Validação

Comandos usados para validar mudanças:

```bash
flutter analyze
flutter test
```

## Estrutura do Repositório

```text
lib/
  main.dart
  worker.dart
  models/
  services/
  utils/
linux/
macos/
assets/
tool/
```

## Roadmap

- Dividir `lib/main.dart` em módulos menores.
- Padronizar toda a UI em PT-BR.
- Melhorar empacotamento e distribuição para release público.
- Expandir cobertura de testes para fluxos de arquivos protegidos, drag and drop e parsing.
- Refinar visual desktop para consistência entre Linux e macOS.

## Contribuição

Pull requests e issues são bem-vindos. Ao reportar bug, inclua:

- sistema operacional e versão
- tipo de arquivo compactado
- se o arquivo usa senha
- comportamento esperado e comportamento atual
- logs relevantes, quando houver

## Arquivos Para Agentes de IA

Este repositório inclui documentação específica para assistentes:

- `AGENTS.md`: fonte principal de contexto e regras do projeto
- `CLAUDE.md`
- `CODEX.md`
- `GEMINI.md`

## Licença

O código-fonte original do GPMT está licenciado sob a licença MIT. Veja [LICENSE](LICENSE).

Importante:

- componentes de terceiros mantêm suas próprias licenças
- binários empacotados como `7z` e `UnRAR` não passam automaticamente a ser MIT
- detalhes adicionais estão em [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
