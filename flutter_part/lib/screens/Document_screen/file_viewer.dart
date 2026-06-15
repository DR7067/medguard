import 'package:flutter/material.dart';
import 'package:flutter_part/screens/Document_screen/storage_item.dart';
import 'dart:io';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:open_file/open_file.dart';

const Color kPrimaryColor = Color(0xFF2563EB);

class FileViewer extends StatefulWidget {
  final StorageItem file;
  final Future<void> Function(StorageItem file, {int? pageNumber})? onScan;
  const FileViewer({super.key, required this.file, this.onScan});

  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  final PdfViewerController _pdfController = PdfViewerController();
  int _currentPage = 1;
  int _pageCount = 0;
  bool _isPopping = false;

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    if ((file.path == null || file.path!.isEmpty) && file.bytes == null) {
      return WillPopScope(
        onWillPop: () async {
          _isPopping = true;
          return true;
        },
        child: Scaffold(
          appBar: AppBar(title: Text(file.name)),
          body: const Center(child: Text("File not found")),
          floatingActionButton: _buildScanFab(context),
        ),
      );
    }

    final ext = file.extension?.toLowerCase();

    if (ext == 'pdf') {
      return WillPopScope(
        onWillPop: () async {
          _isPopping = true;
          return true;
        },
        child: Scaffold(
          appBar: AppBar(title: Text(file.name)),
          body: file.bytes != null
              ? SfPdfViewer.memory(
                  file.bytes!,
                  controller: _pdfController,
                  onPageChanged: (details) {
                    setState(() => _currentPage = details.newPageNumber);
                  },
                  onDocumentLoaded: (details) {
                    setState(() {
                      _pageCount = details.document.pages.count;
                    });
                  },
                )
              : SfPdfViewer.file(
                  File(file.path!),
                  controller: _pdfController,
                  onPageChanged: (details) {
                    setState(() => _currentPage = details.newPageNumber);
                  },
                  onDocumentLoaded: (details) {
                    setState(() {
                      _pageCount = details.document.pages.count;
                    });
                  },
                ),
          floatingActionButton: _buildScanFab(context),
        ),
      );
    }

    if (ext == 'png' || ext == 'jpg' || ext == 'jpeg') {
      return WillPopScope(
        onWillPop: () async {
          _isPopping = true;
          return true;
        },
        child: Scaffold(
          appBar: AppBar(title: Text(file.name)),
          body: Center(
            child: file.bytes != null
                ? Image.memory(file.bytes!)
                : Image.file(File(file.path!)),
          ),
          floatingActionButton: _buildScanFab(context),
        ),
      );
    }

    OpenFile.open(file.path!);

    return WillPopScope(
      onWillPop: () async {
        _isPopping = true;
        return true;
      },
      child: Scaffold(
        appBar: AppBar(title: Text(file.name)),
        body: const Center(child: Text("Opening file...")),
        floatingActionButton: _buildScanFab(context),
      ),
    );
  }

  Widget? _buildScanFab(BuildContext context) {
    if (widget.onScan == null) return null;

    return FloatingActionButton.extended(
      onPressed: () async {
        if (_isPopping) return;
        final ext = widget.file.extension?.toLowerCase();
        if (ext == 'pdf') {
          final pageNumber = await _promptPdfPage(context);
          if (pageNumber == null) return;
          await widget.onScan!(widget.file, pageNumber: pageNumber);
          return;
        }
        await widget.onScan!(widget.file);
      },
      icon: const Icon(Icons.document_scanner),
      label: const Text("Scan"),
    );
  }

  Future<int?> _promptPdfPage(BuildContext context) async {
    final controller = TextEditingController(text: _currentPage.toString());
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Scan PDF Page"),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: "Page number",
              helperText: _pageCount > 0
                  ? "1 - $_pageCount"
                  : "Enter a page number",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                final parsed = int.tryParse(controller.text.trim());
                Navigator.pop(dialogContext, parsed);
              },
              child: const Text("Scan"),
            ),
          ],
        );
      },
    );

    if (selected == null) return null;
    if (selected < 1) {
      _showPageError(context);
      return null;
    }
    if (_pageCount > 0 && selected > _pageCount) {
      _showPageError(context);
      return null;
    }
    return selected;
  }

  void _showPageError(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Invalid page number.")));
  }
}
