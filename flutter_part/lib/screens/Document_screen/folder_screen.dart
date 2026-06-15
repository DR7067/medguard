import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_part/screens/Document_screen/file_viewer.dart';
import 'package:flutter_part/screens/Document_screen/storage_item.dart';

const Color kPrimaryColor = Color(0xFF2563EB);

class FolderScreen extends StatelessWidget {
  final StorageItem folder;
  final Function(StorageItem?) onAdd;
  final Function(StorageItem) onRename;
  final Function(StorageItem) onDelete;
  final Future<void> Function(StorageItem file, {int? pageNumber}) onScan;

  const FolderScreen({
    super.key,
    required this.folder,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final children = folder.children ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(folder.name), backgroundColor: kPrimaryColor),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
        ),
        itemCount: children.length,
        itemBuilder: (_, i) {
          final item = children[i];
          final isImage =
              item.extension == 'png' ||
              item.extension == 'jpg' ||
              item.extension == 'jpeg';

          return InkWell(
            onTap: () {
              if (item.isFolder) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FolderScreen(
                      folder: item,
                      onAdd: onAdd,
                      onRename: onRename,
                      onDelete: onDelete,
                      onScan: onScan,
                    ),
                  ),
                );
              } else if (item.path != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FileViewer(
                      file: item,
                      onScan: (file, {pageNumber}) =>
                          onScan(file, pageNumber: pageNumber),
                    ),
                  ),
                );
              }
            },
            onLongPress: () => onRename(item),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                isImage && item.path != null
                    ? Image.file(File(item.path!), height: 50, width: 50)
                    : Icon(
                        item.isFolder ? Icons.folder : Icons.insert_drive_file,
                        size: 50,
                      ),
                const SizedBox(height: 6),
                Text(item.name, overflow: TextOverflow.ellipsis),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => onAdd(folder),
        child: const Icon(Icons.add),
      ),
    );
  }
}
