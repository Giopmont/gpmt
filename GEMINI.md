# GEMINI.md

Leia `AGENTS.md` como fonte principal de contexto do projeto.

## Papel Deste Arquivo

Este documento acrescenta notas específicas para uso com Gemini, mantendo `AGENTS.md` como base canônica.

## Diretrizes

- Produzir respostas e documentação em PT-BR.
- Não deixar strings visíveis ao usuário em inglês, salvo quando forem nomes técnicos inevitáveis.
- Priorizar clareza arquitetural e comportamento previsível.
- Ao sugerir refatorações, preferir etapas incrementais em vez de reescritas amplas.
- Ao revisar UX, considerar Linux e macOS como plataformas de primeira classe.

## Áreas Sensíveis

- fluxos com senha
- extração em background
- integração com binários externos
- drag and drop com arquivos temporários
- scripts de build e instalação

## Validação Recomendada

```bash
flutter analyze
flutter test
```

Quando a mudança tocar empacotamento ou distribuição:

```bash
flutter build linux --release
./tool/install_desktop.sh --skip-build
```
