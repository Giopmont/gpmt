import 'dart:io';
import 'dart:isolate';
import 'dart:convert';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

class ExtractTask {
  final String sourcePath;
  final String destinationPath;
  final List<String> selectedFiles;
  final bool overwrite;
  final bool useSystem7z;
  final bool flatten;
  final String? custom7zExecutable;
  final String? password;
  final SendPort? sendPort;

  ExtractTask({
    required this.sourcePath,
    required this.destinationPath,
    required this.selectedFiles,
    required this.overwrite,
    this.useSystem7z = false,
    this.flatten = false,
    this.custom7zExecutable,
    this.password,
    this.sendPort,
  });
}

// Changed to return 'void' instead of 'Future<void>' to satisfy Isolate.spawn signature
void extractWorker(ExtractTask task) async {
  if (task.useSystem7z) {
    try {
      await _extractWith7z(task);
      return;
    } catch (e) {
      // Tenta a extração nativa abaixo antes de reportar falha ao processo pai.
    }
  }

  final inputStream = InputFileStream(task.sourcePath);
  try {
    Archive archive;
    final ext = p.extension(task.sourcePath).toLowerCase();

    if (ext == '.zip') {
      archive = ZipDecoder().decodeBuffer(inputStream);
    } else if (ext == '.tar') {
      archive = TarDecoder().decodeBuffer(inputStream);
    } else {
      throw Exception("Unsupported format for extraction: $ext");
    }

    int totalFiles = archive.length;
    if (task.selectedFiles.isNotEmpty) {
      totalFiles = task.selectedFiles.length;
    }

    int processedCount = 0;

    for (final file in archive) {
      if (task.selectedFiles.isNotEmpty) {
        if (!task.selectedFiles.contains(file.name)) continue;
      }

      final filename = task.flatten ? p.basename(file.name) : file.name;
      final destPath = p.join(task.destinationPath, filename);

      if (task.sendPort != null) {
        task.sendPort!.send({
          'type': 'progress',
          'filename': filename,
          'current': processedCount,
          'total': totalFiles
        });
      }

      if (file.isFile) {
        final destFile = File(destPath);
        if (destFile.existsSync()) {
          if (!task.overwrite) {
            processedCount++;
            continue;
          }
        }

        destFile.createSync(recursive: true);
        final outputStream = OutputFileStream(destPath);
        try {
          file.writeContent(outputStream);
        } finally {
          outputStream.close();
        }
      } else {
        if (!task.flatten) {
          Directory(destPath).createSync(recursive: true);
        }
      }
      processedCount++;
    }

    if (task.sendPort != null) {
      task.sendPort!.send({'type': 'done'});
    }
  } catch (e) {
    if (task.sendPort != null) {
      task.sendPort!.send({'type': 'error', 'message': e.toString()});
    }
  } finally {
    inputStream.close();
  }
}

Future<void> _extractWith7z(ExtractTask task) async {
  // Use 'e' (extract here) if flatten is true, otherwise 'x' (extract with full paths)
  final command = task.flatten ? 'e' : 'x';
  final args = [command, task.sourcePath, '-o${task.destinationPath}'];

  if (task.password != null && task.password!.isNotEmpty) {
    args.add('-p${task.password}');
  } else {
    args.add('-p-');
  }

  // Overwrite mode
  if (task.overwrite) {
    args.add('-aoa'); // Overwrite All
  } else {
    args.add('-aos'); // Skip existing
  }

  // Add selected files
  if (task.selectedFiles.isNotEmpty) {
    args.addAll(task.selectedFiles);
  }

  // Start process
  final executable = task.custom7zExecutable ?? '7z';
  final process = await Process.start(executable, args);

  // Parse stdout for progress
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
    if (line.trim().startsWith('Extracting')) {
      final filename = line.replaceAll('Extracting', '').trim();
      if (task.sendPort != null) {
        task.sendPort!.send({
          'type': 'progress',
          'filename': filename,
          'current': 0,
          'total': 0
        });
      }
    }
  });

  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    final stderr = await process.stderr.transform(utf8.decoder).join();
    throw Exception('7z exited with code $exitCode: $stderr');
  }

  if (task.sendPort != null) {
    task.sendPort!.send({'type': 'done'});
  }
}
