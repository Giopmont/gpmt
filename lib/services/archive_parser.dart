import 'package:intl/intl.dart';
import '../models/archive_entry.dart';

/// Parser para saídas de comandos de arquivamento.
class ArchiveParser {
  ArchiveParser._();

  /// Parseia a saída do comando `7z l -slt` (listing detalhado).
  static List<ArchiveEntry> parse7zListing(String output) {
    final lines = output.split('\n');
    final List<ArchiveEntry> entries = [];

    String? currentPath;
    int? currentSize;
    DateTime? currentModified;
    DateTime? currentCreated;
    bool? currentIsDir;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        // Fim de bloco - salvar entrada atual
        if (currentPath != null) {
          entries.add(ArchiveEntry.from7zParsing(
            path: currentPath,
            size: currentSize,
            modified: currentModified,
            created: currentCreated,
            isFolder: currentIsDir ?? false,
          ));
        }
        currentPath = null;
        currentSize = null;
        currentModified = null;
        currentCreated = null;
        currentIsDir = null;
        continue;
      }

      final parts = trimmed.split('=');
      if (parts.length < 2) continue;

      final key = parts[0].trim();
      final value = parts.sublist(1).join('=').trim();

      switch (key) {
        case 'Path':
          currentPath = value.replaceAll('\\', '/');
          break;
        case 'Size':
          currentSize = int.tryParse(value);
          break;
        case 'Folder':
          currentIsDir = (value == '+');
          break;
        case 'Modified':
          currentModified = DateTime.tryParse(value);
          break;
        case 'Created':
          currentCreated = DateTime.tryParse(value);
          break;
      }
    }

    // Adicionar última entrada se existir
    if (currentPath != null) {
      entries.add(ArchiveEntry.from7zParsing(
        path: currentPath,
        size: currentSize,
        modified: currentModified,
        created: currentCreated,
        isFolder: currentIsDir ?? false,
      ));
    }

    return entries;
  }

  /// Parseia a saída do comando `unrar l -c-` (listing).
  static List<ArchiveEntry> parseUnrarListing(String output) {
    final lines = output.split('\n');
    final List<ArchiveEntry> entries = [];

    // Regex para formato "Attributes Size Date Time Name"
    final attrFirstRegex = RegExp(r'^\s*(\S+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(.+)$');

    // Formatos de data suportados pelo unrar
    final dateFormats = [
      DateFormat('yyyy-MM-dd HH:mm'),
      DateFormat('dd-MM-yy HH:mm'),
      DateFormat('MM-dd-yy HH:mm'),
      DateFormat('yyyy-MM-dd HH:mm:ss'),
    ];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      // Ignorar cabeçalhos e rodapés
      if (_isUnrarHeaderOrFooter(line)) continue;

      final match = attrFirstRegex.firstMatch(line);
      if (match != null) {
        try {
          final attr = match.group(1)!;
          final sizeStr = match.group(2)!;
          final dateStr = match.group(3)!;
          final timeStr = match.group(4)!;
          final name = match.group(5)!.trim().replaceAll('\\', '/');

          if (attr.startsWith('Attributes')) continue;

          final size = int.tryParse(sizeStr) ?? 0;
          DateTime? dateModified;

          final dateTimeString = '$dateStr $timeStr';
          for (final fmt in dateFormats) {
            try {
              dateModified = fmt.parse(dateTimeString);
              break;
            } catch (_) {}
          }

          final isDirectory = attr.startsWith('d') || attr.contains('D');

          entries.add(ArchiveEntry.fromUnrarParsing(
            name: name,
            size: size,
            dateModified: dateModified,
            isDirectory: isDirectory,
          ));
        } catch (e) {
          // Ignorar linhas mal formatadas
        }
      }
    }

    return entries;
  }

  /// Verifica se a linha é um cabeçalho ou rodapé do unrar.
  static bool _isUnrarHeaderOrFooter(String line) {
    return line.startsWith('---') ||
        line.startsWith('Archive:') ||
        line.startsWith('Details:') ||
        line.contains('Attributes      Size') ||
        line.startsWith('UNRAR') ||
        line.contains('Alexander Roshal') ||
        line.trim().startsWith(RegExp(r'\d+\s+\d+$'));
  }
}
