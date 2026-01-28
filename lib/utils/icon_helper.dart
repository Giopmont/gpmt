import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// Helper para determinar ícones e cores baseado no tipo de arquivo.
class IconHelper {
  IconHelper._();

  /// Retorna o ícone apropriado para um arquivo ou diretório.
  static IconData getIcon(String path, bool isDirectory) {
    if (isDirectory) return Icons.folder;

    final ext = p.extension(path).toLowerCase();
    return _iconMap[ext] ?? Icons.insert_drive_file;
  }

  /// Retorna a cor apropriada para um arquivo ou diretório.
  static Color getIconColor(String path, bool isDirectory) {
    if (isDirectory) return const Color(0xFFFFD54F); // Amarelo pasta Windows

    final ext = p.extension(path).toLowerCase();
    return _colorMap[ext] ?? Colors.grey.shade500;
  }

  static const Map<String, IconData> _iconMap = {
    // Arquivos compactados
    '.zip': Icons.inventory_2,
    '.rar': Icons.inventory_2,
    '.tar': Icons.inventory_2,
    '.gz': Icons.inventory_2,
    '.7z': Icons.inventory_2,
    '.tgz': Icons.inventory_2,
    '.bz2': Icons.inventory_2,
    '.xz': Icons.inventory_2,

    // Imagens
    '.jpg': Icons.image,
    '.jpeg': Icons.image,
    '.png': Icons.image,
    '.gif': Icons.image,
    '.bmp': Icons.image,
    '.webp': Icons.image,
    '.svg': Icons.image,
    '.ico': Icons.image,

    // Documentos
    '.pdf': Icons.picture_as_pdf,
    '.txt': Icons.description,
    '.md': Icons.description,
    '.log': Icons.description,
    '.doc': Icons.description,
    '.docx': Icons.description,
    '.odt': Icons.description,
    '.rtf': Icons.description,

    // Planilhas
    '.xls': Icons.table_chart,
    '.xlsx': Icons.table_chart,
    '.ods': Icons.table_chart,
    '.csv': Icons.table_chart,

    // Apresentações
    '.ppt': Icons.slideshow,
    '.pptx': Icons.slideshow,
    '.odp': Icons.slideshow,

    // Áudio
    '.mp3': Icons.audio_file,
    '.wav': Icons.audio_file,
    '.ogg': Icons.audio_file,
    '.flac': Icons.audio_file,
    '.aac': Icons.audio_file,
    '.m4a': Icons.audio_file,

    // Vídeo
    '.mp4': Icons.movie,
    '.avi': Icons.movie,
    '.mov': Icons.movie,
    '.mkv': Icons.movie,
    '.wmv': Icons.movie,
    '.webm': Icons.movie,

    // Código/Scripts
    '.exe': Icons.terminal,
    '.bat': Icons.terminal,
    '.sh': Icons.terminal,
    '.py': Icons.code,
    '.js': Icons.code,
    '.ts': Icons.code,
    '.dart': Icons.code,
    '.java': Icons.code,
    '.c': Icons.code,
    '.cpp': Icons.code,
    '.h': Icons.code,
    '.html': Icons.code,
    '.css': Icons.code,
    '.json': Icons.code,
    '.xml': Icons.code,
    '.yaml': Icons.code,
    '.yml': Icons.code,

    // Configuração
    '.ini': Icons.settings,
    '.conf': Icons.settings,
    '.cfg': Icons.settings,
  };

  static final Map<String, Color> _colorMap = {
    // Arquivos compactados
    '.zip': Colors.purple.shade300,
    '.rar': Colors.purple.shade300,
    '.tar': Colors.purple.shade300,
    '.gz': Colors.purple.shade300,
    '.7z': Colors.purple.shade400,
    '.tgz': Colors.purple.shade300,

    // Documentos
    '.pdf': Colors.red.shade400,
    '.doc': Colors.blue.shade600,
    '.docx': Colors.blue.shade600,

    // Imagens
    '.jpg': Colors.blue.shade400,
    '.jpeg': Colors.blue.shade400,
    '.png': Colors.blue.shade400,
    '.gif': Colors.blue.shade400,

    // Planilhas
    '.xls': Colors.green.shade600,
    '.xlsx': Colors.green.shade600,

    // Apresentações
    '.ppt': Colors.orange.shade600,
    '.pptx': Colors.orange.shade600,

    // Executáveis
    '.exe': Colors.grey.shade600,
    '.sh': Colors.grey.shade600,

    // Código
    '.py': Colors.yellow.shade700,
    '.js': Colors.yellow.shade600,
    '.dart': Colors.cyan.shade600,
    '.java': Colors.orange.shade700,
  };
}
