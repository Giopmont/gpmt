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
  final SendPort? sendPort;

  ExtractTask({
    required this.sourcePath,
    required this.destinationPath,
    required this.selectedFiles,
    required this.overwrite,
    this.sendPort,
  });
}

// Changed to return 'void' instead of 'Future<void>' to satisfy Isolate.spawn signature
void extractWorker(ExtractTask task) async {
  // Try using system 7z first for performance and large file support (Zip64)
  bool has7z = false;
  try {
    final result = await Process.run('which', ['7z']);
    has7z = result.exitCode == 0;
  } catch (e) {
    has7z = false;
  }

  if (has7z) {
    try {
      await _extractWith7z(task);
      return;
    } catch (e) {
      if (task.sendPort != null) {
        task.sendPort!.send({'type': 'error', 'message': '7z failed, falling back: $e'});
      }
      // Fallback to Dart implementation below
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

      final filename = file.name;
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
        Directory(destPath).createSync(recursive: true);
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
  final args = ['x', task.sourcePath, '-o${task.destinationPath}'];
  
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

  // Use -bsp1 for progress info if available, but standard output parsing is safer for generic 7z
  // args.add('-bsp1'); 
  
  // Start process
  final process = await Process.start('7z', args);
  
  // Parse stdout for progress
  // 7z output example: "Extracting  Folder/File.ext"
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
          'current': 0, // 7z doesn't give easy file count in this mode without pre-listing
          'total': 0    // indeterminate
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