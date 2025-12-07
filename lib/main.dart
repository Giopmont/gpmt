import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:filesize/filesize.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';
import 'package:open_filex/open_filex.dart';
import 'worker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WinRARApp());
}

class IconHelper {
  static IconData getIcon(String path, bool isDirectory) {
    if (isDirectory) return Icons.folder;
    
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.zip':
      case '.rar':
      case '.tar':
      case '.gz':
      case '.7z':
        return Icons.inventory_2; // Archive look
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
      case '.bmp':
        return Icons.image;
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.txt':
      case '.md':
      case '.log':
        return Icons.description;
      case '.mp3':
      case '.wav':
      case '.ogg':
        return Icons.audio_file;
      case '.mp4':
      case '.avi':
      case '.mov':
        return Icons.movie;
      case '.exe':
      case '.bat':
      case '.sh':
        return Icons.terminal;
      default:
        return Icons.insert_drive_file;
    }
  }
  
  static Color getIconColor(String path, bool isDirectory) {
    if (isDirectory) return const Color(0xFFFFD54F); // Windows folder yellow
    
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.zip':
      case '.rar':
      case '.tar':
      case '.gz':
        return Colors.purple.shade300;
      case '.pdf':
        return Colors.red.shade400;
      case '.jpg':
      case '.png':
        return Colors.blue.shade400;
      case '.exe':
      case '.sh':
        return Colors.grey.shade600;
      default:
        return Colors.grey.shade500;
    }
  }
}

class WinRARApp extends StatelessWidget {
  const WinRARApp({super.key});

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
      home: const WinRARMainScreen(),
    );
  }
}

class WinRARMainScreen extends StatefulWidget {
  const WinRARMainScreen({super.key});

  @override
  State<WinRARMainScreen> createState() => _WinRARMainScreenState();
}

class RarEntry {
  final String name;
  final int size;
  final DateTime? dateModified;
  final bool isDirectory;

  RarEntry({
    required this.name,
    required this.size,
    this.dateModified,
    this.isDirectory = false,
  });
}

class _WinRARMainScreenState extends State<WinRARMainScreen> {
  String _currentPath = Directory.current.path;
  List<FileSystemEntity> _files = [];
  final Set<String> _selectedPaths = {};
  
  // Archive viewing state
  bool _isViewingArchive = false;
  String? _archivePath;
  List<dynamic> _currentArchiveEntries = []; // Can hold ArchiveFile or RarEntry
  InputFileStream? _archiveInputStream;
  
  // Temp dir for drag-and-drop cache
  Directory? _sessionTempDir;

  bool _isUnrarAvailable = false;
  bool _is7zAvailable = false;

  @override
  void initState() {
    super.initState();
    _createSessionTempDir();
    _checkUnrarAvailability();
    _check7zAvailability();
    _refreshFiles();
  }
  
  void _createSessionTempDir() {
    try {
      _sessionTempDir = Directory.systemTemp.createTempSync('winrar_session_');
    } catch (e) {
      // Handle error
    }
  }

  Future<void> _checkUnrarAvailability() async {
    try {
      final result = await Process.run('which', ['unrar']);
      if (result.exitCode == 0) {
        setState(() {
          _isUnrarAvailable = true;
        });
      }
    } catch (e) {
      // Silent error
    }
  }

  Future<void> _check7zAvailability() async {
    try {
      final result = await Process.run('which', ['7z']);
      if (result.exitCode == 0) {
        setState(() {
          _is7zAvailable = true;
        });
      }
    } catch (e) {
      // Silent error
    }
  }

  @override
  void dispose() {
    _closeArchiveStream();
    _cleanupSessionTempDir();
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
      // In archive mode, we don't refresh from disk unless we re-read the archive
      // But here we might just assume static list for the view
      return;
    }

    final dir = Directory(_currentPath);
    try {
      if (dir.existsSync()) {
        final entities = dir.listSync();
        setState(() {
          _files = entities
            ..sort((a, b) {
              if (a is Directory && b is! Directory) return -1;
              if (a is! Directory && b is Directory) return 1;
              return a.path.toLowerCase().compareTo(b.path.toLowerCase());
            });
          _selectedPaths.clear();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error access directory: $e')),
      );
    }
  }

  void _navigateTo(String path) {
    // Check if it's a supported archive
    if (_isArchive(path)) {
      _openArchive(path);
      return;
    }

    final dir = Directory(path);
    if (dir.existsSync()) {
      setState(() {
        _currentPath = path;
        _isViewingArchive = false;
        _closeArchiveStream();
        _archivePath = null;
        _currentArchiveEntries = []; // Use _currentArchiveEntries here too
      });
      _refreshFiles();
    }
  }

  void _navigateUp() {
    if (_isViewingArchive) {
      // Exit archive view
      setState(() {
        _isViewingArchive = false;
        _currentPath = p.dirname(_archivePath!);
        _closeArchiveStream();
        _archivePath = null;
        _currentArchiveEntries = []; // Use _currentArchiveEntries here too
      });
      _refreshFiles();
    } else {
      final parent = Directory(_currentPath).parent;
      if (parent.path != _currentPath) {
        _navigateTo(parent.path);
      }
    }
  }

  bool _isArchive(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.zip' || ext == '.tar' || ext == '.tgz' || ext == '.gz' || ext == '.rar';
  }

  Future<void> _openArchive(String path) async {
    final ext = p.extension(path).toLowerCase();
    
    // RAR handling
    if (ext == '.rar') {
      setState(() {
        _isViewingArchive = true;
        _archivePath = path;
        _currentArchiveEntries = []; // Clear for RAR
        _archiveInputStream = null; // No stream for RAR for now
        _selectedPaths.clear();
      });

      if (!_isUnrarAvailable) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Unrar Not Found"),
              content: const Text("To open RAR files, please install 'unrar' on your system."),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
            ),
          );
        }
        return;
      }

      final result = await Process.run('unrar', ['l', '-c-', path]);

      if (result.exitCode != 0) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Error Opening RAR"),
              content: Text("Failed to list RAR contents: ${result.stderr}"),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
            ),
          );
        }
        return;
      }

      final output = result.stdout as String;
      // debugPrint("Unrar output:\n$output"); // Silent

      final lines = output.split('\n');
      List<RarEntry> rarEntries = [];
      
      // Regex for "Attributes Size Date Time Name" format
      // Attributes: \S+ (can be 7 chars like ..A.... or 10 like -rw-r--r--)
      // Size: digits
      // Date: non-whitespace
      // Time: non-whitespace
      // Name: rest
      final attrFirstRegex = RegExp(r'^\s*(\S+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(.+)$');

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        // Ignore Headers and Footers
        if (line.startsWith('---') || 
            line.startsWith('Archive:') || 
            line.startsWith('Details:') || 
            line.contains('Attributes      Size') ||
            line.startsWith('UNRAR') || 
            line.contains('Alexander Roshal') ||
            line.trim().startsWith(RegExp(r'\d+\s+\d+$'))) { // Summary line (Size Count)
          continue;
        }

        // Try matching standard line
        final match = attrFirstRegex.firstMatch(line);
        if (match != null) {
          try {
            final attr = match.group(1)!;
            final sizeStr = match.group(2)!;
            final dateStr = match.group(3)!;
            final timeStr = match.group(4)!;
            final name = match.group(5)!.trim();
            
            if (attr.startsWith('Attributes')) continue;

            final size = int.tryParse(sizeStr) ?? 0;
            DateTime? dateModified;
            
            final dateTimeString = '$dateStr $timeStr';
            List<String> formats = [
              'yyyy-MM-dd HH:mm',
              'dd-MM-yy HH:mm',
              'MM-dd-yy HH:mm',
              'yyyy-MM-dd HH:mm:ss',
            ];

            for (final fmt in formats) {
               try {
                 dateModified = DateFormat(fmt).parse(dateTimeString);
                 break;
               } catch (_) {}
            }

            final isDirectory = attr.startsWith('d') || attr.contains('D');

            rarEntries.add(RarEntry(
              name: name,
              size: size,
              dateModified: dateModified,
              isDirectory: isDirectory,
            ));
          } catch (e) {
            // Silent error
          }
        }
      }

      setState(() {
        _isViewingArchive = true;
        _archivePath = path;
        _currentArchiveEntries = rarEntries;
        _archiveInputStream = null;
        _selectedPaths.clear();
      });
      return;
    }
    
    // Other archive types handling (Zip, Tar, Gz)
    try {
      _closeArchiveStream(); // Close previous if exists
      final inputStream = InputFileStream(path);
      Archive archive;
      if (ext == '.zip') {
        archive = ZipDecoder().decodeBuffer(inputStream);
      } else if (ext == '.tar') {
        archive = TarDecoder().decodeBuffer(inputStream);
      } else if (ext == '.gz' || ext == '.tgz') {
        // GZip/TGZ view not fully implemented yet
        inputStream.close();
        throw Exception("GZip/TGZ view not fully implemented yet");
      } else {
        inputStream.close();
        throw Exception("Unsupported format: $ext");
      }
      
      setState(() {
        _isViewingArchive = true;
        _archivePath = path;
        _currentArchiveEntries = archive.files; // Store ArchiveFile objects
        _archiveInputStream = inputStream;
        _selectedPaths.clear();
      });
    } catch (e) {
      _closeArchiveStream();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Error Opening Archive"),
            content: Text(e.toString()),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
          ),
        );
      }
    }
  }

  void _toggleSelection(String name) { // Changed parameter from path to name for archive entries
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
            const SnackBar(content: Text('Please select a single archive or open one to extract.')),
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
        final TextEditingController controller = TextEditingController(text: defaultDest);
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
                      String? selected = await FilePicker.platform.getDirectoryPath();
                      if (selected != null) {
                        controller.text = selected;
                      }
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
      }
    );

    if (outputDir == null) return;

    // Ask for overwrite preference upfront for all formats
    if (!mounted) return;
    final bool? overwriteChoice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Extraction Options"),
        content: const Text("How should existing files be handled?"),
        actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text("Cancel")),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Skip Existing")),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Overwrite All")),
        ],
      ),
    );

    if (overwriteChoice == null) return;

    // Check RAR
    if (p.extension(sourceArchive).toLowerCase() == '.rar') {
      if (!_isUnrarAvailable) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Unrar Not Found"),
              content: const Text("To extract RAR files, please install 'unrar' on your system."),
              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
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
        unrarArgs.addAll(_selectedPaths.toList());
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
        final result = await Process.run('unrar', unrarArgs);
        
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
              SnackBar(content: Text('RAR extraction failed: ${result.stderr}')),
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
      selectedFiles: (_isViewingArchive && _selectedPaths.isNotEmpty) ? _selectedPaths.toList() : [],
      overwrite: overwriteChoice,
      useSystem7z: _is7zAvailable,
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
                  const Text("Extracting...", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  ValueListenableBuilder<double>(
                    valueListenable: progressNotifier,
                    builder: (context, value, child) => LinearProgressIndicator(value: value > 0 ? value : null),
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<String>(
                    valueListenable: statusNotifier,
                    builder: (context, value, child) => Text(value, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
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
       showDialog(context: context, builder: (ctx) => AlertDialog(
         title: const Text("Delete files"),
         content: const Text("Are you sure you want to delete the selected files?"),
         actions: [
           TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
           TextButton(onPressed: () {
             Navigator.pop(ctx);
             _performDelete();
           }, child: const Text("Yes")),
         ],
       ));
     }
  }

  Future<String?> _extractFileForDrag(dynamic entry) async {
    if (_archivePath == null) return null;

    try {
      // Use session temp dir if available, else fallback to new temp
      final tempDir = _sessionTempDir ?? Directory.systemTemp.createTempSync('winrar_drag_');
      
      if (entry is FileSystemEntity) {
        return entry.path; 
      }
      
      String name;
      bool isDir;
      
      if (entry is ArchiveFile) {
        name = entry.name;
        isDir = !entry.isFile;
        if (isDir) return null; 
        
        final destPath = p.join(tempDir.path, p.basename(name));
        final destFile = File(destPath);
        
        // CACHE HIT CHECK
        if (destFile.existsSync()) {
          return destPath;
        }

        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Preparing drag...'), duration: Duration(milliseconds: 500)),
           );
        }

        // Use Isolate for extraction to avoid freeze/crash on large files
        final receivePort = ReceivePort();
        final task = ExtractTask(
          sourcePath: _archivePath!,
          destinationPath: tempDir.path,
          selectedFiles: [name], // Extract only this file
          overwrite: true,
          useSystem7z: _is7zAvailable,
          flatten: true,
          sendPort: receivePort.sendPort,
        );
        
        // Show a non-blocking overlay progress or just await
        // Since drag provider expects a future, we just await.
        // To show progress, we might need a Overlay.
        // For now, let's just ensure it DOESN'T CRASH/FREEZE UI.
        // Users will see the drag "hover" until done.
        
        await Isolate.spawn(extractWorker, task);
        
        await for (final message in receivePort) {
           if (message is Map) {
             if (message['type'] == 'done') break;
             if (message['type'] == 'error') throw Exception(message['message']);
           }
        }
        receivePort.close();

        return destPath;
      } 
      else if (entry is RarEntry) {
        name = entry.name;
        isDir = entry.isDirectory;
        if (isDir) return null;
        
        final destPath = p.join(tempDir.path, p.basename(name));
        final destFile = File(destPath);

        // CACHE HIT CHECK
        if (destFile.existsSync()) {
          return destPath;
        }

        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Preparing drag...'), duration: Duration(milliseconds: 500)),
           );
        }
        
        final args = ['e', '-y', _archivePath!, name, tempDir.path];
        final result = await Process.run('unrar', args);
        
        if (result.exitCode == 0) {
           if (destFile.existsSync()) {
             return destPath;
           }
        }
      }
    } catch (e) {
      // Silent error
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
      details.add(Text("Path: ${_isViewingArchive ? _archivePath : _currentPath}"));
      details.add(const SizedBox(height: 8));
      
      int count = _isViewingArchive ? _currentArchiveEntries.length : _files.length;
      details.add(Text("Contains: $count items"));
      
      // Calculate total size if possible (simple sum)
      int totalSize = 0;
      if (_isViewingArchive) {
         for (var e in _currentArchiveEntries) {
           if (e is ArchiveFile) totalSize += e.size;
           if (e is RarEntry) totalSize += e.size;
         }
         details.add(Text("Total Packed Size: ${filesize(totalSize)}"));
      }
    } else {
      // Show info about selection
      title = "Selection Details";
      details.add(Text("Selected: ${_selectedPaths.length} items"));
      details.add(const Divider());
      
      if (_selectedPaths.length == 1) {
        String path = _selectedPaths.first;
        details.add(Text("Name: ${p.basename(path)}"));
        
        if (!_isViewingArchive) {
          try {
             final stat = File(path).statSync();
             details.add(Text("Size: ${filesize(stat.size)}"));
             details.add(Text("Modified: ${DateFormat('yyyy-MM-dd HH:mm').format(stat.modified)}"));
             details.add(Text("Permissions: ${stat.modeString()}"));
          } catch (e) {
             details.add(const Text("Could not read file stats."));
          }
        } else {
          // Find entry in archive list
          var entry = _currentArchiveEntries.firstWhere((e) {
             if (e is ArchiveFile) return e.name == path;
             if (e is RarEntry) return e.name == path;
             return false;
          }, orElse: () => null);
          
          if (entry != null) {
             if (entry is ArchiveFile) details.add(Text("Size: ${filesize(entry.size)}"));
             if (entry is RarEntry) details.add(Text("Size: ${filesize(entry.size)}"));
          }
        }
      } else {
        // Multiple items
        details.add(const Text("Multiple items selected."));
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
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
        const SnackBar(content: Text('Repair is only supported for RAR and ZIP archives.')),
      );
      return;
    }

    // Confirmation
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Repair Archive"),
        content: Text("Attempt to repair '$path'?\nThis will create a fixed copy."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Repair")),
        ],
      ),
    );

    if (confirm != true) return;

    if (ext == '.rar') {
      if (!_isUnrarAvailable) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('unrar not found.')));
        }
        return;
      }
      
      // unrar r <archive> <path_to_save_fixed>
      // unrar usually fixes in place or creates 'fixed.arcname.rar'
      try {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attempting repair...')));
        }
        final result = await Process.run('unrar', ['r', path]);
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
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zip repair not fully implemented yet.')));
      }
    }
  }

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(content)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
      ),
    );
  }

  void _performDelete() {
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
                      _isViewingArchive ? "$_archivePath (Archive)" : _currentPath,
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

  Widget _buildFileList() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            color: const Color(0xFFEEEEEE),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: const Row(
              children: [
                SizedBox(width: 40), // Checkbox space
                Expanded(flex: 5, child: Text("Name", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 2, child: Text("Size", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 2, child: Text("Type", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                Expanded(flex: 3, child: Text("Modified", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
              ],
            ),
          ),
          const Divider(height: 1),
          // List
          Expanded(
            child: _isViewingArchive 
              ? ListView.builder(
                  itemCount: _currentArchiveEntries.length + 1, // +1 for ".."
                  itemBuilder: (context, index) {
                    if (index == 0) return _buildParentDirItem();
                    final entry = _currentArchiveEntries[index - 1];
                    return _buildArchiveEntryItem(entry);
                  },
                )
              : ListView.builder(
                  itemCount: _files.length + 1, // +1 for ".."
                  itemBuilder: (context, index) {
                    if (index == 0) return _buildParentDirItem();
                    final file = _files[index - 1];
                    return _buildFileItem(file);
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentDirItem() {
    return InkWell(
      onTap: _navigateUp,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
             const SizedBox(width: 40, child: Icon(Icons.folder_open, size: 18)),
             const Expanded(flex: 5, child: Text("..", style: TextStyle(fontSize: 13))),
             Expanded(flex: 2, child: Container()),
             Expanded(flex: 2, child: Container()),
             Expanded(flex: 3, child: Container()),
          ],
        ),
      ),
    );
  }

  Widget _buildFileItem(FileSystemEntity file) {
    final name = p.basename(file.path);
    final isSelected = _selectedPaths.contains(file.path);
    final isDir = file is Directory;
    
    String sizeStr = "";
    String dateStr = "";
    String typeStr = "File";
    
    try {
      final stat = file.statSync();
      dateStr = DateFormat('yyyy-MM-dd HH:mm').format(stat.modified);
      if (file is File) {
        sizeStr = filesize(stat.size);
        typeStr = "${p.extension(file.path).toUpperCase().replaceAll('.', '')} File";
        if (typeStr.trim().isEmpty) typeStr = "File";
      } else {
        typeStr = "File Folder";
      }
    } catch (e) {
      // Access error
    }

    final row = InkWell(
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
      child: Container(
        color: isSelected ? const Color(0xFFCCE8FF) : null, // Windows Selection Blue
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 32, 
              child: Icon(
                IconHelper.getIcon(file.path, isDir), 
                color: IconHelper.getIconColor(file.path, isDir),
                size: 20
              )
            ),
            Expanded(flex: 5, child: Text(name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
            Expanded(flex: 2, child: Text(sizeStr, style: const TextStyle(fontSize: 13))),
            Expanded(flex: 2, child: Text(typeStr, style: const TextStyle(fontSize: 13))),
            Expanded(flex: 3, child: Text(dateStr, style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );

    // Draggable Wrapper
    return DragItemWidget(
      dragItemProvider: (request) async {
        final path = file.path;
        final item = DragItem(
          localData: path,
        );
        item.add(Formats.fileUri(Uri.file(path)));
        item.add(Formats.plainText(path));
        return item;
      },
      allowedOperations: () => [DropOperation.copy],
      // Custom Drag Image
      liftBuilder: (context, child) {
        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8), // Transparent white
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueAccent),
              boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black26)],
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  IconHelper.getIcon(file.path, isDir), 
                  color: IconHelper.getIconColor(file.path, isDir),
                  size: 24
                ),
                const SizedBox(width: 8),
                Text(name, style: const TextStyle(fontSize: 14, decoration: TextDecoration.none)),
              ],
            ),
          ),
        );
      },
      child: DraggableWidget(
        child: row,
      ),
    );
  }

  Widget _buildArchiveEntryItem(dynamic entry) {
    String name;
    String sizeStr;
    String typeStr;
    bool isDir;
    bool isSelected;

    if (entry is ArchiveFile) {
      name = entry.name;
      isDir = !entry.isFile;
      sizeStr = isDir ? "" : filesize(entry.size);
      typeStr = isDir ? "Folder" : "Packed File";
      isSelected = _selectedPaths.contains(entry.name);
    } else if (entry is RarEntry) {
      name = entry.name;
      isDir = entry.isDirectory;
      sizeStr = isDir ? "" : filesize(entry.size);
      typeStr = isDir ? "Folder" : "RAR File";
      isSelected = _selectedPaths.contains(entry.name);
    } else {
      name = "Unknown";
      sizeStr = "";
      typeStr = "";
      isDir = false;
      isSelected = false;
    }
    
    final row = InkWell(
      onTap: () => _toggleSelection(name),
      child: Container(
        color: isSelected ? const Color(0xFFCCE8FF) : null,
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 32, 
              child: Icon(
                IconHelper.getIcon(name, isDir), 
                color: IconHelper.getIconColor(name, isDir),
                size: 20
              )
            ),
            Expanded(flex: 5, child: Text(name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
            Expanded(flex: 2, child: Text(sizeStr, style: const TextStyle(fontSize: 13))),
            Expanded(flex: 2, child: Text(typeStr, style: const TextStyle(fontSize: 13))),
            Expanded(flex: 3, child: Text("", style: const TextStyle(fontSize: 13))),
          ],
        ),
      ),
    );

    // Draggable Wrapper for Archive Items
    return DragItemWidget(
      dragItemProvider: (request) async {
        final path = await _extractFileForDrag(entry);
        if (path != null) {
          final item = DragItem(
            localData: path,
          );
          item.add(Formats.fileUri(Uri.file(path)));
          item.add(Formats.plainText(path)); // Fallback
          return item;
        } else {
          return null;
        }
      },
      allowedOperations: () => [DropOperation.copy],
      liftBuilder: (context, child) {
        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purpleAccent),
              boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black26)],
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  IconHelper.getIcon(name, isDir), 
                  color: IconHelper.getIconColor(name, isDir),
                  size: 24
                ),
                const SizedBox(width: 8),
                Text(name, style: const TextStyle(fontSize: 14, decoration: TextDecoration.none)),
              ],
            ),
          ),
        );
      },
      child: DraggableWidget(
        child: row,
      ),
    );
  }

  Widget _buildStatusBar() {
    final count = _isViewingArchive ? _currentArchiveEntries.length : _files.length;
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