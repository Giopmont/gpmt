import 'package:flutter/material.dart';

/// Constantes de cores da aplicação.
class AppColors {
  AppColors._();

  static const Color scaffoldBackground = Color(0xFFF0F0F0);
  static const Color menuBarBackground = Color(0xFFDDDDDD);
  static const Color toolbarBackground = Color(0xFFEEEEEE);
  static const Color tableHeaderBackground = Color(0xFFF5F5F5);
  static const Color tableRowEven = Colors.white;
  static const Color tableRowOdd = Color(0xFFFAFAFA);
  static const Color selectionHighlight = Color(0xFFCCE8FF);
  static const Color columnBorder = Color(0xFFD0D0D0);
  static const Color rowBorder = Color(0xFFEEEEEE);
  static const Color headerBorder = Color(0xFFCCCCCC);
  static const Color resizeHandle = Color(0xFFB0B0B0);
}

/// Constantes de tamanhos padrão.
class AppSizes {
  AppSizes._();

  // Larguras de coluna padrão
  static const double colWidthName = 280.0;
  static const double colWidthCreated = 150.0;
  static const double colWidthModified = 150.0;
  static const double colWidthType = 100.0;
  static const double colWidthSize = 80.0;

  // Limites de largura de coluna
  static const double colMinName = 100.0;
  static const double colMaxName = 600.0;
  static const double colMinDate = 80.0;
  static const double colMaxDate = 250.0;
  static const double colMinType = 60.0;
  static const double colMaxType = 200.0;

  // Ícones
  static const double iconSizeSmall = 16.0;
  static const double iconSizeMedium = 20.0;
  static const double iconSizeLarge = 24.0;
  static const double iconSizeToolbar = 32.0;

  // Fontes
  static const double fontSizeSmall = 11.0;
  static const double fontSizeNormal = 13.0;
  static const double fontSizeCell = 12.0;
}

/// Extensões de arquivo suportadas.
class SupportedExtensions {
  SupportedExtensions._();

  static const List<String> archives = [
    '.zip',
    '.zipx',
    '.7z',
    '.zi',
    '.tar',
    '.tgz',
    '.gz',
    '.rar',
    '.bz2',
    '.xz',
  ];

  /// Verifica se a extensão é de um arquivo suportado.
  static bool isArchive(String path) {
    final ext = path.toLowerCase();
    return archives.any((e) => ext.endsWith(e));
  }

  /// Verifica se é um arquivo RAR.
  static bool isRar(String path) => path.toLowerCase().endsWith('.rar');

  /// Verifica se é um arquivo ZIP.
  static bool isZip(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.zip') || lower.endsWith('.zipx') || lower.endsWith('.zi');
  }

  /// Verifica se é um arquivo TAR.
  static bool isTar(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.tar') || lower.endsWith('.tgz');
  }

  /// Verifica se é um arquivo 7z.
  static bool is7z(String path) => path.toLowerCase().endsWith('.7z');
}

/// Strings da aplicação (PT-BR).
class AppStrings {
  AppStrings._();

  static const String appTitle = 'GPMT';
  static const String appDisplayName = 'GPMT';

  // Colunas
  static const String colName = 'Nome';
  static const String colCreated = 'Criado';
  static const String colModified = 'Modificado';
  static const String colType = 'Tipo';
  static const String colSize = 'Tamanho';

  // Tipos de arquivo
  static const String typeFolder = 'Pasta';
  static const String typeFile = 'Arquivo';
  static const String typeFileFolder = 'Pasta de Arquivos';
  static const String typeArchive = 'Arquivo compactado';
  static const String typeSelectedDetails = 'Detalhes da Seleção';
  static const String typeMultipleItems = 'Múltiplos itens selecionados.';

  // Diálogos
  static const String extractTo = 'Extrair Para';
  static const String extractOptions = 'Opções de Extração';
  static const String cancel = 'Cancelar';
  static const String extract = 'Extrair';
  static const String skipExisting = 'Pular Existentes';
  static const String overwriteAll = 'Sobrescrever Tudo';
  static const String destinationPath = 'Caminho de destino:';
  static const String password = 'Senha';
  static const String continueLabel = 'Continuar';
  static const String ok = 'OK';
  static const String close = 'Fechar';
  static const String yes = 'Sim';
  static const String saveArchiveAs = 'Salvar Arquivo Como';
  static const String createArchive = 'Criar Arquivo';
  static const String deleteFiles = 'Excluir arquivos';
  static const String deleteFilesConfirmation =
      'Tem certeza de que deseja excluir os arquivos selecionados?';
  static const String fileDropAction = 'Ação ao soltar arquivos';
  static const String compressToArchive = 'Compactar em arquivo';
  static const String copyHere = 'Copiar aqui';
  static const String wizardTitle = 'Assistente do GPMT';
  static const String wizardExtract = 'Descompactar um arquivo';
  static const String wizardCreate = 'Criar um novo arquivo';
  static const String infoTitle = 'Informações';
  static const String archiveInfoTitle = 'Informações do Arquivo';
  static const String folderInfoTitle = 'Informações da Pasta';
  static const String repairArchiveTitle = 'Reparar arquivo';
  static const String repairArchiveAction = 'Reparar';
  static const String deleteErrorTitle = 'Erro ao excluir';
  static const String addErrorTitle = 'Erro ao adicionar';
  static const String fileAccessInfoUnavailable =
      'Não foi possível ler informações do arquivo.';

  // Status
  static const String ready = 'Pronto';
  static const String extracting = 'Extraindo...';
  static const String preparing = 'Preparando...';
  static const String preparingDrag = 'Preparando arraste...';
  static const String attemptingRepair = 'Tentando reparar...';
  static const String selectedSuffix = 'selecionado(s)';
  static const String objectsSuffix = 'objeto(s)';
  static const String upOneLevel = 'Subir um nível';

  // Erros
  static const String errorAccessDirectory = 'Erro ao acessar diretório';
  static const String errorOpenArchive = 'Erro ao Abrir Arquivo';
  static const String unrarNotFound = 'Unrar Não Encontrado';
  static const String errorExtraction = 'Falha na Extração';
  static const String errorUnsupportedFormat = 'Formato não suportado';
  static const String errorGzipPreviewUnavailable =
      'Visualização de GZip/TGZ ainda não implementada';
  static const String errorListArchiveFailed =
      'Falha ao listar o conteúdo do arquivo';
  static const String errorListRarFailed = 'Falha ao listar conteúdo RAR';
  static const String errorList7zUnavailable =
      'Não foi possível listar arquivos 7z sem o binário 7z disponível.';
  static const String errorRarToolUnavailable =
      'Para abrir arquivos RAR, instale "unrar" ou "p7zip-full".';
  static const String errorRarExtractionToolUnavailable =
      'Para extrair arquivos RAR, instale "unrar" no sistema.';
  static const String errorRarExtractionFailed = 'Falha na extração RAR';
  static const String errorRarDeleteToolUnavailable =
      'Instale a CLI "rar" para excluir de arquivos RAR.';
  static const String error7zDeleteToolUnavailable =
      'Instale o "7z" para excluir de arquivos compactados.';
  static const String errorRarAddToolUnavailable =
      'Para adicionar arquivos em RAR, instale a CLI "rar" (não livre).';
  static const String error7zAddToolUnavailable =
      'Instale o "7z" (p7zip) para permitir atualização por arrastar e soltar.';
  static const String errorRarRepairToolUnavailable =
      'A CLI "rar" não foi encontrada.';
  static const String errorZipRepairNotImplemented =
      'O reparo de ZIP ainda não foi implementado por completo.';
  static const String errorSelectSingleArchiveToExtract =
      'Selecione um único arquivo compactado ou abra um para extrair.';
  static const String errorSelectFilesToArchive =
      'Selecione arquivos para adicionar ao arquivo compactado.';
  static const String errorCreateArchiveFailed = 'Falha ao criar arquivo';
  static const String errorDeleteFailed = 'Falha ao excluir arquivos';
  static const String errorGeneric = 'Erro';
  static const String errorFolderCopyNotImplemented =
      'A cópia de pastas via arrastar e soltar ainda não foi implementada.';
  static const String errorSelectSingleArchiveToRepair =
      'Selecione um único arquivo compactado para reparar.';
  static const String errorRepairOnlyRarZip =
      'O reparo só é suportado para arquivos RAR e ZIP.';
  static const String errorAddFilesFailed = 'Falha ao adicionar arquivos';

  // Toolbar
  static const String add = 'Adicionar';
  static const String extractToLabel = 'Extrair';
  static const String test = 'Testar';
  static const String view = 'Ver';
  static const String delete = 'Excluir';
  static const String find = 'Buscar';
  static const String wizard = 'Assistente';
  static const String info = 'Info';
  static const String repair = 'Reparar';

  // Menu
  static const String menuFile = 'Arquivo';
  static const String menuCommands = 'Comandos';
  static const String menuTools = 'Ferramentas';
  static const String menuFavorites = 'Favoritos';
  static const String menuOptions = 'Opções';
  static const String menuHelp = 'Ajuda';

  // Senha
  static const String archiveProtected = 'Arquivo protegido';
  static const String incorrectPassword = 'Senha incorreta';
  static const String promptArchivePassword =
      'Informe a senha para abrir o arquivo.';
  static const String promptArchivePasswordRetry =
      'A senha informada não abriu o arquivo.';

  // Info
  static const String infoPath = 'Caminho';
  static const String infoContains = 'Contém';
  static const String infoItems = 'itens';
  static const String infoTotalSize = 'Tamanho total';
  static const String infoSelected = 'Selecionados';
  static const String infoName = 'Nome';
  static const String infoSize = 'Tamanho';
  static const String infoModified = 'Modificado';
  static const String infoPermissions = 'Permissões';

  // Ações e feedback
  static const String extractionSucceeded = 'Extração concluída em';
  static const String extractionSucceededRar = 'RAR extraído em';
  static const String archiveCreated = 'Arquivo criado';
  static const String filesDeletedSuccessfully =
      'Arquivos excluídos com sucesso.';
  static const String filesAddedSuccessfully =
      'Arquivos adicionados com sucesso.';
  static const String repairConfirmationPrefix =
      'Tentar reparar o arquivo';
  static const String repairConfirmationSuffix =
      'Isso criará uma cópia corrigida.';
}
