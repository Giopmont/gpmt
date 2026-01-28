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

  // Diálogos
  static const String extractTo = 'Extrair Para';
  static const String extractOptions = 'Opções de Extração';
  static const String cancel = 'Cancelar';
  static const String extract = 'Extrair';
  static const String skipExisting = 'Pular Existentes';
  static const String overwriteAll = 'Sobrescrever Tudo';
  static const String destinationPath = 'Caminho de destino:';

  // Status
  static const String ready = 'Pronto';
  static const String extracting = 'Extraindo...';
  static const String preparing = 'Preparando...';

  // Erros
  static const String errorAccessDirectory = 'Erro ao acessar diretório';
  static const String errorOpenArchive = 'Erro ao Abrir Arquivo';
  static const String unrarNotFound = 'Unrar Não Encontrado';
  static const String errorExtraction = 'Falha na Extração';

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
}
