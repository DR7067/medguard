import 'dart:typed_data';

class StorageItem {
  String? id;
  String name;
  bool isFolder;
  String? extension;
  String? path;
  Uint8List? bytes;
  List<StorageItem>? children;
  List<String>? folderPath;
  String? storagePath;
  String? downloadUrl;
  int? uploadedAtMs;

  StorageItem({
    this.id,
    required this.name,
    required this.isFolder,
    this.extension,
    this.path,
    this.bytes,
    this.children,
    this.folderPath,
    this.storagePath,
    this.downloadUrl,
    this.uploadedAtMs,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isFolder': isFolder,
      'extension': extension,
      'path': path,
      'children': children?.map((child) => child.toJson()).toList(),
      'folderPath': folderPath,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'uploadedAtMs': uploadedAtMs,
    };
  }

  factory StorageItem.fromJson(Map<String, dynamic> json) {
    final rawChildren = json['children'];
    return StorageItem(
      id: json['id']?.toString(),
      name: (json['name'] ?? '').toString(),
      isFolder: json['isFolder'] == true,
      extension: json['extension']?.toString(),
      path: json['path']?.toString(),
      children: rawChildren is List
          ? rawChildren
                .whereType<Map>()
                .map(
                  (item) =>
                      StorageItem.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : null,
      folderPath: (json['folderPath'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      storagePath: json['storagePath']?.toString(),
      downloadUrl: json['downloadUrl']?.toString(),
      uploadedAtMs: (json['uploadedAtMs'] as num?)?.toInt(),
    );
  }
}
