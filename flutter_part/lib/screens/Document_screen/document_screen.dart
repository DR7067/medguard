import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_part/screens/Document_screen/file_viewer.dart';
import 'package:flutter_part/screens/Document_screen/folder_screen.dart';
import 'package:flutter_part/screens/Document_screen/report_highlight_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_part/screens/Document_screen/storage_item.dart';
import 'package:flutter_part/screens/Home_screen/activity_service.dart';
import 'package:flutter_part/screens/Home_screen/recent_activity.dart';

const Color kPrimaryColor = Color(0xFF2563EB);

/// =======================
/// DOCUMENT SCREEN
/// =======================
class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key});

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  List<StorageItem> items = [];
  static const String _backendBaseUrl = "http://10.12.82.64:5000";
  static const String _documentsStorageKey = 'saved_documents';
  static const String _databaseId = 'medguard-data';
  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: _databaseId,
  );
  final FirebaseStorage _storage = FirebaseStorage.instance;
  String _searchQuery = '';
  final bool _sortAscending = true;
  String _selectedFilter = "All";

  @override
  void initState() {
    super.initState();
    _initializeDocuments();
  }

  Future<void> _initializeDocuments() async {
    await _waitForUser();
    await _loadDocuments();
    await _uploadPendingLocalItems();
    await _syncFromCloud();
  }

  Future<User?> _waitForUser() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) return current;
    try {
      return await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedDocumentsKey());
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final loaded = decoded
          .whereType<Map>()
          .map((item) => StorageItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      if (!mounted) return;
      setState(() {
        items
          ..clear()
          ..addAll(loaded);
      });
    } catch (_) {
      await prefs.remove(_scopedDocumentsKey());
    }
  }

  Future<void> _saveDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(items.map((item) => item.toJson()).toList());
    await prefs.setString(_scopedDocumentsKey(), encoded);
  }

  Future<void> _uploadPendingLocalItems() async {
    final pending = <StorageItem>[];
    void walk(List<StorageItem> list) {
      for (final item in list) {
        if (!item.isFolder &&
            (item.storagePath == null || item.storagePath!.isEmpty)) {
          pending.add(item);
        }
        if (item.children != null) walk(item.children!);
      }
    }

    walk(items);
    for (final item in pending) {
      await _uploadItemToCloud(item);
    }
  }

  String _scopedDocumentsKey() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return _documentsStorageKey;
    return '${_documentsStorageKey}_$uid';
  }

  List<String> _childFolderPath(StorageItem? parent, String name) {
    final base = <String>[];
    if (parent != null) {
      if (parent.folderPath != null && parent.folderPath!.isNotEmpty) {
        base.addAll(parent.folderPath!);
      } else {
        base.add(parent.name);
      }
    }
    base.add(name);
    return base;
  }

  List<String>? _folderPathForParent(StorageItem? parent) {
    if (parent == null) return null;
    if (parent.folderPath != null && parent.folderPath!.isNotEmpty) {
      return List<String>.from(parent.folderPath!);
    }
    return [parent.name];
  }

  StorageItem? _findById(String id) {
    StorageItem? result;
    void walk(List<StorageItem> list) {
      for (final item in list) {
        if (item.id == id) {
          result = item;
          return;
        }
        if (item.children != null) {
          walk(item.children!);
          if (result != null) return;
        }
      }
    }

    walk(items);
    return result;
  }

  StorageItem _ensureFolderPath(List<String> path) {
    List<StorageItem> cursor = items;
    StorageItem? current;
    for (final segment in path) {
      final existing = cursor.firstWhere(
        (e) => e.isFolder && e.name == segment,
        orElse: () {
          final folder = StorageItem(
            name: segment,
            isFolder: true,
            children: [],
            folderPath: current == null
                ? [segment]
                : [...(current.folderPath ?? []), segment],
          );
          cursor.add(folder);
          return folder;
        },
      );
      current = existing;
      existing.children ??= [];
      cursor = existing.children!;
    }
    return current!;
  }

  Future<void> _syncFromCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await _db
          .collection('users')
          .doc(user.uid)
          .collection('documents')
          .get();

      bool changed = false;
      for (final doc in snap.docs) {
        final data = doc.data();
        final id = doc.id;
        if (_findById(id) != null) continue;

        final fileName = data['fileName']?.toString() ?? 'file';
        final downloadUrl = data['fileUrl']?.toString();
        final storagePath = data['storagePath']?.toString();
        final folderPath = (data['folderPath'] as List?)
            ?.map((e) => e.toString())
            .toList();

        String? localPath;
        if (downloadUrl != null && downloadUrl.isNotEmpty) {
          try {
            final resp = await http.get(Uri.parse(downloadUrl));
            if (resp.statusCode >= 200 && resp.statusCode < 300) {
              localPath = await _storeFileLocally(
                originalName: fileName,
                bytes: resp.bodyBytes,
              );
            }
          } catch (_) {}
        }

        final item = StorageItem(
          id: id,
          name: fileName,
          isFolder: false,
          extension: _extensionForName(fileName),
          path: localPath,
          bytes: localPath == null ? null : null,
          folderPath: folderPath,
          storagePath: storagePath,
          downloadUrl: downloadUrl,
          uploadedAtMs: (data['uploadedAtMs'] as num?)?.toInt(),
        );

        if (folderPath != null && folderPath.isNotEmpty) {
          final parent = _ensureFolderPath(folderPath);
          parent.children ??= [];
          parent.children!.add(item);
        } else {
          items.add(item);
        }
        changed = true;
      }

      if (changed && mounted) {
        setState(() {});
        await _saveDocuments();
      }
    } catch (e) {
      debugPrint('Cloud sync failed: $e');
    }
  }

  Future<void> _uploadItemToCloud(StorageItem item) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || item.isFolder) return;
    if (item.storagePath != null && item.storagePath!.isNotEmpty) return;

    final safeName = _sanitizeFileName(item.name);
    final storagePath =
        'documents/${user.uid}/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = _storage.ref().child(storagePath);

    try {
      if (item.path != null && item.path!.isNotEmpty) {
        final file = File(item.path!);
        if (await file.exists()) {
          await ref.putFile(file);
        } else if (item.bytes != null) {
          await ref.putData(item.bytes!);
        } else {
          return;
        }
      } else if (item.bytes != null) {
        await ref.putData(item.bytes!);
      } else {
        return;
      }

      final url = await ref.getDownloadURL();
      final docId =
          item.id ??
          _db
              .collection('users')
              .doc(user.uid)
              .collection('documents')
              .doc()
              .id;

      await _db
          .collection('users')
          .doc(user.uid)
          .collection('documents')
          .doc(docId)
          .set({
            'fileName': item.name,
            'fileUrl': url,
            'storagePath': storagePath,
            'uploadedAtMs': DateTime.now().millisecondsSinceEpoch,
            'folderPath': item.folderPath,
            'type': item.extension ?? '',
          }, SetOptions(merge: true));

      item.id = docId;
      item.storagePath = storagePath;
      item.downloadUrl = url;
      item.uploadedAtMs = DateTime.now().millisecondsSinceEpoch;
      await _saveDocuments();
      ActivityService.instance.addActivity(
        RecentActivity(
          description: "Added document ${item.name}",
          timestamp: DateTime.now(),
          type: ActivityType.document,
        ),
      );
    } catch (e) {
      debugPrint('Upload failed: $e');
    }
  }

  Future<Directory> _documentsDirectory() async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${baseDir.path}${Platform.pathSeparator}documents');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _sanitizeFileName(String name) {
    final safe = name.replaceAll(RegExp(r'[\\\\/:*?"<>|]'), '_').trim();
    return safe.isEmpty ? 'file' : safe;
  }

  String _normalizedFileName(String input, String? existingExt) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    if (!trimmed.contains('.') &&
        existingExt != null &&
        existingExt.isNotEmpty) {
      return '$trimmed.$existingExt';
    }
    return trimmed;
  }

  String _extensionForName(String name) {
    final idx = name.lastIndexOf('.');
    if (idx <= 0 || idx == name.length - 1) return '';
    return name.substring(idx + 1).toLowerCase();
  }

  Future<String> _uniqueFilePath(Directory dir, String fileName) async {
    final safeName = _sanitizeFileName(fileName);
    String candidate = '${dir.path}${Platform.pathSeparator}$safeName';
    if (!await File(candidate).exists()) return candidate;

    final dot = safeName.lastIndexOf('.');
    final base = dot > 0 ? safeName.substring(0, dot) : safeName;
    final ext = dot > 0 ? safeName.substring(dot) : '';
    int counter = 1;
    while (await File(candidate).exists()) {
      candidate = '${dir.path}${Platform.pathSeparator}$base ($counter)$ext';
      counter++;
    }
    return candidate;
  }

  Future<String> _storeFileLocally({
    required String originalName,
    String? sourcePath,
    Uint8List? bytes,
  }) async {
    final dir = await _documentsDirectory();
    final targetPath = await _uniqueFilePath(dir, originalName);
    if (sourcePath != null && sourcePath.isNotEmpty) {
      await File(sourcePath).copy(targetPath);
    } else if (bytes != null) {
      await File(targetPath).writeAsBytes(bytes, flush: true);
    }
    return targetPath;
  }

  /// -----------------------
  /// CREATE FOLDER IN ROOT
  /// -----------------------
  void _addFolder({StorageItem? parent}) {
    TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          parent == null
              ? "Create New Folder"
              : "Create Folder in ${parent.name}",
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Folder name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                StorageItem? createdFolder;
                setState(() {
                  createdFolder = StorageItem(
                    name: controller.text.trim(),
                    isFolder: true,
                    children: [],
                    folderPath: _childFolderPath(
                      parent,
                      controller.text.trim(),
                    ),
                  );
                  if (parent == null) {
                    items.add(createdFolder!);
                  } else {
                    parent.children ??= [];
                    parent.children!.add(createdFolder!);
                  }
                });
                await _saveDocuments();
                final folderName =
                    createdFolder?.name ?? controller.text.trim();
                ActivityService.instance.addActivity(
                  RecentActivity(
                    description: "Created folder $folderName",
                    timestamp: DateTime.now(),
                    type: ActivityType.document,
                  ),
                );
              }
              // ignore: use_build_context_synchronously
              Navigator.pop(context);
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  /// -----------------------
  /// PICK FILE
  /// -----------------------
  Future<void> _pickFile({
    StorageItem? parent,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Upload tapped: opening file picker...")),
      );
    }
    debugPrint("Upload tapped: opening file picker...");

    final hasPermission = await _ensureFileAccessPermission();
    if (!hasPermission && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Storage permission denied. Trying picker anyway..."),
        ),
      );
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: type,
        allowedExtensions: allowedExtensions,
        withData: true,
      );
    } catch (e) {
      debugPrint("File picker error: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("File picker error: $e")));
      }
      return;
    }

    if (result == null) {
      debugPrint("File picker result is null (cancelled or failed).");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No file selected or picker failed.")),
        );
      }
      return;
    }

    debugPrint("Picked ${result.files.length} file(s).");
    for (var file in result.files) {
      final ext = file.name.split('.').last.toLowerCase();
      if (!(ext == "pdf" || ext == "png" || ext == "jpg" || ext == "jpeg")) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Only PDF or image files are supported: ${file.name}",
              ),
            ),
          );
        }
        continue;
      }
      if (file.path == null && file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("No data for ${file.name}")));
        }
        continue;
      }

      final item = await _buildStorageItem(file, ext, parent: parent);
      if (item == null) {
        continue;
      }
      setState(() {
        if (parent == null) {
          items.add(item);
        } else {
          parent.children ??= [];
          parent.children!.add(item);
        }
      });
      await _uploadItemToCloud(item);
    }
    await _saveDocuments();
  }

  Future<StorageItem?> _buildStorageItem(
    PlatformFile file,
    String ext, {
    StorageItem? parent,
  }) async {
    final sourcePath = file.path;
    final bytes = file.bytes;

    if (sourcePath == null && bytes == null) return null;

    try {
      final localPath = await _storeFileLocally(
        originalName: file.name,
        sourcePath: sourcePath,
        bytes: bytes,
      );
      return StorageItem(
        name: file.name,
        isFolder: false,
        extension: ext,
        path: localPath,
        folderPath: _folderPathForParent(parent),
      );
    } catch (_) {
      return null;
    }
  }

  void _showPickTypeOptions([StorageItem? parent]) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Align(
          alignment: Alignment.bottomRight,
          child: Container(
            width: 220,
            margin: const EdgeInsets.only(right: 16, bottom: 80),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(blurRadius: 10, color: Colors.black26),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: const Text("Pick PDF"),
                  onTap: () {
                    Navigator.pop(context);
                    Future.delayed(
                      const Duration(milliseconds: 200),
                      () => _pickFile(
                        parent: parent,
                        type: FileType.any,
                        allowedExtensions: null,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.image, color: Colors.blue),
                  title: const Text("Pick Image"),
                  onTap: () {
                    Navigator.pop(context);
                    Future.delayed(
                      const Duration(milliseconds: 200),
                      () => _pickFile(
                        parent: parent,
                        type: FileType.any,
                        allowedExtensions: null,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// -----------------------
  /// CAMERA / IMAGE PICKER
  /// -----------------------
  Future<void> _addImage({StorageItem? parent}) async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.camera);

    if (photo != null && photo.path.isNotEmpty) {
      CroppedFile? cropped;
      try {
        cropped = await ImageCropper().cropImage(
          sourcePath: photo.path,
          compressQuality: 95,
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Image',
              toolbarColor: kPrimaryColor,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: CropAspectRatioPreset.original,
              lockAspectRatio: false,
            ),
            IOSUiSettings(title: 'Crop Image'),
          ],
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Crop failed, using original photo. ($e)")),
          );
        }
      }
      if (cropped == null || cropped.path.isEmpty) {
        // If cropping was cancelled or failed, fall back to original photo.
        final localPath = await _storeFileLocally(
          originalName: photo.name,
          sourcePath: photo.path,
        );
        final ext = _extensionForName(photo.name);
        final imageItem = StorageItem(
          name: photo.name,
          isFolder: false,
          extension: ext,
          path: localPath,
          folderPath: _folderPathForParent(parent),
        );
        setState(() {
          if (parent == null) {
            items.add(imageItem);
          } else {
            parent.children ??= [];
            parent.children!.add(imageItem);
          }
        });
        await _saveDocuments();
        await _uploadItemToCloud(imageItem);
        return;
      }
      final localPath = await _storeFileLocally(
        originalName: photo.name,
        sourcePath: cropped.path,
      );
      final ext = _extensionForName(photo.name);
      final imageItem = StorageItem(
        name: photo.name,
        isFolder: false,
        extension: ext,
        path: localPath,
        folderPath: _folderPathForParent(parent),
      );
      setState(() {
        if (parent == null) {
          items.add(imageItem);
        } else {
          parent.children ??= [];
          parent.children!.add(imageItem);
        }
      });
      await _saveDocuments();
      await _uploadItemToCloud(imageItem);
    }
  }

  /// -----------------------
  /// FILE ICON
  /// -----------------------
  IconData getIconForExtension(String? ext) {
    switch (ext) {
      case "pdf":
        return Icons.picture_as_pdf;
      case "doc":
      case "docx":
        return Icons.description;
      case "png":
      case "jpg":
      case "jpeg":
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// -----------------------
  /// RENAME ITEM
  /// -----------------------
  void _renameItem(StorageItem item) {
    TextEditingController controller = TextEditingController(text: item.name);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item.isFolder ? "Rename Folder" : "Rename File"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "Enter new name"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final rawName = controller.text.trim();
              if (rawName.isEmpty) {
                Navigator.pop(context);
                return;
              }

              final normalizedName = item.isFolder
                  ? rawName
                  : _normalizedFileName(rawName, item.extension);
              String? updatedPath = item.path;

              if (!item.isFolder &&
                  item.path != null &&
                  item.path!.isNotEmpty) {
                final currentFile = File(item.path!);
                if (await currentFile.exists()) {
                  final targetPath = await _uniqueFilePath(
                    currentFile.parent,
                    normalizedName,
                  );
                  try {
                    final renamed = await currentFile.rename(targetPath);
                    updatedPath = renamed.path;
                  } catch (_) {
                    try {
                      await currentFile.copy(targetPath);
                      await currentFile.delete();
                      updatedPath = targetPath;
                    } catch (_) {}
                  }
                }
              }

              setState(() {
                item.name = normalizedName;
                if (!item.isFolder) {
                  item.extension = _extensionForName(normalizedName);
                  item.path = updatedPath;
                }
              });
              await _saveDocuments();
              // ignore: use_build_context_synchronously
              Navigator.pop(context);
            },
            child: const Text("Rename"),
          ),
        ],
      ),
    );
  }

  /// -----------------------
  /// GRID ITEM
  /// -----------------------
  Widget _buildGridItem(StorageItem item) {
    return InkWell(
      onTap: () {
        if (item.isFolder) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FolderScreen(
                folder: item,
                onRename: (item) => _showFileOptions(item),
                onAdd: (folder) => _showCreateOptions(folder),
                onDelete: (item) => _deleteItem(item),
                onScan: (file, {pageNumber}) =>
                    _scanFile(file, pageNumber: pageNumber),
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FileViewer(
                file: item,
                onScan: (file, {pageNumber}) =>
                    _scanFile(file, pageNumber: pageNumber),
              ),
            ),
          );
        }
      },
      onLongPress: () => _showFileOptions(item),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.isFolder
                  ? Icons.folder
                  : getIconForExtension(item.extension),
              size: 44,
              color: item.isFolder ? const Color(0xFFF5B301) : kPrimaryColor,
            ),
            const SizedBox(height: 10),
            Text(
              item.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: Color(0xFF374151),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// -----------------------
  /// FILTER CHIP
  /// -----------------------
  Widget _buildChip(String label) {
    final isSelected = _selectedFilter == label;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        backgroundColor: Colors.white,
        label: Text(label),
        selected: isSelected,
        selectedColor: kPrimaryColor,
        shape: StadiumBorder(
          side: BorderSide(
            color: isSelected ? kPrimaryColor : const Color(0xFFE5E7EB),
          ),
        ),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF374151),
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
        onSelected: (_) => setState(() => _selectedFilter = label),
      ),
    );
  }

  /// -----------------------
  /// FLOATING POPUP OPTIONS
  /// -----------------------
  void _showCreateOptions([StorageItem? parent]) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Align(
          alignment: Alignment.bottomRight,
          child: Container(
            width: 220,
            margin: const EdgeInsets.only(right: 16, bottom: 80),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(blurRadius: 10, color: Colors.black26),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.create_new_folder,
                    color: Colors.blue,
                  ),
                  title: const Text("Create Folder"),
                  onTap: () {
                    Navigator.pop(context);
                    _addFolder(parent: parent);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file, color: Colors.green),
                  title: const Text("Upload File"),
                  onTap: () {
                    Navigator.pop(context);
                    Future.delayed(
                      const Duration(milliseconds: 200),
                      () => _showPickTypeOptions(parent),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: Colors.blueGrey),
                  title: const Text("Scan Image"),
                  onTap: () {
                    Navigator.pop(context);
                    _addImage(parent: parent);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  //File options

  void _showFileOptions(StorageItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // keeps corners rounded
      isScrollControlled: true, // adjusts height based on content
      builder: (_) {
        return Container(
          width: 300,
          margin: const EdgeInsets.only(
            bottom: 600,
            right: 16,
            left: 16,
          ), // bottom and horizontal spacing
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min, // only take as much space as needed
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.pop(context);
                  _renameItem(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteItem(item);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  //File Delete

  bool _deleteRecursive(List<StorageItem> list, StorageItem target) {
    // Try removing directly from this level
    if (list.remove(target)) return true;

    // If not found, check in children recursively
    for (var item in list) {
      if (item.children != null) {
        if (_deleteRecursive(item.children!, target)) return true;
      }
    }
    return false; // not found
  }

  Future<void> _deleteFilesRecursive(StorageItem item) async {
    if (item.isFolder) {
      final children = item.children ?? const [];
      for (final child in children) {
        await _deleteFilesRecursive(child);
      }
    } else if (item.path != null && item.path!.isNotEmpty) {
      final file = File(item.path!);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> _deleteItem(StorageItem item) async {
    setState(() {
      _deleteRecursive(items, item);
    });
    await _deleteFilesRecursive(item);
    await _saveDocuments();
    final label = item.isFolder ? 'folder' : 'document';
    ActivityService.instance.addActivity(
      RecentActivity(
        description: "Deleted $label ${item.name}",
        timestamp: DateTime.now(),
        type: ActivityType.document,
      ),
    );
  }

  //open file

  // ignore: unused_element
  void _openFile(StorageItem item) {
    if (item.path != null) {
      OpenFile.open(item.path!);
    }
  }

  Future<bool> _ensureFileAccessPermission() async {
    if (!Platform.isAndroid) return true;

    final storageStatus = await Permission.storage.status;
    if (storageStatus.isGranted) return true;

    final requested = await Permission.storage.request();
    if (requested.isGranted) return true;

    final photosStatus = await Permission.photos.status;
    if (photosStatus.isGranted) return true;

    final photosRequested = await Permission.photos.request();
    if (photosRequested.isGranted) return true;

    return false;
  }

  Future<void> _scanFile(StorageItem item, {int? pageNumber}) async {
    if ((item.path == null || item.path!.isEmpty) && item.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("File path not found.")));
      return;
    }

    File? file;
    if (item.path != null && item.path!.isNotEmpty) {
      file = File(item.path!);
      if (!await file.exists()) {
        file = null;
      }
    }

    final loaderContext = await _showProcessingLoader();
    try {
      final ext = item.extension?.toLowerCase();
      final isImage = ext == "png" || ext == "jpg" || ext == "jpeg";
      final isPdf = ext == "pdf";
      if (!isPdf && !isImage) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Only PDF or image files can be scanned."),
          ),
        );
        return;
      }

      final request = http.MultipartRequest(
        "POST",
        Uri.parse("$_backendBaseUrl/upload"),
      );
      if (isPdf && pageNumber != null && pageNumber > 0) {
        request.fields["page"] = pageNumber.toString();
      }
      if (file != null) {
        request.files.add(
          await http.MultipartFile.fromPath("image", file.path),
        );
      } else if (item.bytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            "image",
            item.bytes!,
            filename: item.name,
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("File data not available.")),
        );
        return;
      }

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = json.decode(body);
        await _storeReferenceRanges(decoded["reference_ranges"]);
        final highlights = decoded["highlights"];
        final parsed = decoded["parsed"];
        final List<Map<String, dynamic>> parsedAbnormal = parsed is List
            ? parsed
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];
        // isImage / isPdf already computed before upload

        if (highlights != null &&
            (isPdf || isImage) &&
            highlights["boxes"] is List &&
            (highlights["boxes"] as List).isNotEmpty) {
          final List<Map<String, dynamic>> rawBoxes =
              (highlights["boxes"] as List).cast<Map<String, dynamic>>();
          final Set<String> abnormalTests = parsedAbnormal
              .map((item) => item["test"]?.toString())
              .whereType<String>()
              .map((t) => t.trim().toUpperCase())
              .where((t) => t.isNotEmpty)
              .toSet();
          List<Map<String, dynamic>> boxes = abnormalTests.isEmpty
              ? rawBoxes
              : rawBoxes.where((box) {
                  final test = box["test"]?.toString();
                  if (test == null || test.trim().isEmpty) return false;
                  return abnormalTests.contains(test.trim().toUpperCase());
                }).toList();
          if (boxes.isNotEmpty) {
            (highlights["image_width"] as num).toDouble();
            final double imageH = (highlights["image_height"] as num)
                .toDouble();
            boxes = boxes.where((box) {
              final h = (box["height"] as num?)?.toDouble() ?? 0;
              if (imageH <= 0) return true;
              return h <= imageH * 0.5;
            }).toList();
          }
          final String? renderedBase64 =
              highlights["rendered_image_base64"] as String?;
          final Uint8List? renderedBytes = renderedBase64 != null
              ? base64Decode(renderedBase64)
              : null;
          if (boxes.isEmpty) {
            showDialog(
              // ignore: use_build_context_synchronously
              context: context,
              builder: (_) => const AlertDialog(
                title: Text("No Highlights"),
                content: Text(
                  "Abnormal values were detected, but their positions could not be matched on the report image.",
                ),
              ),
            );
          } else {
            Navigator.push(
              // ignore: use_build_context_synchronously
              context,
              MaterialPageRoute(
                builder: (_) => ReportHighlightScreen(
                  imagePath: item.path ?? "",
                  imageWidth: (highlights["image_width"] as num).toDouble(),
                  imageHeight: (highlights["image_height"] as num).toDouble(),
                  boxes: boxes,
                  imageBytes: renderedBytes,
                  abnormalResults: parsedAbnormal,
                ),
              ),
            );
          }
        } else {
          final bool hasParsed = parsed is List && parsed.isNotEmpty;
          final String message = hasParsed
              ? "Abnormal values were detected, but they could not be located on the report image."
              : "No abnormal values were found to highlight on this report.";
          showDialog(
            // ignore: use_build_context_synchronously
            context: context,
            builder: (_) => AlertDialog(
              title: const Text("No Highlights"),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
              ],
            ),
          );
        }
      } else {
        String message = "Upload failed: ${response.statusCode}";
        try {
          final decoded = json.decode(body);
          if (decoded is Map) {
            final error = decoded["error"]?.toString();
            if (error != null && error.isNotEmpty) {
              message = error;
            }
            final trace = decoded["trace"]?.toString();
            if (trace != null && trace.isNotEmpty) {
              final firstLine = trace.split('\n').first.trim();
              if (firstLine.isNotEmpty && firstLine != error) {
                message = "$message ($firstLine)";
              }
            }
            final details = decoded["details"];
            if (details is Map && details.isNotEmpty) {
              final cmd = details["current_cmd"]?.toString();
              final exists = details["current_cmd_exists"];
              if (cmd != null && cmd.isNotEmpty && exists == false) {
                message = "$message (Tesseract not found at $cmd).";
              }
            }
          }
        } catch (_) {
          if (body.trim().isNotEmpty) {
            final snippet = body.trim().replaceAll('\n', ' ');
            message = "Upload failed: ${response.statusCode} ($snippet)";
          }
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Upload error: $e")));
    } finally {
      // ignore: use_build_context_synchronously
      _hideProcessingLoader(loaderContext);
    }
  }

  Future<BuildContext?> _showProcessingLoader() async {
    if (!mounted) return null;
    BuildContext? dialogContext;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return const AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Processing scan...",
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
    return dialogContext;
  }

  void _hideProcessingLoader(BuildContext? dialogContext) {
    if (dialogContext == null) return;
    if (!Navigator.of(dialogContext).canPop()) return;
    Navigator.of(dialogContext).pop();
  }

  Future<void> _storeReferenceRanges(dynamic ranges) async {
    if (ranges is! Map) return;
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(ranges);
    await prefs.setString("reference_ranges_json", encoded);
  }

  /// -----------------------
  /// UI
  /// -----------------------
  @override
  Widget build(BuildContext context) {
    List<StorageItem> filtered = items;

    if (_searchQuery.isNotEmpty) {
      filtered = filtered
          .where(
            (e) => e.name.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList();
    }

    if (_selectedFilter == "Images") {
      filtered = filtered
          .where((e) => ['png', 'jpg', 'jpeg'].contains(e.extension))
          .toList();
    }

    if (_selectedFilter == "PDF") {
      filtered = filtered.where((e) => e.extension == 'pdf').toList();
    }

    filtered.sort(
      (a, b) =>
          _sortAscending ? a.name.compareTo(b.name) : b.name.compareTo(a.name),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryColor, Color(0xFF3B82F6)],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Document Storage",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: const InputDecoration(
                  hintText: "Search documents...",
                  prefixIcon: Icon(Icons.search),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildChip("All"),
                _buildChip("Images"),
                _buildChip("PDF"),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1,
              ),
              itemCount: filtered.length,
              itemBuilder: (_, index) => _buildGridItem(filtered[index]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kPrimaryColor,
        onPressed: () => _showCreateOptions(),
        icon: const Icon(Icons.add),
        label: const Text("Add"),
        shape: const StadiumBorder(),
      ),
    );
  }
}
