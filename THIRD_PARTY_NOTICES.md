# Third-Party Notices

Este projeto inclui ou pode incluir componentes de terceiros que nao estao cobertos pela licenca MIT do codigo-fonte original do GPMT.

## Escopo

- O codigo do GPMT esta sob a licenca MIT.
- Binarios, bibliotecas, assets ou ferramentas de terceiros mantem suas proprias licencas.
- Ao redistribuir builds do aplicativo, voce deve revisar estas dependencias e cumprir os termos de cada fornecedor.
- No estado atual do repositorio, isso inclui os binarios rastreados em `assets/bin/linux/` e `assets/bin/macos/`.

## Componentes Relevantes

### 7-Zip

- Uso no projeto: listagem e extracao de alguns formatos, incluindo `7z`.
- Fonte oficial: https://7-zip.org/
- Informacoes oficiais de licenca:
  - https://7-zip.org/
  - https://7-zip.org/faq.html

Resumo operacional:

- O site oficial informa que a maior parte do codigo esta sob GNU LGPL.
- Algumas partes usam BSD 3-Clause.
- Existem tambem restricoes relacionadas ao codigo unRAR em partes especificas.
- A FAQ oficial informa que, ao usar executaveis ou DLLs do 7-Zip em uma aplicacao comercial, a documentacao deve mencionar o uso do 7-Zip, a licenca GNU LGPL e o link para https://7-zip.org/.

## UnRAR / RARLAB

- Uso no projeto: listagem e extracao de arquivos `RAR`.
- Fonte oficial: https://www.rarlab.com/
- Informacoes oficiais:
  - https://www.rarlab.com/license.htm
  - https://www.rarlab.com/rar_add.htm

Resumo operacional:

- Os binarios oficiais de UnRAR para Linux e macOS sao distribuidos como parte dos pacotes oficiais da RARLAB.
- A pagina oficial de licenca da RARLAB informa uma excecao especifica para componentes UnRAR em relacao a distribuicao separada de partes do pacote.
- A licenca oficial contem restricoes especificas, incluindo a proibicao de uso para recriar o algoritmo proprietario de compressao RAR.
- O tratamento juridico de redistribuicao desses binarios nao deve ser presumido como equivalente a uma licenca open source permissiva.

## Recomendacoes Antes de Publicar Releases

- Confirmar que qualquer binario empacotado em `assets/bin/` continua vindo de fonte oficial.
- Incluir este arquivo em distribuicoes binarias e no repositorio publico.
- Revisar se a estrategia de empacotar `UnRAR` continua adequada para o tipo de distribuicao desejado.
- Confirmar que icones e outros assets do projeto podem ser redistribuidos publicamente.

## Aviso

Este arquivo nao substitui a leitura das licencas oficiais dos terceiros. Em caso de redistribuicao publica ampla, a leitura das fontes oficiais acima continua sendo necessaria.
