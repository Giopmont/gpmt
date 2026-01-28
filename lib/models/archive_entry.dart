import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Modelo unificado para entradas de arquivo (ZIP, RAR, TAR, etc.)
class ArchiveEntry {
  final String name;
  final int size;
  final DateTime? dateModified;
  final DateTime? dateCreated;
  final bool isDirectory;
  final String? compressionMethod;
  final int? compressedSize;

  ArchiveEntry({
    required this.name,
    required this.size,
    this.dateModified,
    this.dateCreated,
    this.isDirectory = false,
    this.compressionMethod,
    this.compressedSize,
  });

  /// Nome do arquivo (basename).
  String get baseName => p.basename(name);

  /// Extensão do arquivo (em minúsculas).
  String get extension => p.extension(name).toLowerCase();

  /// Tipo de arquivo formatado para exibição.
  String get typeDescription {
    if (isDirectory) return 'Pasta';
    if (extension.isEmpty) return 'Arquivo';
    return '${extension.substring(1).toUpperCase()} File';
  }

  /// Cria ArchiveEntry a partir de ArchiveFile (pacote archive).
  factory ArchiveEntry.fromArchiveFile(ArchiveFile file) {
    DateTime? modTime;
    if (file.lastModTime > 0) {
      modTime = DateTime.fromMillisecondsSinceEpoch(file.lastModTime * 1000);
    }

    return ArchiveEntry(
      name: file.name.replaceAll('\\', '/'),
      size: file.size,
      dateModified: modTime,
      dateCreated: modTime, // ZIP não tem data de criação separada
      isDirectory: !file.isFile,
      compressedSize: file.rawContent?.length,
    );
  }

  /// Cria ArchiveEntry a partir de parsing de saída do 7z.
  factory ArchiveEntry.from7zParsing({
    required String path,
    int? size,
    DateTime? modified,
    DateTime? created,
    bool isFolder = false,
  }) {
    return ArchiveEntry(
      name: path,
      size: size ?? 0,
      dateModified: modified,
      dateCreated: created,
      isDirectory: isFolder,
    );
  }

  /// Cria ArchiveEntry a partir de parsing de saída do unrar.
  factory ArchiveEntry.fromUnrarParsing({
    required String name,
    required int size,
    DateTime? dateModified,
    bool isDirectory = false,
  }) {
    return ArchiveEntry(
      name: name,
      size: size,
      dateModified: dateModified,
      isDirectory: isDirectory,
    );
  }

  @override
  String toString() =>
      'ArchiveEntry(name: $name, size: $size, isDir: $isDirectory)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArchiveEntry &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
}

/// Modelo para item do sistema de arquivos com cache de stats.
class FileItem {
  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
  final DateTime? created;
  final String typeDescription;

  FileItem({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    this.modified,
    this.created,
    required this.typeDescription,
  });

  /// Extensão do arquivo (em minúsculas).
  String get extension => p.extension(path).toLowerCase();
}
