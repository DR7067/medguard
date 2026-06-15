import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../Medicine_screen/medicine.dart';

class ExpiryScannerPage extends StatefulWidget {
  const ExpiryScannerPage({super.key});

  @override
  State<ExpiryScannerPage> createState() => _ExpiryScannerPageState();
}

class _ExpiryScannerPageState extends State<ExpiryScannerPage> {
  String barcodeResult = '';
  String expiryDate = '';
  bool isScanning = true;

  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void dispose() {
    textRecognizer.close();
    super.dispose();
  }

  Future<void> processImage(InputImage image) async {
    final recognizedText = await textRecognizer.processImage(image);
    for (TextBlock block in recognizedText.blocks) {
      final text = block.text;
      final match = RegExp(r'(0?[1-9]|1[0-2])[/.-]\d{2,4}').firstMatch(text);
      if (match != null) {
        setState(() {
          expiryDate = match.group(0)!;
        });
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Medicine')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) async {
              final code = capture.barcodes.isNotEmpty
                  ? capture.barcodes.first.rawValue
                  : null;
              if (code != null && isScanning) {
                setState(() {
                  barcodeResult = code;
                  isScanning = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Barcode scanned: $barcodeResult')),
                );
              }
            },
          ),
          if (!isScanning)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.all(20),
                color: Colors.white70,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Barcode: $barcodeResult'),
                    const SizedBox(height: 10),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Enter Expiry Date',
                        hintText: 'MM/YYYY',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => expiryDate = val,
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        final med = Medicine(
                          name: 'Unknown',
                          type: MedicineType.tablet,
                          expiryDate:
                              DateTime.tryParse('01/$expiryDate') ??
                              DateTime.now(),
                        );
                        Navigator.pop(context, med);
                      },
                      child: const Text('Save Medicine'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
