import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';

void main() {
  runApp(const PdfStamperApp());
}

class PdfStamperApp extends StatelessWidget {
  const PdfStamperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Signature Stamper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const PdfStamperScreen(),
    );
  }
}

class PdfStamperScreen extends StatefulWidget {
  const PdfStamperScreen({super.key});

  @override
  State<PdfStamperScreen> createState() => _PdfStamperScreenState();
}

class _PdfStamperScreenState extends State<PdfStamperScreen> {
  String _status = 'Select a PDF file to stamp signature';
  bool _isProcessing = false;
  String? _outputPath;

  Future<void> _pickAndStampPdf() async {
    setState(() {
      _isProcessing = true;
      _status = 'Picking PDF file...';
    });

    try {
      // Request storage permission
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();

      // Pick PDF file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          _status = 'No file selected';
          _isProcessing = false;
        });
        return;
      }

      String inputPath = result.files.single.path!;
      setState(() {
        _status = 'Processing: ${result.files.single.name}\nPlease wait...';
      });

      // Stamp the PDF
      String? outputPath = await _stampSignature(inputPath);

      if (outputPath != null) {
        setState(() {
          _status = '✓ Success!\n\nStamped PDF saved to:\n$outputPath';
          _outputPath = outputPath;
          _isProcessing = false;
        });
      } else {
        setState(() {
          _status = '✗ No signature field found in PDF';
          _isProcessing = false;
        });
      }
    } catch (e) {
      setState(() {
        _status = '✗ Error: $e';
        _isProcessing = false;
      });
    }
  }

  Future<String?> _stampSignature(String inputPath) async {
    try {
      // Read input PDF
      File inputFile = File(inputPath);
      Uint8List bytes = await inputFile.readAsBytes();

      // Load PDF document
      PdfDocument document = PdfDocument(inputBytes: bytes);
      
      bool modified = false;

      // Iterate through all pages
      for (int i = 0; i < document.pages.count; i++) {
        PdfPage page = document.pages[i];
        
        // Get annotations (signature fields)
        if (page.annotations.count > 0) {
          for (int j = 0; j < page.annotations.count; j++) {
            PdfAnnotation annotation = page.annotations[j];
            
            // Check if it's a signature field
            if (annotation is PdfSignatureField) {
              // Get bounds of signature field
              Rect bounds = annotation.bounds;
              
              // Draw green tick mark
              _drawTickMark(page.graphics, bounds);
              
              modified = true;
            }
          }
        }
      }

      if (!modified) {
        document.dispose();
        return null;
      }

      // Save to output file
      Directory? outputDir = await getExternalStorageDirectory();
      if (outputDir == null) {
        outputDir = await getApplicationDocumentsDirectory();
      }

      String fileName = inputPath.split('/').last.replaceAll('.pdf', '_stamped.pdf');
      String outputPath = '${outputDir.path}/$fileName';

      File outputFile = File(outputPath);
      await outputFile.writeAsBytes(await document.save());
      document.dispose();

      return outputPath;
    } catch (e) {
      print('Error stamping PDF: $e');
      return null;
    }
  }

  void _drawTickMark(PdfGraphics graphics, Rect bounds) {
    double w = bounds.width;
    double h = bounds.height;
    
    double centerX = bounds.left + w / 2;
    double centerY = bounds.top + h / 2;
    
    // Tick mark points (relative to signature field)
    double p1x = centerX - w * 0.12;
    double p1y = centerY;
    double p2x = centerX - w * 0.02;
    double p2y = centerY + h * 0.23;
    double p3x = centerX + w * 0.14;
    double p3y = centerY - h * 0.26;

    // Draw black outline
    PdfPen outlinePen = PdfPen(PdfColor(0, 0, 0), width: w * 0.065);
    graphics.drawLine(outlinePen, Offset(p1x, p1y), Offset(p2x, p2y));
    graphics.drawLine(outlinePen, Offset(p2x, p2y), Offset(p3x, p3y));

    // Draw green tick
    PdfPen greenPen = PdfPen(PdfColor(0, 153, 38), width: w * 0.05);
    graphics.drawLine(greenPen, Offset(p1x, p1y), Offset(p2x, p2y));
    graphics.drawLine(greenPen, Offset(p2x, p2y), Offset(p3x, p3y));
  }

  Future<void> _openOutputFile() async {
    if (_outputPath != null) {
      await OpenFile.open(_outputPath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Signature Stamper'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(
                      Icons.edit_document,
                      size: 64,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'PDF Signature Stamper',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Stamp green tick on PDF signature fields',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _pickAndStampPdf,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_isProcessing ? 'Processing...' : 'Select PDF File'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Status:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            _status,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_outputPath != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _openOutputFile,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Stamped PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
