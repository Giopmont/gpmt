import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Serviço responsável por localizar e verificar binários externos (7z, unrar).
/// Prioriza binários empacotados no app, com fallback para binários do sistema.
class BinaryLocator {
  static final BinaryLocator _instance = BinaryLocator._internal();
  factory BinaryLocator() => _instance;
  BinaryLocator._internal();

  String _sevenZipExecutable = '7z';
  String _unrarExecutable = 'unrar';
  String _rarExecutable = 'rar';
  bool _is7zAvailable = false;
  bool _isUnrarAvailable = false;
  bool _isRarAvailable = false;
  String _unrarErrorDetails = '';

  // Getters
  String get sevenZipExecutable => _sevenZipExecutable;
  String get unrarExecutable => _unrarExecutable;
  String get rarExecutable => _rarExecutable;
  bool get is7zAvailable => _is7zAvailable;
  bool get isUnrarAvailable => _isUnrarAvailable;
  bool get isRarAvailable => _isRarAvailable;
  String get unrarErrorDetails => _unrarErrorDetails;

  /// Inicializa a detecção de todos os binários.
  Future<void> initialize() async {
    await Future.wait([
      _check7zAvailability(),
      _checkUnrarAvailability(),
      _checkRarAvailability(),
    ]);
  }

  /// Verifica disponibilidade do 7z (bundled ou sistema).
  Future<void> _check7zAvailability() async {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final appDir = await getApplicationSupportDirectory();
        final bundledPath = p.join(appDir.path, '7z');
        final bundledFile = File(bundledPath);

        if (!bundledFile.existsSync()) {
          await _extractBundledBinary(
            assetPath: Platform.isMacOS
                ? 'assets/bin/macos/7z'
                : 'assets/bin/linux/7z',
            destPath: bundledPath,
            appDir: appDir,
          );
        }

        if (bundledFile.existsSync()) {
          final result = await Process.run(bundledPath, ['i']);
          if (result.exitCode == 0 || result.exitCode == 255) {
            _is7zAvailable = true;
            _sevenZipExecutable = bundledPath;
            debugPrint('7z encontrado (bundled): $bundledPath');
            return;
          }
        }
      } catch (e) {
        debugPrint('Erro ao verificar 7z bundled: $e');
      }
    }

    // Fallback para sistema
    try {
      final result = await Process.run('which', ['7z']);
      if (result.exitCode == 0) {
        _is7zAvailable = true;
        _sevenZipExecutable = '7z';
        debugPrint('7z encontrado (sistema)');
      }
    } catch (e) {
      debugPrint('7z não encontrado no sistema');
    }
  }

  /// Verifica disponibilidade do unrar (bundled ou sistema).
  Future<void> _checkUnrarAvailability() async {
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final appDir = await getApplicationSupportDirectory();
        final bundledPath = p.join(appDir.path, 'unrar');
        final bundledFile = File(bundledPath);

        if (!bundledFile.existsSync() || bundledFile.lengthSync() == 0) {
          await _extractBundledBinary(
            assetPath: Platform.isMacOS
                ? 'assets/bin/macos/unrar'
                : 'assets/bin/linux/unrar',
            destPath: bundledPath,
            appDir: appDir,
          );
        }

        if (bundledFile.existsSync()) {
          try {
            final result = await Process.run(bundledPath, []);
            if (result.exitCode == 0 ||
                result.exitCode == 7 ||
                result.stdout.toString().trim().isNotEmpty) {
              _isUnrarAvailable = true;
              _unrarExecutable = bundledPath;
              _unrarErrorDetails = '';
              debugPrint('unrar encontrado (bundled): $bundledPath');
              return;
            } else {
              _unrarErrorDetails =
                  'Falha na execução (código ${result.exitCode}). Stderr: ${result.stderr}';
            }
          } catch (e) {
            _unrarErrorDetails = 'Exceção na execução: $e';
            debugPrint('unrar bundled falhou no teste: $e');
          }
        }
      } catch (e) {
        _unrarErrorDetails = 'Erro geral: $e';
        debugPrint('Erro ao verificar unrar bundled: $e');
      }
    }

    // Fallback para sistema
    try {
      final result = await Process.run('which', ['unrar']);
      if (result.exitCode == 0) {
        _isUnrarAvailable = true;
        _unrarExecutable = 'unrar';
        _unrarErrorDetails = '';
        debugPrint('unrar encontrado (sistema)');
      } else {
        if (_unrarErrorDetails.isEmpty) {
          _unrarErrorDetails =
              'unrar não encontrado no sistema (which retornou ${result.exitCode})';
        }
      }
    } catch (e) {
      if (_unrarErrorDetails.isEmpty) {
        _unrarErrorDetails = 'Verificação do sistema falhou: $e';
      }
    }
  }

  /// Verifica disponibilidade do rar (via system path, pois é licença proprietária/shareware).
  Future<void> _checkRarAvailability() async {
    try {
      final result = await Process.run('which', ['rar']);
      if (result.exitCode == 0) {
        _isRarAvailable = true;
        _rarExecutable = 'rar';
        debugPrint('rar found (system)');
      }
    } catch (e) {
      debugPrint('rar not found in system');
    }
  }

  /// Extrai um binário dos assets para o diretório de suporte do app.
  Future<void> _extractBundledBinary({
    required String assetPath,
    required String destPath,
    required Directory appDir,
  }) async {
    try {
      final byteData = await rootBundle.load(assetPath);
      final buffer = byteData.buffer.asUint8List();

      if (!appDir.existsSync()) {
        appDir.createSync(recursive: true);
      }

      final destFile = File(destPath);
      await destFile.writeAsBytes(buffer);
      await Process.run('chmod', ['+x', destPath]);

      debugPrint('Binário extraído: $destPath');
    } catch (e) {
      debugPrint('Falha ao extrair binário $assetPath: $e');
      rethrow;
    }
  }

  /// Retorna instruções de instalação para o sistema atual.
  String getInstallInstructions() {
    if (Platform.isLinux) {
      return 'Instale via: sudo apt install p7zip-full unrar rar';
    } else if (Platform.isMacOS) {
      return 'Instale via: brew install p7zip unrar rar';
    }
    return 'Instale 7z e unrar no seu sistema.';
  }
}
