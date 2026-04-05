import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:filesize/filesize.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:open_filex/open_filex.dart';
import 'services/binary_locator.dart';
import 'services/archive_service.dart';
import 'models/archive_entry.dart';
import 'utils/icon_helper.dart';
import 'utils/constants.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(GpmtApp(args: args));
}

// Singleton para localização de binários
final _binaryLocator = BinaryLocator();
final _archiveService = ArchiveService(_binaryLocator);

class GpmtApp extends StatelessWidget {
  final List<String> args;
  final bool enableBackgroundInit;
  const GpmtApp({
    super.key,
    this.args = const [],
    this.enableBackgroundInit = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Segoe UI', // Attempt to look like Windows
        scaffoldBackgroundColor: const Color(0xFFF0F0F0),
      ),
      home: GpmtMainScreen(
        args: args,
        enableBackgroundInit: enableBackgroundInit,
      ),
    );
  }
}

class GpmtMainScreen extends StatefulWidget {
  final List<String> args;
  final bool enableBackgroundInit;
  const GpmtMainScreen({
    super.key,
    this.args = const [],
    this.enableBackgroundInit = false,
  });

  @override
  State<GpmtMainScreen> createState() => _GpmtMainScreenState();
}

// RarEntry foi movido para models/archive_entry.dart como ArchiveEntry

class _GpmtMainScreenState extends State<GpmtMainScreen> {
  late String _currentPath;
  List<FileSystemEntity> _files = [];
  final Set<String> _selectedPaths = {};

  // Cache de stats para evitar múltiplas chamadas statSync()
  final Map<String, FileStat> _statsCache = {};

  // Archive viewing state
  bool _isViewingArchive = false;
  String? _archivePath;
  String? _archivePassword;
  List<ArchiveEntry> _allArchiveEntries = []; // Todas as entradas do arquivo
  List<ArchiveEntry> _currentArchiveEntries =
      []; // Entradas filtradas pelo nível atual
  String _archiveVirtualPath =
      ''; // Caminho virtual dentro do arquivo (ex: "pasta1/subpasta/")
  // Temp dir for drag-and-drop cache
  Directory? _sessionTempDir;

  // Workaround: delay DropRegion until Flutter engine is fully ready
  // Fixes crash in release mode where FlutterView is nil during early initialization
  bool _dropRegionReady = false;

  // Sorting
  int _sortColumn = 0; // 0=Name, 1=Created, 2=Modified, 3=Type, 4=Size
  bool _sortAscending = true;

  // Larguras das colunas (redimensionáveis)
  double _colWidthName = AppSizes.colWidthName;
  double _colWidthCreated = AppSizes.colWidthCreated;
  double _colWidthModified = AppSizes.colWidthModified;
  double _colWidthType = AppSizes.colWidthType;
  final double _colWidthSize = AppSizes.colWidthSize;

  // Scroll controller para sincronizar header e body
  final ScrollController _headerScrollController = ScrollController();

  static const _fileHandlerChannel = MethodChannel('com.gpmt/file_handler');

  @override
  void initState() {
    super.initState();

    // Initialize _currentPath to user's home directory
    _currentPath = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    debugPrint('Initial _currentPath: $_currentPath');
    debugPrint(
        'GPMT Version: 1.0.2 (Race Fix) - Build Time: ${DateTime.now()}');

    _createSessionTempDir();
    _refreshFiles();
    _setupFileHandlerChannel();

    // Start initialization sequence
    if (widget.enableBackgroundInit) {
      _initApp();
    } else {
      _dropRegionReady = true;
    }
  }

  Future<void> _initApp() async {
    // Inicializar localizador de binários
    await _binaryLocator.initialize();

    // Processar argumentos (requisições de abertura de arquivo)
    if (mounted) {
      _processArgs();
    }

    // Delay DropRegion initialization to avoid crash in release mode
    // The super_native_extensions plugin crashes if FlutterView is not ready
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() {
        _dropRegionReady = true;
      });
    }
  }

  void _setupFileHandlerChannel() {
    debugPrint('Setting up file handler channel');
    _fileHandlerChannel.setMethodCallHandler((call) async {
      debugPrint('=== File Handler Channel ===');
      debugPrint('Method: ${call.method}');
      debugPrint('Arguments: ${call.arguments}');

      if (call.method == 'openFile') {
        final filePath = call.arguments as String;
        debugPrint('Opening file from native: $filePath');
        _navigateTo(filePath);
      }
    });
  }

  // Desabilitado: usando AppDelegate nativo em vez de plugin de deep link.
  /*
  void _initDeepLinks() {
    // Handle deep links / file open requests (macOS)
    _appLinks.uriLinkStream.listen(_handleIncomingUri, onError: (err) {
      debugPrint('Deep link error: $err');
    });
    _appLinks.stringLinkStream.listen((link) {
      _handleIncomingString(link);
    }, onError: (err) {
      debugPrint('Deep link string error: $err');
    });

    // Also handle the initial link when the app is cold-started from a file open
    _appLinks.getInitialLink().then((uri) {
      if (!mounted || uri == null) return;
      _handleIncomingUri(uri);
    }).catchError((err) {
      debugPrint('Initial link error: $err');
    });
    _appLinks.getInitialLinkString().then((link) {
      if (!mounted || link == null) return;
      _handleIncomingString(link);
    }).catchError((err) {
      debugPrint('Initial link string error: $err');
    });
  }

  void _handleIncomingUri(Uri uri) {
    debugPrint('=== GPMT Deep Link URI ===');
    debugPrint('URI: $uri');
    debugPrint('Scheme: ${uri.scheme}');

    if (!mounted) return;

    // Prefer file:// URIs for macOS "open with" flows
    if (uri.scheme == 'file') {
      final path = uri.toFilePath();
      debugPrint('File path: $path');
      if (path.isNotEmpty) {
        _navigateTo(path);
      }
      return;
    }

    // Fallback: treat plain paths (no scheme) as file paths
    if (uri.scheme.isEmpty && uri.toString().isNotEmpty) {
      debugPrint('Plain path: ${uri.toString()}');
      _navigateTo(uri.toString());
    }
  }

  void _handleIncomingString(String link) {
    debugPrint('=== GPMT Deep Link String ===');
    debugPrint('Link: $link');

    if (!mounted || link.isEmpty) return;
    try {
      final uri = Uri.parse(link);
      if (uri.scheme.isNotEmpty) {
        _handleIncomingUri(uri);
        return;
      }
    } catch (_) {
      // Not a URI, treat as path
    }
    debugPrint('Treating as direct path: $link');
    _navigateTo(link);
  }
  */

  void _processArgs() {
    debugPrint('=== GPMT Args Debug ===');
    debugPrint('Args count: ${widget.args.length}');
    debugPrint('Args: ${widget.args}');
    debugPrint('Current directory: ${Directory.current.path}');

    if (widget.args.isEmpty) {
      debugPrint('No args received - relying on deep links');
      return;
    }

    // Simple parser:
    // gpmt <file> -> Open
    // gpmt --extract <file> -> Extract dialog

    String? targetFile;
    bool extractMode = false;

    for (int i = 0; i < widget.args.length; i++) {
      final arg = widget.args[i];
      debugPrint('Processing arg[$i]: $arg');
      if (arg == '--extract' || arg == '-e') {
        extractMode = true;
      } else if (!arg.startsWith('-')) {
        targetFile = arg;
      }
    }

    debugPrint('Target file: $targetFile');

    if (targetFile != null && targetFile.isNotEmpty) {
      // Just navigate to the file/directory - _navigateTo will handle it correctly
      debugPrint('Navigating to: $targetFile');
      _navigateTo(targetFile);

      if (extractMode) {
        // Future improvement: Trigger extraction dialog automatically
        // Future.delayed(Duration(seconds: 1), () => _extractSelected());
      }
    }
  }

  void _createSessionTempDir() {
    try {
      _sessionTempDir = Directory.systemTemp.createTempSync('winrar_session_');
    } catch (e) {
      // Handle error
    }
  }

  // Métodos _check7zAvailability e _checkUnrarAvailability movidos para BinaryLocator

  /// Obtém stats do cache ou carrega e armazena no cache.
  FileStat _getCachedStat(FileSystemEntity entity) {
    return _statsCache.putIfAbsent(entity.path, () {
      try {
        return entity.statSync();
      } catch (_) {
        return Directory.systemTemp.statSync();
      }
    });
  }

  /// Filtra as entradas do arquivo para mostrar apenas o nível atual.
  /// Mostra apenas itens do diretório virtual atual dentro do compactado.
  void _filterArchiveEntriesToCurrentLevel() {
    if (!_isViewingArchive) return;

    final Set<String> seenNames = {};
    final List<ArchiveEntry> filtered = [];

    for (final entry in _allArchiveEntries) {
      String entryPath = entry.name;

      // Normalizar path (remover trailing slash se existir)
      if (entryPath.endsWith('/')) {
        entryPath = entryPath.substring(0, entryPath.length - 1);
      }

      // Se estamos em um subdiretório, verificar se a entrada começa com esse caminho
      if (_archiveVirtualPath.isNotEmpty) {
        if (!entryPath.startsWith(_archiveVirtualPath)) {
          continue; // Entrada não está no diretório atual
        }
        // Remover o prefixo do caminho virtual
        entryPath = entryPath.substring(_archiveVirtualPath.length);
      }

      // Se o caminho ainda contém '/', significa que está em um subdiretório
      final slashIndex = entryPath.indexOf('/');
      if (slashIndex > 0) {
        // É um item dentro de uma subpasta - criar entrada de pasta virtual
        final folderName = entryPath.substring(0, slashIndex);
        if (!seenNames.contains(folderName)) {
          seenNames.add(folderName);
          // Criar entrada de pasta virtual
          filtered.add(ArchiveEntry(
            name: folderName,
            size: 0,
            isDirectory: true,
          ));
        }
      } else if (entryPath.isNotEmpty) {
        // Item no nível atual
        if (!seenNames.contains(entryPath)) {
          seenNames.add(entryPath);
          // Criar entrada com nome ajustado (apenas o basename)
          filtered.add(ArchiveEntry(
            name: entryPath,
            size: entry.size,
            dateModified: entry.dateModified,
            dateCreated: entry.dateCreated,
            isDirectory: entry.isDirectory,
            compressionMethod: entry.compressionMethod,
            compressedSize: entry.compressedSize,
          ));
        }
      }
    }

    _currentArchiveEntries = filtered;
  }

  /// Navega para um subdiretório dentro do arquivo compactado.
  void _navigateIntoArchiveFolder(String folderName) {
    setState(() {
      _archiveVirtualPath = '$_archiveVirtualPath$folderName/';
      _filterArchiveEntriesToCurrentLevel();
      _sortFiles();
      _selectedPaths.clear();
    });
  }

  /// Obtém o caminho completo de um item dentro do arquivo (incluindo o caminho virtual).
  String _getFullArchivePath(String itemName) {
    return '$_archiveVirtualPath$itemName';
  }

  /// Navega para cima dentro do arquivo compactado.
  void _navigateUpInArchive() {
    if (_archiveVirtualPath.isEmpty) {
      // Já está na raiz do arquivo, sair do arquivo
      setState(() {
        _isViewingArchive = false;
        _currentPath = p.dirname(_archivePath!);
        _archivePath = null;
        _archivePassword = null;
        _allArchiveEntries = [];
        _currentArchiveEntries = [];
        _archiveVirtualPath = '';
      });
      _refreshFiles();
    } else {
      // Voltar um nível dentro do arquivo
      setState(() {
        // Remover último segmento do caminho
        String path = _archiveVirtualPath;
        if (path.endsWith('/')) {
          path = path.substring(0, path.length - 1);
        }
        final lastSlash = path.lastIndexOf('/');
        if (lastSlash >= 0) {
          _archiveVirtualPath = path.substring(0, lastSlash + 1);
        } else {
          _archiveVirtualPath = '';
        }
        _filterArchiveEntriesToCurrentLevel();
        _sortFiles();
        _selectedPaths.clear();
      });
    }
  }

  void _sortFiles() {
    if (_isViewingArchive) {
      _currentArchiveEntries.sort((a, b) {
        // Pastas sempre primeiro
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;

        int cmp = 0;
        switch (_sortColumn) {
          case 0: // Nome
            cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
            break;
          case 1: // Criado
            final dtA = a.dateCreated ?? DateTime.fromMillisecondsSinceEpoch(0);
            final dtB = b.dateCreated ?? DateTime.fromMillisecondsSinceEpoch(0);
            cmp = dtA.compareTo(dtB);
            break;
          case 2: // Modificado
            final dtA =
                a.dateModified ?? DateTime.fromMillisecondsSinceEpoch(0);
            final dtB =
                b.dateModified ?? DateTime.fromMillisecondsSinceEpoch(0);
            cmp = dtA.compareTo(dtB);
            break;
          case 3: // Tipo
            cmp = a.extension.compareTo(b.extension);
            break;
          case 4: // Tamanho
            cmp = a.size.compareTo(b.size);
            break;
        }

        return _sortAscending ? cmp : -cmp;
      });
    } else {
      _files.sort((a, b) {
        bool isDirA = a is Directory;
        bool isDirB = b is Directory;

        if (isDirA && !isDirB) return -1;
        if (!isDirA && isDirB) return 1;

        // Usar cache de stats
        final statA = _getCachedStat(a);
        final statB = _getCachedStat(b);

        int cmp = 0;
        switch (_sortColumn) {
          case 0: // Nome
            cmp = p
                .basename(a.path)
                .toLowerCase()
                .compareTo(p.basename(b.path).toLowerCase());
            break;
          case 1: // Criado (Changed)
            cmp = statA.changed.compareTo(statB.changed);
            break;
          case 2: // Modificado
            cmp = statA.modified.compareTo(statB.modified);
            break;
          case 3: // Tipo
            cmp = p
                .extension(a.path)
                .toLowerCase()
                .compareTo(p.extension(b.path).toLowerCase());
            break;
          case 4: // Tamanho
            final sizeA = isDirA ? 0 : statA.size;
            final sizeB = isDirB ? 0 : statB.size;
            cmp = sizeA.compareTo(sizeB);
            break;
        }
        return _sortAscending ? cmp : -cmp;
      });
    }
  }

  void _onColumnHeaderTap(int index) {
    setState(() {
      if (_sortColumn == index) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = index;
        _sortAscending = true;
      }
      _sortFiles();
    });
  }

  @override
  void dispose() {
    _cleanupSessionTempDir();
    _headerScrollController.dispose();
    super.dispose();
  }

  void _cleanupSessionTempDir() {
    try {
      if (_sessionTempDir != null && _sessionTempDir!.existsSync()) {
        _sessionTempDir!.deleteSync(recursive: true);
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  void _refreshFiles() {
    if (_isViewingArchive) {
      // Em modo arquivo, não atualiza do disco
      return;
    }

    final dir = Directory(_currentPath);
    try {
      if (dir.existsSync()) {
        final entities = dir.listSync();
        setState(() {
          _files = entities;
          _statsCache.clear(); // Limpar cache ao atualizar
          _sortFiles();
          _selectedPaths.clear();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppStrings.errorAccessDirectory}: $e')),
      );
    }
  }

  void _navigateTo(String path) {
    debugPrint('=== _navigateTo called ===');
    debugPrint('Path: $path');
    debugPrint('Is archive: ${_isArchive(path)}');

    // Check if it's a supported archive
    if (_isArchive(path)) {
      debugPrint('Opening as archive');
      _openArchive(path);
      return;
    }

    final dir = Directory(path);
    final exists = dir.existsSync();
    debugPrint('Directory exists: $exists');

    if (exists) {
      setState(() {
        _currentPath = path;
        _isViewingArchive = false;
        _archivePath = null;
        _archivePassword = null;
        _allArchiveEntries = [];
        _currentArchiveEntries = [];
        _archiveVirtualPath = '';
      });
      _refreshFiles();
    } else {
      debugPrint('Path does not exist as directory, checking if file...');
      final file = File(path);
      if (file.existsSync()) {
        debugPrint('File exists but not recognized as archive');
      } else {
        debugPrint('Path does not exist: $path');
      }
    }
  }

  void _navigateUp() {
    if (_isViewingArchive) {
      _navigateUpInArchive();
    } else {
      final parent = Directory(_currentPath).parent;
      if (parent.path != _currentPath) {
        _navigateTo(parent.path);
      }
    }
  }

  bool _isArchive(String path) {
    return SupportedExtensions.isArchive(path);
  }

  Future<String?> _promptArchivePassword({
    required String archivePath,
    bool retry = false,
  }) async {
    if (!mounted) return null;

    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          retry ? AppStrings.incorrectPassword : AppStrings.archiveProtected,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              retry
                  ? AppStrings.promptArchivePasswordRetry
                  : AppStrings.promptArchivePassword,
            ),
            const SizedBox(height: 8),
            Text(
              p.basename(archivePath),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: AppStrings.password,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                final trimmed = value.trim();
                Navigator.pop(ctx, trimmed.isEmpty ? null : value);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text(AppStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text;
              final trimmed = value.trim();
              Navigator.pop(ctx, trimmed.isEmpty ? null : value);
            },
            child: const Text(AppStrings.continueLabel),
          ),
        ],
      ),
    );
  }

  void _applyOpenedArchive({
    required String path,
    required List<ArchiveEntry> entries,
    String? password,
  }) {
    setState(() {
      _isViewingArchive = true;
      _archivePath = path;
      _archivePassword = password;
      _allArchiveEntries = entries;
      _archiveVirtualPath = '';
      _selectedPaths.clear();
    });
    _filterArchiveEntriesToCurrentLevel();
    _sortFiles();
  }

  Future<void> _openArchive(String path) async {
    String? password = path == _archivePath ? _archivePassword : null;

    while (true) {
      final result = await _archiveService.listArchive(
        path: path,
        password: password,
      );

      if (result.isSuccess) {
        _applyOpenedArchive(
          path: path,
          entries: result.entries,
          password: password,
        );
        return;
      }

      if (!result.requiresPassword) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppStrings.errorOpenArchive),
            content: Text(result.errorMessage ?? AppStrings.errorGeneric),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(AppStrings.ok),
              )
            ],
          ),
        );
        return;
      }

      final nextPassword = await _promptArchivePassword(
        archivePath: path,
        retry: password != null && password.isNotEmpty,
      );
      if (nextPassword == null) {
        return;
      }
      password = nextPassword;
    }
  }

  void _toggleSelection(String name) {
    // Changed parameter from path to name for archive entries
    setState(() {
      if (_selectedPaths.contains(name)) {
        _selectedPaths.remove(name);
      } else {
        _selectedPaths.add(name);
      }
    });
  }

  Future<void> _extractSelected() async {
    if (!_isViewingArchive && _selectedPaths.isEmpty) return;

    String? sourceArchive = _archivePath;
    if (!_isViewingArchive) {
      if (_selectedPaths.length == 1 && _isArchive(_selectedPaths.first)) {
        sourceArchive = _selectedPaths.first;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(AppStrings.errorSelectSingleArchiveToExtract),
            ),
          );
        }
        return;
      }
    }

    if (sourceArchive == null) return;

    // Extraction Dialog
    String defaultName = p.basenameWithoutExtension(sourceArchive);
    String parentDir = p.dirname(sourceArchive);
    String defaultDest = p.join(parentDir, defaultName);

    final String? outputDir = await showDialog<String>(
        context: context,
        builder: (context) {
          final TextEditingController controller =
              TextEditingController(text: defaultDest);
          return AlertDialog(
            title: const Text(AppStrings.extractTo),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(AppStrings.destinationPath),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.folder_open),
                      onPressed: () async {
                        String? selected =
                            await FilePicker.platform.getDirectoryPath();
                        controller.text = selected ?? controller.text;
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text(AppStrings.cancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text(AppStrings.extract),
              ),
            ],
          );
        });

    if (outputDir == null) return;

    // Ask for overwrite preference upfront for all formats
    if (!mounted) return;
    final bool? overwriteChoice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.extractOptions),
        content: const Text('Como os arquivos existentes devem ser tratados?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text(AppStrings.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(AppStrings.skipExisting)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(AppStrings.overwriteAll)),
        ],
      ),
    );

    if (overwriteChoice == null) return;

    final initialPassword =
        sourceArchive == _archivePath ? _archivePassword : null;

    // Check RAR
    if (p.extension(sourceArchive).toLowerCase() == '.rar') {
      if (!_binaryLocator.isUnrarAvailable) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text(AppStrings.unrarNotFound),
              content: const Text(AppStrings.errorRarExtractionToolUnavailable),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(AppStrings.ok))
              ],
            ),
          );
        }
        return;
      }

      bool loadingVisible = false;
      String? password = initialPassword;

      while (true) {
        try {
          if (mounted && !loadingVisible) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) =>
                  const Center(child: CircularProgressIndicator()),
            );
            loadingVisible = true;
          }

          final result = await _archiveService.extractRar(
            sourceArchive: sourceArchive,
            outputDir: outputDir,
            overwrite: overwriteChoice,
            selectedFiles: _isViewingArchive && _selectedPaths.isNotEmpty
                ? _selectedPaths.map(_getFullArchivePath).toList()
                : const [],
            password: password,
          );

          if (loadingVisible && mounted) {
            Navigator.pop(context);
            loadingVisible = false;
          }

          if (result.isSuccess) {
            _archivePassword =
                (password != null && password.isNotEmpty) ? password : null;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${AppStrings.extractionSucceededRar} $outputDir',
                  ),
                ),
              );
            }
            break;
          }

          if (result.requiresPassword) {
            final nextPassword = await _promptArchivePassword(
              archivePath: sourceArchive,
              retry: password != null && password.isNotEmpty,
            );
            if (nextPassword == null) {
              return;
            }
            password = nextPassword;
            continue;
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result.errorMessage ?? AppStrings.errorRarExtractionFailed,
                ),
              ),
            );
          }
          return;
        } catch (e) {
          if (loadingVisible && mounted) {
            Navigator.pop(context);
            loadingVisible = false;
          }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.errorRarExtractionFailed}: $e')),
        );
      }
          return;
        }
      }
      return;
    }

    // Other archive types extraction (Zip/Tar) via Isolate
    final selectedFiles = (_isViewingArchive && _selectedPaths.isNotEmpty)
        ? _selectedPaths.map((name) => _getFullArchivePath(name)).toList()
        : <String>[];

    // Progress State
    ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
    ValueNotifier<String> statusNotifier = ValueNotifier(AppStrings.preparing);

    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: Dialog(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(AppStrings.extracting,
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (context, value, child) => LinearProgressIndicator(
                        value: value > 0 ? value : null),
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<String>(
                    valueListenable: statusNotifier,
                    builder: (context, value, child) => Text(value,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    String? password =
        SupportedExtensions.is7z(sourceArchive) ? initialPassword : null;

    try {
      while (true) {
        final result = await _archiveService.extractWithWorker(
          sourceArchive: sourceArchive,
          outputDir: outputDir,
          selectedFiles: selectedFiles,
          overwrite: overwriteChoice,
          flatten: false,
          password: password,
          onProgress: (filename, current, total) {
            statusNotifier.value =
                '${AppStrings.extracting} $filename ($current/$total)';
            if (total > 0) {
              progressNotifier.value = current / total;
            }
          },
        );

        if (result.isSuccess) {
          _archivePassword =
              (password != null && password.isNotEmpty) ? password : null;
          break;
        }

        if (result.requiresPassword) {
          if (mounted) {
            Navigator.pop(context);
          }

          final nextPassword = await _promptArchivePassword(
            archivePath: sourceArchive,
            retry: password != null && password.isNotEmpty,
          );
          if (nextPassword == null) {
            return;
          }

          password = nextPassword;
          progressNotifier.value = 0.0;
          statusNotifier.value = AppStrings.preparing;

          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => PopScope(
                canPop: false,
                child: Dialog(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(AppStrings.extracting,
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        ValueListenableBuilder<double>(
                          valueListenable: progressNotifier,
                          builder: (context, value, child) =>
                              LinearProgressIndicator(
                                  value: value > 0 ? value : null),
                        ),
                        const SizedBox(height: 10),
                        ValueListenableBuilder<String>(
                          valueListenable: statusNotifier,
                          builder: (context, value, child) => Text(value,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
          continue;
        }

        throw Exception(result.errorMessage ?? AppStrings.errorExtraction);
      }

      if (mounted) Navigator.pop(context); // Close loading

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppStrings.extractionSucceeded} $outputDir'),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.errorExtraction}: $e')),
        );
      }
    }
  }

  Future<void> _addToArchive() async {
    if (_selectedPaths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.errorSelectFilesToArchive)),
        );
      }
      return;
    }

    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: AppStrings.saveArchiveAs,
      fileName: 'archive.zip',
    );

    if (outputFile == null) return;

    try {
      await _archiveService.createZipArchive(
        outputFile: outputFile,
        files: _selectedPaths,
      );

      _refreshFiles(); // Refresh current view to show new file if in same dir
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppStrings.archiveCreated}: $outputFile'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.errorCreateArchiveFailed}: $e')),
        );
      }
    }
  }

  void _deleteSelected() {
    if (_selectedPaths.isEmpty) return;

    // Confirmation dialog
    if (mounted) {
      showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text(AppStrings.deleteFiles),
                content: const Text(AppStrings.deleteFilesConfirmation),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(AppStrings.cancel)),
                  TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _performDelete();
                      },
                      child: const Text(AppStrings.yes)),
                ],
              ));
    }
  }

  Future<String?> _extractFileForDrag(ArchiveEntry entry) async {
    if (_archivePath == null) return null;

    try {
      final tempDir = _sessionTempDir ??
          Directory.systemTemp.createTempSync('winrar_drag_');

      if (entry.isDirectory) return null;

      // Obter o caminho completo do arquivo dentro do arquivo
      final fullEntryPath = _getFullArchivePath(entry.name);

      final destPath = p.join(tempDir.path, p.basename(entry.name));
      final destFile = File(destPath);

      // Cache hit - arquivo já extraído
      if (destFile.existsSync()) {
        return destPath;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(AppStrings.preparingDrag),
            duration: Duration(milliseconds: 500),
          ),
        );
      }

      // RAR usa unrar diretamente
      if (SupportedExtensions.isRar(_archivePath!)) {
        String? password = _archivePassword;
        while (true) {
          final result = await _archiveService.extractRar(
            sourceArchive: _archivePath!,
            outputDir: tempDir.path,
            overwrite: true,
            selectedFiles: [fullEntryPath],
            password: password,
          );

          if (result.isSuccess && destFile.existsSync()) {
            _archivePassword =
                (password != null && password.isNotEmpty) ? password : null;
            return destPath;
          }

          if (!result.requiresPassword) {
            return null;
          }

          final nextPassword = await _promptArchivePassword(
            archivePath: _archivePath!,
            retry: password != null && password.isNotEmpty,
          );
          if (nextPassword == null) {
            return null;
          }
          password = nextPassword;
        }
      }

      // Outros formatos usam Isolate
      String? password =
          SupportedExtensions.is7z(_archivePath!) ? _archivePassword : null;

      while (true) {
        final result = await _archiveService.extractWithWorker(
          sourceArchive: _archivePath!,
          outputDir: tempDir.path,
          selectedFiles: [fullEntryPath],
          overwrite: true,
          flatten: true,
          password: password,
        );

        if (result.isSuccess) {
          _archivePassword =
              (password != null && password.isNotEmpty) ? password : null;
          return destPath;
        }

        if (!result.requiresPassword) {
          throw Exception(result.errorMessage ?? AppStrings.errorExtraction);
        }

        final nextPassword = await _promptArchivePassword(
          archivePath: _archivePath!,
          retry: password != null && password.isNotEmpty,
        );
        if (nextPassword == null) {
          return null;
        }
        password = nextPassword;
      }
    } catch (e) {
      debugPrint('Erro ao extrair para drag: $e');
    }
    return null;
  }

  void _showWizard() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text(AppStrings.wizardTitle),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _extractSelected();
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(Icons.unarchive, color: Colors.blue),
                  SizedBox(width: 12),
                  Text(AppStrings.wizardExtract),
                ],
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _addToArchive();
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Icon(Icons.archive, color: Colors.green),
                  SizedBox(width: 12),
                  Text(AppStrings.wizardCreate),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfo() {
    String title = AppStrings.infoTitle;
    List<Widget> details = [];

    if (_selectedPaths.isEmpty) {
      // Show info about current directory/archive
      title = _isViewingArchive
          ? AppStrings.archiveInfoTitle
          : AppStrings.folderInfoTitle;
      details.add(Text(
        '${AppStrings.infoPath}: ${_isViewingArchive ? _archivePath : _currentPath}',
      ));
      details.add(const SizedBox(height: 8));

      int count =
          _isViewingArchive ? _currentArchiveEntries.length : _files.length;
      details.add(
        Text('${AppStrings.infoContains}: $count ${AppStrings.infoItems}'),
      );

      // Calcular tamanho total
      int totalSize = 0;
      if (_isViewingArchive) {
        for (var e in _currentArchiveEntries) {
          totalSize += e.size;
        }
        details.add(Text('${AppStrings.infoTotalSize}: ${filesize(totalSize)}'));
      }
    } else {
      // Informações da seleção
      title = AppStrings.typeSelectedDetails;
      details.add(
        Text('${AppStrings.infoSelected}: ${_selectedPaths.length} ${AppStrings.infoItems}'),
      );
      details.add(const Divider());

      if (_selectedPaths.length == 1) {
        String path = _selectedPaths.first;
        details.add(Text('${AppStrings.infoName}: ${p.basename(path)}'));

        if (!_isViewingArchive) {
          try {
            final stat = File(path).statSync();
            details.add(Text('${AppStrings.infoSize}: ${filesize(stat.size)}'));
            details.add(Text(
                '${AppStrings.infoModified}: ${DateFormat('yyyy-MM-dd HH:mm').format(stat.modified)}'));
            details.add(Text('${AppStrings.infoPermissions}: ${stat.modeString()}'));
          } catch (e) {
            details.add(const Text(AppStrings.fileAccessInfoUnavailable));
          }
        } else {
          // Buscar entrada na lista do arquivo
          final entry = _currentArchiveEntries.cast<ArchiveEntry?>().firstWhere(
                (e) => e?.name == path,
                orElse: () => null,
              );

          if (entry != null) {
            details.add(Text('${AppStrings.infoSize}: ${filesize(entry.size)}'));
            if (entry.dateModified != null) {
              details.add(Text(
                '${AppStrings.infoModified}: ${DateFormat('yyyy-MM-dd HH:mm').format(entry.dateModified!)}',
              ));
            }
          }
        }
      } else {
        details.add(const Text(AppStrings.typeMultipleItems));
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: details,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(AppStrings.close)),
        ],
      ),
    );
  }

  Future<void> _showRepair() async {
    if (_selectedPaths.isEmpty || _selectedPaths.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.errorSelectSingleArchiveToRepair),
        ),
      );
      return;
    }

    String path = _selectedPaths.first;
    String ext = p.extension(path).toLowerCase();

    if (ext != '.rar' && ext != '.zip') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AppStrings.errorRepairOnlyRarZip),
        ),
      );
      return;
    }

    // Confirmation
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.repairArchiveTitle),
        content:
            Text("${AppStrings.repairConfirmationPrefix} '$path'?\n${AppStrings.repairConfirmationSuffix}"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(AppStrings.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(AppStrings.repairArchiveAction)),
        ],
      ),
    );

    if (confirm != true) return;

    if (ext == '.rar') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.attemptingRepair)),
        );
      }
      final result = await _archiveService.repairArchive(path);
      if (!mounted) return;
      _showInfoDialog(
        AppStrings.repairArchiveTitle,
        result.isSuccess
            ? AppStrings.attemptingRepair
            : (result.errorMessage ?? AppStrings.errorRarRepairToolUnavailable),
      );
    } else {
      // Zip repair logic (generic placeholder or basic zip -F if available)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.errorZipRepairNotImplemented)),
        );
      }
    }
  }

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(content)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(AppStrings.ok))
        ],
      ),
    );
  }

  void _performDelete() async {
    if (_isViewingArchive && _archivePath != null) {
      // Show progress
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator()),
        );
      }

      try {
        final filesToDelete =
            _selectedPaths.map((name) => _getFullArchivePath(name)).toList();
        final result = await _archiveService.deleteFromArchive(
          archivePath: _archivePath!,
          filesToDelete: filesToDelete,
        );

        if (mounted) Navigator.pop(context);
        if (!mounted) return;

        if (result.isSuccess) {
          setState(() => _selectedPaths.clear());
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.filesDeletedSuccessfully)),
          );
          _openArchive(_archivePath!); // Refresh
        } else {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text(AppStrings.deleteErrorTitle),
              content: Text(
                '${AppStrings.errorDeleteFailed}:\n${result.errorMessage ?? AppStrings.errorGeneric}',
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(AppStrings.ok))
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.errorGeneric}: $e')),
        );
      }
    } else {
      // Delete from file system
      for (final path in _selectedPaths) {
        try {
          final type = FileSystemEntity.typeSync(path);
          if (type == FileSystemEntityType.file) {
            File(path).deleteSync();
          } else if (type == FileSystemEntityType.directory) {
            Directory(path).deleteSync(recursive: true);
          }
        } catch (e) {
          // Silent error
        }
      }
      setState(() {
        _selectedPaths.clear();
      });
      _refreshFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildMenuBar(),
          _buildToolbar(),
          _buildAddressBar(),
          Expanded(child: _buildFileList()),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildMenuBar() {
    return Container(
      color: const Color(0xFFDDDDDD),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          _menuItem(AppStrings.menuFile),
          _menuItem(AppStrings.menuCommands),
          _menuItem(AppStrings.menuTools),
          _menuItem(AppStrings.menuFavorites),
          _menuItem(AppStrings.menuOptions),
          _menuItem(AppStrings.menuHelp),
        ],
      ),
    );
  }

  Widget _menuItem(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text(title, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey)),
        color: Color(0xFFEEEEEE),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolbarButton(Icons.add_box, AppStrings.add, _addToArchive),
            _toolbarButton(
                Icons.unarchive, AppStrings.extractToLabel, _extractSelected),
            _toolbarButton(Icons.check_circle_outline, AppStrings.test, () {}),
            _toolbarButton(
                Icons.remove_red_eye_outlined, AppStrings.view, () {}),
            _toolbarButton(
                Icons.delete_outline, AppStrings.delete, _deleteSelected),
            _toolbarButton(Icons.search, AppStrings.find, () {}),
            _toolbarButton(Icons.auto_fix_high, AppStrings.wizard, _showWizard),
            _toolbarButton(Icons.info_outline, AppStrings.info, _showInfo),
            _toolbarButton(
                Icons.build_circle_outlined, AppStrings.repair, _showRepair),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton(IconData icon, String label, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: Colors.blueGrey[800]),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressBar() {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            onPressed: _navigateUp,
            tooltip: AppStrings.upOneLevel,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(8),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                color: Colors.white,
              ),
              child: Row(
                children: [
                  Icon(Icons.folder, size: 16, color: Colors.yellow[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isViewingArchive
                          ? "$_archivePath${_archiveVirtualPath.isNotEmpty ? '\\$_archiveVirtualPath' : ''}"
                          : _currentPath,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Número total de itens (inclui ".." como primeiro item).
  int get _itemCount =>
      1 + (_isViewingArchive ? _currentArchiveEntries.length : _files.length);

  Widget _buildFileList() {
    final listContent = Container(
      color: Colors.white,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double availableWidth = constraints.maxWidth;
          final double fixedColumnsWidth = _colWidthCreated +
              _colWidthModified +
              _colWidthType +
              _colWidthSize;
          final double minRequiredNameWidth = _colWidthName;

          // Se houver espaço sobrando, expande a coluna Nome
          // Se não, usa o tamanho definido pelo usuário e permite scroll horizontal
          double renderNameWidth = minRequiredNameWidth;
          if (availableWidth > fixedColumnsWidth + minRequiredNameWidth) {
            renderNameWidth = availableWidth - fixedColumnsWidth;
          }

          // Largura total do conteúdo
          final double totalContentWidth = renderNameWidth + fixedColumnsWidth;

          return Column(
            children: [
              // Header
              Container(
                decoration: BoxDecoration(
                  color: AppColors.tableHeaderBackground,
                  border: const Border(
                    bottom: BorderSide(color: AppColors.headerBorder, width: 1),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _headerScrollController,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: totalContentWidth,
                    child: _buildDataTableHeader(nameWidth: renderNameWidth),
                  ),
                ),
              ),

              // Lista virtualizada
              Expanded(
                child: Scrollbar(
                  controller: _headerScrollController,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _headerScrollController,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: totalContentWidth,
                      child: ListView.builder(
                        itemCount: _itemCount,
                        itemExtent: 32,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildParentDirRow(
                                nameWidth: renderNameWidth);
                          }
                          final realIndex = index - 1;
                          if (_isViewingArchive) {
                            return _buildArchiveEntryRow(
                              _currentArchiveEntries[realIndex],
                              realIndex,
                              nameWidth: renderNameWidth,
                            );
                          } else {
                            return _buildFileRow(
                              _files[realIndex],
                              realIndex,
                              nameWidth: renderNameWidth,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Workaround: Only wrap with DropRegion after Flutter engine is fully ready
    // to avoid crash in release mode caused by FlutterView being nil
    if (!_dropRegionReady || Platform.isMacOS) {
      return listContent;
    }

    return DropRegion(
      formats: Formats.standardFormats,
      onDropOver: (event) {
        return DropOperation.copy;
      },
      onPerformDrop: (event) async {
        _handleDroppedFiles(event);
      },
      child: listContent,
    );
  }

  Widget _buildDataTableHeader({double? nameWidth}) {
    return Row(
      children: [
        _buildHeaderCell(AppStrings.colName, 0, nameWidth ?? _colWidthName,
            (delta) {
          setState(
              () => _colWidthName = (_colWidthName + delta).clamp(100, 1000));
        }),
        _buildHeaderCell(AppStrings.colCreated, 1, _colWidthCreated, (delta) {
          setState(() =>
              _colWidthCreated = (_colWidthCreated + delta).clamp(80, 250));
        }),
        _buildHeaderCell(AppStrings.colModified, 2, _colWidthModified, (delta) {
          setState(() =>
              _colWidthModified = (_colWidthModified + delta).clamp(80, 250));
        }),
        _buildHeaderCell(AppStrings.colType, 3, _colWidthType, (delta) {
          setState(
              () => _colWidthType = (_colWidthType + delta).clamp(60, 200));
        }),
        _buildHeaderCell(AppStrings.colSize, 4, _colWidthSize, null,
            isLast: true),
      ],
    );
  }

  Widget _buildHeaderCell(
    String label,
    int columnIndex,
    double width,
    void Function(double)? onResize, {
    bool isLast = false,
  }) {
    final isActive = _sortColumn == columnIndex;
    final arrow = isActive ? (_sortAscending ? ' ▲' : ' ▼') : '';

    return SizedBox(
      width: width,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _onColumnHeaderTap(columnIndex),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                child: Text(
                  '$label$arrow',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isActive ? Colors.blue.shade800 : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          if (!isLast)
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                onResize?.call(details.delta.dx);
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: Container(
                  width: 8,
                  height: 36,
                  decoration: const BoxDecoration(
                    border: Border(
                      right: BorderSide(color: Color(0xFFB0B0B0), width: 1),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Linha do diretório pai ".."
  Widget _buildParentDirRow({double? nameWidth}) {
    return _buildDataRow(
      icon: Icons.folder_open,
      iconColor: Colors.amber,
      name: '..',
      created: '',
      modified: '',
      type: '',
      size: '',
      isSelected: false,
      onTap: _navigateUp,
      onDoubleTap: _navigateUp,
      isEven: true,
      nameWidth: nameWidth,
    );
  }

  Widget _buildDataRow({
    required IconData icon,
    required Color iconColor,
    required String name,
    required String created,
    required String modified,
    required String type,
    required String size,
    required bool isSelected,
    required VoidCallback onTap,
    required VoidCallback onDoubleTap,
    required bool isEven,
    Widget? dragWrapper,
    double? nameWidth,
  }) {
    final rowContent = InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFCCE8FF)
              : (isEven ? Colors.white : const Color(0xFFFAFAFA)),
          border: const Border(
            bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
          ),
        ),
        child: Row(
          children: [
            // Coluna Nome com ícone
            SizedBox(
              width: nameWidth ?? _colWidthName,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Color(0xFFD0D0D0), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: iconColor, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Coluna Criado
            SizedBox(
              width: _colWidthCreated,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Color(0xFFD0D0D0), width: 1),
                  ),
                ),
                child: Text(
                  created,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Coluna Modificado
            SizedBox(
              width: _colWidthModified,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Color(0xFFD0D0D0), width: 1),
                  ),
                ),
                child: Text(
                  modified,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Coluna Tipo
            SizedBox(
              width: _colWidthType,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    right: BorderSide(color: Color(0xFFD0D0D0), width: 1),
                  ),
                ),
                child: Text(
                  type,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Coluna Tamanho
            SizedBox(
              width: _colWidthSize,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Text(
                  size,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return dragWrapper ?? rowContent;
  }

  Widget _buildFileRow(FileSystemEntity file, int index, {double? nameWidth}) {
    final name = p.basename(file.path);
    final isSelected = _selectedPaths.contains(file.path);
    final isDir = file is Directory;

    String sizeStr = "";
    String dateStr = "";
    String createdStr = "";
    String typeStr = AppStrings.typeFile;

    try {
      final stat = file.statSync();
      dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(stat.modified);
      createdStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(stat.changed);
      if (file is File) {
        sizeStr = filesize(stat.size);
        final ext = p.extension(file.path);
        if (ext.isNotEmpty) {
          typeStr =
              "${ext.substring(1).toUpperCase()} ${AppStrings.typeFile.toLowerCase()}";
        }
      } else {
        typeStr = AppStrings.typeFileFolder;
      }
    } catch (e) {
      // Access error
    }

    final icon = IconHelper.getIcon(file.path, isDir);
    final iconColor = IconHelper.getIconColor(file.path, isDir);

    // Create the draggable wrapper
    final dragWrapper = DragItemWidget(
      dragItemProvider: (request) async {
        final path = file.path;
        final item = DragItem(localData: path);
        item.add(Formats.fileUri(Uri.file(path)));
        item.add(Formats.plainText(path));
        return item;
      },
      allowedOperations: () => [DropOperation.copy],
      liftBuilder: (context, child) {
        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueAccent),
              boxShadow: const [
                BoxShadow(blurRadius: 5, color: Colors.black26)
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 8),
                Text(name,
                    style: const TextStyle(
                        fontSize: 14, decoration: TextDecoration.none)),
              ],
            ),
          ),
        );
      },
      child: DraggableWidget(
        child: _buildDataRow(
          icon: icon,
          iconColor: iconColor,
          name: name,
          created: createdStr,
          modified: dateStr,
          type: typeStr,
          size: sizeStr,
          isSelected: isSelected,
          onTap: () => _toggleSelection(file.path),
          onDoubleTap: () {
            if (file is Directory) {
              _navigateTo(file.path);
            } else if (_isArchive(file.path)) {
              _navigateTo(file.path);
            } else {
              OpenFilex.open(file.path);
            }
          },
          isEven: index % 2 == 0,
          nameWidth: nameWidth,
        ),
      ),
    );

    return dragWrapper;
  }

  Widget _buildArchiveEntryRow(ArchiveEntry entry, int index,
      {double? nameWidth}) {
    final name = entry.name;
    final isDir = entry.isDirectory;
    final sizeStr = isDir ? "" : filesize(entry.size);
    final typeStr = entry.typeDescription;
    final isSelected = _selectedPaths.contains(entry.name);

    String dateStr = "";
    String createdStr = "";

    if (entry.dateModified != null) {
      dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(entry.dateModified!);
    }
    if (entry.dateCreated != null) {
      createdStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(entry.dateCreated!);
    }

    final icon = IconHelper.getIcon(name, isDir);
    final iconColor = IconHelper.getIconColor(name, isDir);

    // Create the draggable wrapper for archive items
    final dragWrapper = DragItemWidget(
      dragItemProvider: (request) async {
        final path = await _extractFileForDrag(entry);
        if (path != null) {
          final item = DragItem(localData: path);
          item.add(Formats.fileUri(Uri.file(path)));
          item.add(Formats.plainText(path));
          return item;
        }
        return null;
      },
      allowedOperations: () => [DropOperation.copy],
      liftBuilder: (context, child) {
        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purpleAccent),
              boxShadow: const [
                BoxShadow(blurRadius: 5, color: Colors.black26)
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 8),
                Text(name,
                    style: const TextStyle(
                        fontSize: 14, decoration: TextDecoration.none)),
              ],
            ),
          ),
        );
      },
      child: DraggableWidget(
        child: _buildDataRow(
          icon: icon,
          iconColor: iconColor,
          name: name,
          created: createdStr,
          modified: dateStr,
          type: typeStr,
          size: sizeStr,
          isSelected: isSelected,
          onTap: () => _toggleSelection(name),
          onDoubleTap: () async {
            if (isDir) {
              _navigateIntoArchiveFolder(name);
            } else {
              // Extract file to temp and open with default application
              final extractedPath = await _extractFileForDrag(entry);
              if (extractedPath != null) {
                OpenFilex.open(extractedPath);
              }
            }
          },
          isEven: index % 2 == 0,
          nameWidth: nameWidth,
        ),
      ),
    );

    return dragWrapper;
  }

  Future<void> _handleDroppedFiles(PerformDropEvent event) async {
    final List<String> droppedPaths = [];

    // Read all items

    for (final item in event.session.items) {
      final reader = item.dataReader;

      if (reader != null) {
        if (reader.canProvide(Formats.fileUri)) {
          reader.getValue(Formats.fileUri, (uri) {
            if (uri != null) droppedPaths.add(uri.toFilePath());
          });
        }
      }
    }

    // Wait a bit for async callbacks to populate droppedPaths

    // In a real robust app we'd use Completers, but for this simpler logic:

    await Future.delayed(const Duration(milliseconds: 200));

    if (droppedPaths.isEmpty) return;

    if (_isViewingArchive) {
      if (_archivePath == null) return;

      // Auto-compress into current archive

      _compressFilesToCurrentArchive(droppedPaths);
    } else {
      // Ask user what to do

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text(AppStrings.fileDropAction),
          children: [
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);

                _createArchiveFromDropped(droppedPaths);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Row(children: [
                  Icon(Icons.archive),
                  SizedBox(width: 8),
                  Text(AppStrings.compressToArchive)
                ]),
              ),
            ),
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);

                _copyFilesHere(droppedPaths);
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Row(children: [
                  Icon(Icons.copy),
                  SizedBox(width: 8),
                  Text(AppStrings.copyHere)
                ]),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _compressFilesToCurrentArchive(List<String> files) async {
    // Atualização in-place depende de CLI externa.
    final ext = p.extension(_archivePath!).toLowerCase();

    if (ext == '.rar') {
      if (!_binaryLocator.isRarAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.errorRarAddToolUnavailable)),
        );
        return;
      }
    } else if (!_binaryLocator.is7zAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.error7zAddToolUnavailable)),
      );
      return;
    }

    // Show Progress
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final result = await _archiveService.addFilesToArchive(
        archivePath: _archivePath!,
        files: files,
        archiveVirtualPath: _archiveVirtualPath,
      );

      if (mounted) Navigator.pop(context); // Close loading

      if (result.isSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.filesAddedSuccessfully)),
          );
        }
        _openArchive(_archivePath!); // Refresh
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text(AppStrings.addErrorTitle),
              content: Text(
                '${AppStrings.errorAddFilesFailed}:\n${result.errorMessage ?? AppStrings.errorGeneric}',
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(AppStrings.ok))
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.errorGeneric}: $e')),
        );
      }
    }
  }

  Future<void> _createArchiveFromDropped(List<String> files) async {
    String defaultName = 'NovoArquivo.zip';

    if (files.length == 1) {
      defaultName = "${p.basenameWithoutExtension(files.first)}.zip";
    }

    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: AppStrings.createArchive,
      fileName: defaultName,
    );

    if (outputFile == null) return;

    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      await _archiveService.createArchiveFromFiles(
        outputFile: outputFile,
        files: files,
      );

      if (mounted) Navigator.pop(context); // Close loading

      _refreshFiles();
    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.errorCreateArchiveFailed}: $e')),
        );
      }
    }
  }

  void _copyFilesHere(List<String> files) {
    for (final srcPath in files) {
      try {
        final filename = p.basename(srcPath);

        final destPath = p.join(_currentPath, filename);

        if (FileSystemEntity.isDirectorySync(srcPath)) {
          // Simple recursive copy or warn

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(AppStrings.errorFolderCopyNotImplemented),
            ),
          );
        } else {
          File(srcPath).copySync(destPath);
        }
      } catch (e) {
        // ignore
      }
    }

    _refreshFiles();
  }

  Widget _buildStatusBar() {
    final count =
        _isViewingArchive ? _currentArchiveEntries.length : _files.length;
    final selectedCount = _selectedPaths.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      color: const Color(0xFFDDDDDD),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14),
          const SizedBox(width: 4),
          if (selectedCount > 0)
            Text('$selectedCount ${AppStrings.selectedSuffix}')
          else
            Text('$count ${AppStrings.objectsSuffix}'),
          const Spacer(),
          const Text(AppStrings.ready),
        ],
      ),
    );
  }
}
