import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:filesize/filesize.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:open_filex/open_filex.dart';
import 'worker.dart';
import 'services/binary_locator.dart';
import 'services/archive_parser.dart';
import 'models/archive_entry.dart';
import 'utils/icon_helper.dart';
import 'utils/constants.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(WinRARApp(args: args));
}

// Singleton para localização de binários
final _binaryLocator = BinaryLocator();

class WinRARApp extends StatelessWidget {
  final List<String> args;
  const WinRARApp({super.key, this.args = const []});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WinRAR Replica',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Segoe UI', // Attempt to look like Windows
        scaffoldBackgroundColor: const Color(0xFFF0F0F0),
      ),
      home: WinRARMainScreen(args: args),
    );
  }
}

class WinRARMainScreen extends StatefulWidget {
  final List<String> args;
  const WinRARMainScreen({super.key, this.args = const []});

  @override
  State<WinRARMainScreen> createState() => _WinRARMainScreenState();
}

// RarEntry foi movido para models/archive_entry.dart como ArchiveEntry

class _WinRARMainScreenState extends State<WinRARMainScreen> {
  late String _currentPath;
  List<FileSystemEntity> _files = [];
  final Set<String> _selectedPaths = {};

  // Cache de stats para evitar múltiplas chamadas statSync()
  final Map<String, FileStat> _statsCache = {};

  // Archive viewing state
  bool _isViewingArchive = false;
  String? _archivePath;
  List<ArchiveEntry> _allArchiveEntries = []; // Todas as entradas do arquivo
  List<ArchiveEntry> _currentArchiveEntries =
      []; // Entradas filtradas pelo nível atual
  String _archiveVirtualPath =
      ''; // Caminho virtual dentro do arquivo (ex: "pasta1/subpasta/")
  InputFileStream? _archiveInputStream;

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
    _currentPath = Platform.environment['HOME'] ?? Directory.current.path;
    debugPrint('Initial _currentPath: $_currentPath');
    debugPrint(
        'GPMT Version: 1.0.2 (Race Fix) - Build Time: ${DateTime.now()}');

    _createSessionTempDir();
    _refreshFiles();
    _setupFileHandlerChannel();

    // Start initialization sequence
    _initApp();
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

  // DISABLED - Using native AppDelegate instead of app_links package
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
        return FileStat.statSync('/dev/null'); // Fallback
      }
    });
  }

  /// Filtra as entradas do arquivo para mostrar apenas o nível atual.
  /// Imita o comportamento do WinRAR onde apenas itens do diretório atual são mostrados.
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
        _closeArchiveStream();
        _archivePath = null;
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
  @override
  void dispose() {
    _closeArchiveStream();
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

  void _closeArchiveStream() {
    try {
      _archiveInputStream?.close();
    } catch (e) {
      // Silent error
    }
    _archiveInputStream = null;
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
        _closeArchiveStream();
        _archivePath = null;
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

  Future<void> _openArchive(String path) async {
    final ext = p.extension(path).toLowerCase();

    // RAR handling
    if (ext == '.rar') {
      setState(() {
        _isViewingArchive = true;
        _archivePath = path;
        _allArchiveEntries = [];
        _currentArchiveEntries = [];
        _archiveVirtualPath = '';
        _archiveInputStream = null;
        _selectedPaths.clear();
      });

      // Tentar com 7z primeiro (mais informações)
      if (_binaryLocator.is7zAvailable) {
        try {
          final result = await Process.run(
            _binaryLocator.sevenZipExecutable,
            ['l', '-slt', path],
          );

          if (result.exitCode == 0) {
            final entries =
                ArchiveParser.parse7zListing(result.stdout.toString());
            setState(() {
              _allArchiveEntries =
                  entries.where((e) => e.name != path).toList();
            });
            _filterArchiveEntriesToCurrentLevel();
            _sortFiles();
            return;
          }
        } catch (e) {
          debugPrint("7z RAR listing falhou, usando unrar: $e");
        }
      }

      // Fallback para unrar
      if (!_binaryLocator.isUnrarAvailable) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(AppStrings.unrarNotFound),
              content: Text(
                "Para abrir arquivos RAR, instale 'unrar' ou 'p7zip-full'.\n\n"
                "${_binaryLocator.getInstallInstructions()}\n\n"
                "Detalhes: ${_binaryLocator.unrarErrorDetails}",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("OK"),
                )
              ],
            ),
          );
        }
        return;
      }

      final result = await Process.run(
        _binaryLocator.unrarExecutable,
        ['l', '-c-', path],
      );

      if (result.exitCode != 0) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(AppStrings.errorOpenArchive),
              content: Text("Falha ao listar conteúdo RAR: ${result.stderr}"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("OK"),
                )
              ],
            ),
          );
        }
        return;
      }

      final entries = ArchiveParser.parseUnrarListing(result.stdout.toString());
      setState(() {
        _allArchiveEntries = entries.where((e) => e.name != path).toList();
      });
      _filterArchiveEntriesToCurrentLevel();
      _sortFiles();
      return;
    }

    // Outros tipos de arquivo (Zip, Tar, Gz)
    try {
      _closeArchiveStream();
      final inputStream = InputFileStream(path);
      Archive archive;

      if (ext == '.zip' || ext == '.zipx' || ext == '.zi') {
        archive = ZipDecoder().decodeBuffer(inputStream);
      } else if (ext == '.tar') {
        archive = TarDecoder().decodeBuffer(inputStream);
      } else if (ext == '.gz' || ext == '.tgz') {
        inputStream.close();
        throw Exception("Visualização GZip/TGZ não implementada ainda");
      } else if (ext == '.7z' && _binaryLocator.is7zAvailable) {
        inputStream.close();
        // Usar 7z para listar arquivos .7z
        final result = await Process.run(
          _binaryLocator.sevenZipExecutable,
          ['l', '-slt', path],
        );
        if (result.exitCode == 0) {
          final entries =
              ArchiveParser.parse7zListing(result.stdout.toString());
          setState(() {
            _isViewingArchive = true;
            _archivePath = path;
            _allArchiveEntries = entries.where((e) => e.name != path).toList();
            _archiveVirtualPath = '';
            _archiveInputStream = null;
            _selectedPaths.clear();
          });
          _filterArchiveEntriesToCurrentLevel();
          _sortFiles();
          return;
        }
        throw Exception("Falha ao listar arquivo 7z");
      } else {
        inputStream.close();
        throw Exception("Formato não suportado: $ext");
      }

      // Converter ArchiveFile para ArchiveEntry
      final entries =
          archive.files.map((f) => ArchiveEntry.fromArchiveFile(f)).toList();

      setState(() {
        _isViewingArchive = true;
        _archivePath = path;
        _allArchiveEntries = entries;
        _archiveVirtualPath = '';
        _archiveInputStream = inputStream;
        _selectedPaths.clear();
      });
      _filterArchiveEntriesToCurrentLevel();
      _sortFiles();
    } catch (e) {
      _closeArchiveStream();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppStrings.errorOpenArchive),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("OK"),
              )
            ],
          ),
        );
      }
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
                content: Text(
                    'Please select a single archive or open one to extract.')),
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
            title: const Text("Extract To"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Destination path:"),
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
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text("Extract"),
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
        title: const Text("Extraction Options"),
        content: const Text("How should existing files be handled?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Skip Existing")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Overwrite All")),
        ],
      ),
    );

    if (overwriteChoice == null) return;

    // Check RAR
    if (p.extension(sourceArchive).toLowerCase() == '.rar') {
      if (!_binaryLocator.isUnrarAvailable) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Unrar Not Found"),
              content: const Text(
                  "To extract RAR files, please install 'unrar' on your system."),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("OK"))
              ],
            ),
          );
        }
        return;
      }

      final List<String> unrarArgs = ['x'];
      if (overwriteChoice) {
        unrarArgs.add('-o+'); // Overwrite all
      } else {
        unrarArgs.add('-o-'); // Skip existing
      }

      unrarArgs.add(sourceArchive);

      if (_isViewingArchive && _selectedPaths.isNotEmpty) {
        // Adicionar caminho virtual para obter o caminho completo
        unrarArgs.addAll(
            _selectedPaths.map((name) => _getFullArchivePath(name)).toList());
      }
      unrarArgs.add(outputDir);

      // Show loading dialog for RAR
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator()),
        );
      }

      try {
        final result =
            await Process.run(_binaryLocator.unrarExecutable, unrarArgs);

        if (mounted) Navigator.pop(context); // Close loading

        if (result.exitCode == 0) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Extracted RAR to $outputDir')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('RAR extraction failed: ${result.stderr}')),
            );
          }
        }
      } catch (e) {
        if (mounted) Navigator.pop(context); // Close loading
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('RAR extraction failed: $e')),
          );
        }
      }
      return;
    }

    // Other archive types extraction (Zip/Tar) via Isolate
    final receivePort = ReceivePort();
    final task = ExtractTask(
      sourcePath: sourceArchive,
      destinationPath: outputDir,
      selectedFiles: (_isViewingArchive && _selectedPaths.isNotEmpty)
          ? _selectedPaths.map((name) => _getFullArchivePath(name)).toList()
          : [],
      overwrite: overwriteChoice,
      useSystem7z: _binaryLocator.is7zAvailable,
      custom7zExecutable: _binaryLocator.sevenZipExecutable,
      flatten: false,
      sendPort: receivePort.sendPort,
    );

    // Progress State
    ValueNotifier<double> progressNotifier = ValueNotifier(0.0);
    ValueNotifier<String> statusNotifier = ValueNotifier("Preparing...");

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
                  const Text("Extracting...",
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

    try {
      await Isolate.spawn(extractWorker, task);

      await for (final message in receivePort) {
        if (message is Map) {
          if (message['type'] == 'progress') {
            final filename = message['filename'];
            final current = message['current'];
            final total = message['total'];
            statusNotifier.value = "Extracting $filename ($current/$total)";
            if (total > 0) {
              progressNotifier.value = current / total;
            }
          } else if (message['type'] == 'done') {
            break;
          } else if (message['type'] == 'error') {
            throw Exception(message['message']);
          }
        }
      }

      if (mounted) Navigator.pop(context); // Close loading

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extracted to $outputDir')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extraction failed: $e')),
        );
      }
    } finally {
      receivePort.close();
    }
  }

  Future<void> _addToArchive() async {
    if (_selectedPaths.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select files to add to archive.')),
        );
      }
      return;
    }

    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Archive As',
      fileName: 'archive.zip',
    );

    if (outputFile == null) return;

    try {
      final encoder = ZipFileEncoder();
      encoder.create(outputFile);

      for (final path in _selectedPaths) {
        if (FileSystemEntity.isDirectorySync(path)) {
          encoder.addDirectory(Directory(path));
        } else if (FileSystemEntity.isFileSync(path)) {
          encoder.addFile(File(path));
        }
      }
      encoder.close();

      _refreshFiles(); // Refresh current view to show new file if in same dir
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Archive created: $outputFile')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create archive: $e')),
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
                title: const Text("Delete files"),
                content: const Text(
                    "Are you sure you want to delete the selected files?"),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Cancel")),
                  TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _performDelete();
                      },
                      child: const Text("Yes")),
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
            content: Text('Preparando arraste...'),
            duration: Duration(milliseconds: 500),
          ),
        );
      }

      // RAR usa unrar diretamente
      if (SupportedExtensions.isRar(_archivePath!)) {
        final args = ['e', '-y', _archivePath!, fullEntryPath, tempDir.path];
        final result = await Process.run(_binaryLocator.unrarExecutable, args);

        if (result.exitCode == 0 && destFile.existsSync()) {
          return destPath;
        }
        return null;
      }

      // Outros formatos usam Isolate
      final receivePort = ReceivePort();
      final task = ExtractTask(
        sourcePath: _archivePath!,
        destinationPath: tempDir.path,
        selectedFiles: [fullEntryPath],
        overwrite: true,
        useSystem7z: _binaryLocator.is7zAvailable,
        custom7zExecutable: _binaryLocator.sevenZipExecutable,
        flatten: true,
        sendPort: receivePort.sendPort,
      );

      await Isolate.spawn(extractWorker, task);

      await for (final message in receivePort) {
        if (message is Map) {
          if (message['type'] == 'done') break;
          if (message['type'] == 'error') throw Exception(message['message']);
        }
      }
      receivePort.close();

      return destPath;
    } catch (e) {
      debugPrint('Erro ao extrair para drag: $e');
    }
    return null;
  }

  void _showWizard() {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('WinRAR Wizard'),
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
                  Text('Unpack an archive'),
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
                  Text('Create a new archive'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfo() {
    String title = "Information";
    List<Widget> details = [];

    if (_selectedPaths.isEmpty) {
      // Show info about current directory/archive
      title = _isViewingArchive ? "Archive Information" : "Folder Information";
      details.add(
          Text("Path: ${_isViewingArchive ? _archivePath : _currentPath}"));
      details.add(const SizedBox(height: 8));

      int count =
          _isViewingArchive ? _currentArchiveEntries.length : _files.length;
      details.add(Text("Contains: $count items"));

      // Calcular tamanho total
      int totalSize = 0;
      if (_isViewingArchive) {
        for (var e in _currentArchiveEntries) {
          totalSize += e.size;
        }
        details.add(Text("Tamanho Total: ${filesize(totalSize)}"));
      }
    } else {
      // Informações da seleção
      title = "Detalhes da Seleção";
      details.add(Text("Selecionados: ${_selectedPaths.length} itens"));
      details.add(const Divider());

      if (_selectedPaths.length == 1) {
        String path = _selectedPaths.first;
        details.add(Text("Nome: ${p.basename(path)}"));

        if (!_isViewingArchive) {
          try {
            final stat = File(path).statSync();
            details.add(Text("Tamanho: ${filesize(stat.size)}"));
            details.add(Text(
                "Modificado: ${DateFormat('yyyy-MM-dd HH:mm').format(stat.modified)}"));
            details.add(Text("Permissões: ${stat.modeString()}"));
          } catch (e) {
            details.add(
                const Text("Não foi possível ler informações do arquivo."));
          }
        } else {
          // Buscar entrada na lista do arquivo
          final entry = _currentArchiveEntries.cast<ArchiveEntry?>().firstWhere(
                (e) => e?.name == path,
                orElse: () => null,
              );

          if (entry != null) {
            details.add(Text("Tamanho: ${filesize(entry.size)}"));
            if (entry.dateModified != null) {
              details.add(Text(
                "Modificado: ${DateFormat('yyyy-MM-dd HH:mm').format(entry.dateModified!)}",
              ));
            }
          }
        }
      } else {
        details.add(const Text("Múltiplos itens selecionados."));
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
              child: const Text("Close")),
        ],
      ),
    );
  }

  Future<void> _showRepair() async {
    if (_selectedPaths.isEmpty || _selectedPaths.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a single archive to repair.')),
      );
      return;
    }

    String path = _selectedPaths.first;
    String ext = p.extension(path).toLowerCase();

    if (ext != '.rar' && ext != '.zip') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Repair is only supported for RAR and ZIP archives.')),
      );
      return;
    }

    // Confirmation
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Repair Archive"),
        content:
            Text("Attempt to repair '$path'?\nThis will create a fixed copy."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Repair")),
        ],
      ),
    );

    if (confirm != true) return;

    if (ext == '.rar') {
      if (!_binaryLocator.isUnrarAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('unrar not found.')));
        }
        return;
      }

      // unrar r <archive> <path_to_save_fixed>
      // unrar usually fixes in place or creates 'fixed.arcname.rar'
      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Attempting repair...')));
        }
        final result =
            await Process.run(_binaryLocator.unrarExecutable, ['r', path]);
        if (mounted) {
          if (result.exitCode == 0) {
            _showInfoDialog("Repair Complete", "Output:\n${result.stdout}");
          } else {
            _showInfoDialog("Repair Failed", "Error:\n${result.stderr}");
          }
        }
      } catch (e) {
        if (mounted) _showInfoDialog("Error", e.toString());
      }
    } else {
      // Zip repair logic (generic placeholder or basic zip -F if available)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Zip repair not fully implemented yet.')));
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
              onPressed: () => Navigator.pop(ctx), child: const Text("OK"))
        ],
      ),
    );
  }

  void _performDelete() async {
    if (_isViewingArchive && _archivePath != null) {
      // Delete from archive using rar d or 7z d
      final ext = p.extension(_archivePath!).toLowerCase();

      // Show progress
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator()),
        );
      }

      try {
        ProcessResult result;
        // Get the full paths of selected items
        final filesToDelete =
            _selectedPaths.map((name) => _getFullArchivePath(name)).toList();

        if (ext == '.rar') {
          if (!_binaryLocator.isRarAvailable) {
            if (mounted) Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('Install "rar" CLI to delete from RAR archives.')),
            );
            return;
          }
          // rar d <archive> <files...>
          final args = ['d', _archivePath!, ...filesToDelete];
          result = await Process.run(_binaryLocator.rarExecutable, args);
        } else {
          if (!_binaryLocator.is7zAvailable) {
            if (mounted) Navigator.pop(context);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Install "7z" to delete from archives.')),
            );
            return;
          }
          // 7z d <archive> <files...>
          final args = ['d', _archivePath!, ...filesToDelete];
          result = await Process.run(_binaryLocator.sevenZipExecutable, args);
        }

        if (mounted) Navigator.pop(context);
        if (!mounted) return;

        if (result.exitCode == 0) {
          setState(() => _selectedPaths.clear());
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Files deleted successfully.')),
          );
          _openArchive(_archivePath!); // Refresh
        } else {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete Error'),
              content: Text('Failed to delete files:\n${result.stderr}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK'))
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) Navigator.pop(context);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
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
          _menuItem("File"),
          _menuItem("Commands"),
          _menuItem("Tools"),
          _menuItem("Favorites"),
          _menuItem("Options"),
          _menuItem("Help"),
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
            _toolbarButton(Icons.add_box, "Add", _addToArchive),
            _toolbarButton(Icons.unarchive, "Extract To", _extractSelected),
            _toolbarButton(Icons.check_circle_outline, "Test", () {}),
            _toolbarButton(Icons.remove_red_eye_outlined, "View", () {}),
            _toolbarButton(Icons.delete_outline, "Delete", _deleteSelected),
            _toolbarButton(Icons.search, "Find", () {}),
            _toolbarButton(Icons.auto_fix_high, "Wizard", _showWizard),
            _toolbarButton(Icons.info_outline, "Info", _showInfo),
            _toolbarButton(Icons.build_circle_outlined, "Repair", _showRepair),
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
            tooltip: "Up one level",
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
    if (!_dropRegionReady) {
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
        _buildHeaderCell('Nome', 0, nameWidth ?? _colWidthName, (delta) {
          setState(
              () => _colWidthName = (_colWidthName + delta).clamp(100, 1000));
        }),
        _buildHeaderCell('Criado', 1, _colWidthCreated, (delta) {
          setState(() =>
              _colWidthCreated = (_colWidthCreated + delta).clamp(80, 250));
        }),
        _buildHeaderCell('Modificado', 2, _colWidthModified, (delta) {
          setState(() =>
              _colWidthModified = (_colWidthModified + delta).clamp(80, 250));
        }),
        _buildHeaderCell('Tipo', 3, _colWidthType, (delta) {
          setState(
              () => _colWidthType = (_colWidthType + delta).clamp(60, 200));
        }),
        _buildHeaderCell('Tamanho', 4, _colWidthSize, null, isLast: true),
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
    String typeStr = "File";

    try {
      final stat = file.statSync();
      dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(stat.modified);
      createdStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(stat.changed);
      if (file is File) {
        sizeStr = filesize(stat.size);
        final ext = p.extension(file.path);
        if (ext.isNotEmpty) {
          typeStr = "${ext.substring(1).toUpperCase()} File";
        }
      } else {
        typeStr = "File Folder";
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
          title: const Text("File Drop Action"),
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
                  Text("Compress to Archive")
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
                  Text("Copy Here")
                ]),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _compressFilesToCurrentArchive(List<String> files) async {
    // We strictly need 7z or zip for this. Dart archive lib is bad at 'updating' in place.

    if (!_binaryLocator.is7zAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Install "7z" (p7zip) to enable drag-and-drop compression updates.')),
      );

      return;
    }

    String ext = p.extension(_archivePath!).toLowerCase();

    if (ext == '.rar') {
      if (!_binaryLocator.isRarAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'To add files to RAR archives, please install the "rar" CLI tool (non-free).')),
        );
        return;
      }
      // Continue to RAR logic below (we will need to branch logic based on extension)
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
      ProcessResult result;

      if (ext == '.rar') {
        // rar a -ep1 -ap<destino> <archive_name> <files...>
        // -ep1: Exclude base directory from names
        // -ap<path>: Set path inside archive
        final List<String> args = ['a', '-ep1'];
        if (_archiveVirtualPath.isNotEmpty) {
          // Remove trailing slash for -ap flag
          String destPath = _archiveVirtualPath;
          if (destPath.endsWith('/')) {
            destPath = destPath.substring(0, destPath.length - 1);
          }
          args.add('-ap$destPath');
        }
        args.add(_archivePath!);
        args.addAll(files);
        result = await Process.run(_binaryLocator.rarExecutable, args);
      } else {
        // For 7z, we need to create a temporary directory structure
        // that mirrors the destination path and copy files there first
        if (_archiveVirtualPath.isNotEmpty) {
          // Create temp dir with the destination structure
          final tempDir = await Directory.systemTemp.createTemp('gpmt_add_');
          try {
            final destDir =
                Directory(p.join(tempDir.path, _archiveVirtualPath));
            await destDir.create(recursive: true);

            // Copy files to the destination structure
            for (final filePath in files) {
              final file = File(filePath);
              if (await file.exists()) {
                await file.copy(p.join(destDir.path, p.basename(filePath)));
              }
            }

            // Add the structured temp dir to archive
            final args = ['u', _archivePath!, '-r', '${tempDir.path}/*'];
            result = await Process.run(
              _binaryLocator.sevenZipExecutable,
              args,
              workingDirectory: tempDir.path,
            );

            // Cleanup temp dir
            await tempDir.delete(recursive: true);
          } catch (e) {
            await tempDir.delete(recursive: true);
            rethrow;
          }
        } else {
          // Root level - simple add
          final args = ['u', '-ep1', _archivePath!, ...files];
          result = await Process.run(_binaryLocator.sevenZipExecutable, args);
        }
      }

      if (mounted) Navigator.pop(context); // Close loading

      if (result.exitCode == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Files added successfully.')),
          );
        }
        _openArchive(_archivePath!); // Refresh
      } else {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Add Error'),
              content: Text('Failed to add files:\n${result.stderr}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("OK"))
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _createArchiveFromDropped(List<String> files) async {
    String defaultName = "NewArchive.zip";

    if (files.length == 1) {
      defaultName = "${p.basenameWithoutExtension(files.first)}.zip";
    }

    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Create Archive',
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
      // Prefer 7z if available

      if (_binaryLocator.is7zAvailable) {
        final args = ['a', outputFile, ...files];

        await Process.run(_binaryLocator.sevenZipExecutable, args);
      } else {
        // Fallback to Dart archive

        final encoder = ZipFileEncoder();

        encoder.create(outputFile);

        for (final path in files) {
          if (FileSystemEntity.isDirectorySync(path)) {
            encoder.addDirectory(Directory(path));
          } else if (FileSystemEntity.isFileSync(path)) {
            encoder.addFile(File(path));
          }
        }

        encoder.close();
      }

      if (mounted) Navigator.pop(context); // Close loading

      _refreshFiles();
    } catch (e) {
      if (mounted) Navigator.pop(context);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create archive: $e')),
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
                content: Text(
                    'Folder copy not fully implemented in drag logic yet.')),
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
            Text("$selectedCount selected")
          else
            Text("$count objects"),
          const Spacer(),
          const Text("Ready"),
        ],
      ),
    );
  }
}
