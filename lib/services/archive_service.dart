import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../models/archive_entry.dart';
import '../utils/constants.dart';
import '../worker.dart';
import 'archive_parser.dart';
import 'binary_locator.dart';

class ArchiveListResult {
  final List<ArchiveEntry> entries;
  final bool requiresPassword;
  final String? errorMessage;

  const ArchiveListResult({
    this.entries = const [],
    this.requiresPassword = false,
    this.errorMessage,
  });

  bool get isSuccess => errorMessage == null && !requiresPassword;
}

class ArchiveCommandResult {
  final bool isSuccess;
  final bool requiresPassword;
  final String? errorMessage;

  const ArchiveCommandResult({
    required this.isSuccess,
    this.requiresPassword = false,
    this.errorMessage,
  });
}

class ArchiveService {
  ArchiveService(this._binaryLocator);

  final BinaryLocator _binaryLocator;

  String commandOutput(ProcessResult result) {
    final stderr = result.stderr.toString().trim();
    final stdout = result.stdout.toString().trim();
    if (stderr.isNotEmpty && stdout.isNotEmpty) {
      return '$stderr\n$stdout';
    }
    return stderr.isNotEmpty ? stderr : stdout;
  }

  bool resultNeedsPassword(ProcessResult result) {
    final output = commandOutput(result).toLowerCase();
    return output.contains('enter password') ||
        output.contains('wrong password') ||
        output.contains('incorrect password') ||
        output.contains('encrypted headers') ||
        output.contains('encrypted archive') ||
        output.contains('password is incorrect');
  }

  bool errorNeedsPassword(String errorText) {
    return resultNeedsPassword(ProcessResult(0, 1, '', errorText));
  }

  Future<ArchiveListResult> listArchive({
    required String path,
    String? password,
  }) async {
    final ext = p.extension(path).toLowerCase();

    if (ext == '.rar') {
      return _listRarArchive(path: path, password: password);
    }

    if (ext == '.7z') {
      if (!_binaryLocator.is7zAvailable) {
        return ArchiveListResult(
          errorMessage:
              '${AppStrings.errorList7zUnavailable}\n\n${_binaryLocator.getInstallInstructions()}',
        );
      }
      return _listWith7z(path: path, password: password);
    }

    return _listWithArchivePackage(path);
  }

  Future<ArchiveListResult> _listRarArchive({
    required String path,
    String? password,
  }) async {
    if (_binaryLocator.is7zAvailable) {
      final result = await Process.run(
        _binaryLocator.sevenZipExecutable,
        ['l', '-slt', _sevenZipPasswordArg(password), path],
      );
      if (result.exitCode == 0) {
        return ArchiveListResult(
          entries: ArchiveParser.parse7zListing(result.stdout.toString())
              .where((entry) => entry.name != path)
              .toList(),
        );
      }

      if (resultNeedsPassword(result)) {
        return const ArchiveListResult(requiresPassword: true);
      }
    }

    if (!_binaryLocator.isUnrarAvailable) {
      return ArchiveListResult(
        errorMessage:
            "${AppStrings.errorRarToolUnavailable}\n\n${_binaryLocator.getInstallInstructions()}\n\n${_binaryLocator.unrarErrorDetails}",
      );
    }

    final result = await Process.run(
      _binaryLocator.unrarExecutable,
      ['l', '-c-', _unrarPasswordArg(password), path],
    );
    if (result.exitCode == 0) {
      return ArchiveListResult(
        entries: ArchiveParser.parseUnrarListing(result.stdout.toString())
            .where((entry) => entry.name != path)
            .toList(),
      );
    }

    if (resultNeedsPassword(result)) {
      return const ArchiveListResult(requiresPassword: true);
    }

    return ArchiveListResult(
      errorMessage:
          '${AppStrings.errorListRarFailed}: ${commandOutput(result)}',
    );
  }

  Future<ArchiveListResult> _listWith7z({
    required String path,
    String? password,
  }) async {
    final result = await Process.run(
      _binaryLocator.sevenZipExecutable,
      ['l', '-slt', _sevenZipPasswordArg(password), path],
    );
    if (result.exitCode == 0) {
      return ArchiveListResult(
        entries: ArchiveParser.parse7zListing(result.stdout.toString())
            .where((entry) => entry.name != path)
            .toList(),
      );
    }

    if (resultNeedsPassword(result)) {
      return const ArchiveListResult(requiresPassword: true);
    }

    return ArchiveListResult(
      errorMessage:
          '${AppStrings.errorListArchiveFailed}: ${commandOutput(result)}',
    );
  }

  ArchiveListResult _listWithArchivePackage(String path) {
    InputFileStream? inputStream;
    try {
      final ext = p.extension(path).toLowerCase();
      inputStream = InputFileStream(path);
      Archive archive;

      if (SupportedExtensions.isZip(path)) {
        archive = ZipDecoder().decodeBuffer(inputStream);
      } else if (ext == '.tar') {
        archive = TarDecoder().decodeBuffer(inputStream);
      } else if (ext == '.gz' || ext == '.tgz') {
        throw Exception(AppStrings.errorGzipPreviewUnavailable);
      } else {
        throw Exception('${AppStrings.errorUnsupportedFormat}: $ext');
      }

      return ArchiveListResult(
        entries: archive.files.map(ArchiveEntry.fromArchiveFile).toList(),
      );
    } catch (e) {
      return ArchiveListResult(errorMessage: e.toString());
    } finally {
      inputStream?.close();
    }
  }

  Future<ArchiveCommandResult> extractRar({
    required String sourceArchive,
    required String outputDir,
    required bool overwrite,
    required List<String> selectedFiles,
    String? password,
  }) async {
    if (!_binaryLocator.isUnrarAvailable) {
      return const ArchiveCommandResult(
        isSuccess: false,
        errorMessage: AppStrings.errorRarExtractionToolUnavailable,
      );
    }

    final args = ['x', _unrarPasswordArg(password), overwrite ? '-o+' : '-o-'];
    args.add(sourceArchive);
    if (selectedFiles.isNotEmpty) {
      args.addAll(selectedFiles);
    }
    args.add(outputDir);

    final result = await Process.run(_binaryLocator.unrarExecutable, args);
    if (result.exitCode == 0) {
      return const ArchiveCommandResult(isSuccess: true);
    }
    if (resultNeedsPassword(result)) {
      return const ArchiveCommandResult(
        isSuccess: false,
        requiresPassword: true,
      );
    }
    return ArchiveCommandResult(
      isSuccess: false,
      errorMessage:
          '${AppStrings.errorRarExtractionFailed}: ${commandOutput(result)}',
    );
  }

  Future<ArchiveCommandResult> extractWithWorker({
    required String sourceArchive,
    required String outputDir,
    required List<String> selectedFiles,
    required bool overwrite,
    required bool flatten,
    String? password,
    void Function(String filename, int current, int total)? onProgress,
  }) async {
    final receivePort = ReceivePort();
    final task = ExtractTask(
      sourcePath: sourceArchive,
      destinationPath: outputDir,
      selectedFiles: selectedFiles,
      overwrite: overwrite,
      useSystem7z: _binaryLocator.is7zAvailable,
      flatten: flatten,
      custom7zExecutable: _binaryLocator.sevenZipExecutable,
      password: password,
      sendPort: receivePort.sendPort,
    );

    await Isolate.spawn(extractWorker, task);

    Object? extractionError;
    await for (final message in receivePort) {
      if (message is! Map) {
        continue;
      }

      if (message['type'] == 'progress') {
        onProgress?.call(
          message['filename']?.toString() ?? '',
          message['current'] as int? ?? 0,
          message['total'] as int? ?? 0,
        );
        continue;
      }

      if (message['type'] == 'done') {
        break;
      }

      if (message['type'] == 'error') {
        extractionError = message['message'];
        break;
      }
    }
    receivePort.close();

    if (extractionError == null) {
      return const ArchiveCommandResult(isSuccess: true);
    }

    final errorText = extractionError.toString();
    if (SupportedExtensions.is7z(sourceArchive) && errorNeedsPassword(errorText)) {
      return const ArchiveCommandResult(
        isSuccess: false,
        requiresPassword: true,
      );
    }

    return ArchiveCommandResult(
      isSuccess: false,
      errorMessage: errorText,
    );
  }

  Future<ArchiveCommandResult> deleteFromArchive({
    required String archivePath,
    required List<String> filesToDelete,
  }) async {
    final ext = p.extension(archivePath).toLowerCase();
    late final ProcessResult result;

    if (ext == '.rar') {
      if (!_binaryLocator.isRarAvailable) {
        return const ArchiveCommandResult(
          isSuccess: false,
          errorMessage: AppStrings.errorRarDeleteToolUnavailable,
        );
      }
      result = await Process.run(
        _binaryLocator.rarExecutable,
        ['d', archivePath, ...filesToDelete],
      );
    } else {
      if (!_binaryLocator.is7zAvailable) {
        return const ArchiveCommandResult(
          isSuccess: false,
          errorMessage: AppStrings.error7zDeleteToolUnavailable,
        );
      }
      result = await Process.run(
        _binaryLocator.sevenZipExecutable,
        ['d', archivePath, ...filesToDelete],
      );
    }

    if (result.exitCode == 0) {
      return const ArchiveCommandResult(isSuccess: true);
    }

    return ArchiveCommandResult(
      isSuccess: false,
      errorMessage: result.stderr.toString().trim(),
    );
  }

  Future<ArchiveCommandResult> addFilesToArchive({
    required String archivePath,
    required List<String> files,
    required String archiveVirtualPath,
  }) async {
    final ext = p.extension(archivePath).toLowerCase();
    late final ProcessResult result;

    if (ext == '.rar') {
      if (!_binaryLocator.isRarAvailable) {
        return const ArchiveCommandResult(
          isSuccess: false,
          errorMessage: AppStrings.errorRarAddToolUnavailable,
        );
      }

      final args = ['a', '-ep1'];
      if (archiveVirtualPath.isNotEmpty) {
        var destPath = archiveVirtualPath;
        if (destPath.endsWith('/')) {
          destPath = destPath.substring(0, destPath.length - 1);
        }
        args.add('-ap$destPath');
      }
      args.add(archivePath);
      args.addAll(files);
      result = await Process.run(_binaryLocator.rarExecutable, args);
    } else {
      if (!_binaryLocator.is7zAvailable) {
        return const ArchiveCommandResult(
          isSuccess: false,
          errorMessage: AppStrings.error7zAddToolUnavailable,
        );
      }

      result = await _addFilesWith7z(
        archivePath: archivePath,
        files: files,
        archiveVirtualPath: archiveVirtualPath,
      );
    }

    if (result.exitCode == 0) {
      return const ArchiveCommandResult(isSuccess: true);
    }

    return ArchiveCommandResult(
      isSuccess: false,
      errorMessage: result.stderr.toString().trim(),
    );
  }

  Future<ProcessResult> _addFilesWith7z({
    required String archivePath,
    required List<String> files,
    required String archiveVirtualPath,
  }) async {
    if (archiveVirtualPath.isNotEmpty) {
      final tempDir = await Directory.systemTemp.createTemp('gpmt_add_');
      try {
        final destDir = Directory(p.join(tempDir.path, archiveVirtualPath));
        await destDir.create(recursive: true);

        for (final filePath in files) {
          final file = File(filePath);
          if (await file.exists()) {
            await file.copy(p.join(destDir.path, p.basename(filePath)));
          }
        }

        return Process.run(
          _binaryLocator.sevenZipExecutable,
          ['a', archivePath, '.'],
          workingDirectory: tempDir.path,
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    }

    if (files.isEmpty) {
      return ProcessResult(0, 0, '', '');
    }

    final workDir = File(files.first).parent.path;
    final basenames = files.map(p.basename).toList();
    return Process.run(
      _binaryLocator.sevenZipExecutable,
      ['a', archivePath, ...basenames],
      workingDirectory: workDir,
    );
  }

  Future<void> createZipArchive({
    required String outputFile,
    required Iterable<String> files,
  }) async {
    final encoder = ZipFileEncoder();
    encoder.create(outputFile);
    try {
      for (final path in files) {
        if (FileSystemEntity.isDirectorySync(path)) {
          encoder.addDirectory(Directory(path));
        } else if (FileSystemEntity.isFileSync(path)) {
          encoder.addFile(File(path));
        }
      }
    } finally {
      encoder.close();
    }
  }

  Future<void> createArchiveFromFiles({
    required String outputFile,
    required List<String> files,
  }) async {
    if (_binaryLocator.is7zAvailable) {
      final result = await Process.run(
        _binaryLocator.sevenZipExecutable,
        ['a', outputFile, ...files],
      );
      if (result.exitCode != 0) {
        throw Exception(commandOutput(result));
      }
      return;
    }

    await createZipArchive(outputFile: outputFile, files: files);
  }

  Future<ArchiveCommandResult> repairArchive(String path) async {
    if (!_binaryLocator.isRarAvailable) {
      return const ArchiveCommandResult(
        isSuccess: false,
        errorMessage: AppStrings.errorRarRepairToolUnavailable,
      );
    }

    final result = await Process.run(_binaryLocator.rarExecutable, ['r', path]);
    if (result.exitCode == 0) {
      return const ArchiveCommandResult(isSuccess: true);
    }

    return ArchiveCommandResult(
      isSuccess: false,
      errorMessage: commandOutput(result),
    );
  }

  String _sevenZipPasswordArg(String? password) {
    if (password == null || password.isEmpty) {
      return '-p-';
    }
    return '-p$password';
  }

  String _unrarPasswordArg(String? password) {
    if (password == null || password.isEmpty) {
      return '-p-';
    }
    return '-p$password';
  }
}
