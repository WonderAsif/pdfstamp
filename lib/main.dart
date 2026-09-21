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
  String? _pendingPdfPath;

  Future<void> _pickAndStampPdf() async {
    setState(() {
      _isProcessing = true;
      _status = 'Picking PDF file...';
    });

    try {
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();

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
      
      bool isEncrypted = await _checkIfEncrypted(inputPath);
      
      if (isEncrypted) {
        _pendingPdfPath = inputPath;
        _showPasswordDialog();
      } else {
        _processPdf(inputPath, '');
      }
    } catch (e) {
      setState(() {
        _status = '✗ Error: $e';
        _isProcessing = false;
      });
    }
  }

  Future<bool> _checkIfEncrypted(String path) async {
    try {
      File file = File(path);
      Uint8List bytes = await file.readAsBytes();
      PdfDocument document = PdfDocument(inputBytes: bytes);
      document.dispose();
      return false;
    } catch (e) {
      return true;
    }
  }

  void _showPasswordDialog() {
    TextEditingController passwordController = TextEditingController();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Password Protected PDF'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('This PDF is password protected. Please enter the password:'),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _status = 'Cancelled';
                  _isProcessing = false;
                });
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _processPdf(_pendingPdfPath!, passwordController.text);
              },
              child: const Text('Unlock'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _processPdf(String inputPath, String password) async {
    setState(() {
      _status = 'Processing...\nPlease wait...';
    });

    try {
      String? outputPath = await _stampSignature(inputPath, password);

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

  Future<String?> _stampSignature(String inputPath, String password) async {
    try {
      File inputFile = File(inputPath);
      Uint8List bytes = await inputFile.readAsBytes();

      PdfDocument document;
      
      if (password.isNotEmpty) {
        document = PdfDocument(inputBytes: bytes, password: password);
      } else {
        document = PdfDocument(inputBytes: bytes);
      }
      
      bool modified = false;

      // Iterate through all pages
      for (int i = 0; i < document.pages.count; i++) {
        PdfPage page = document.pages[i];
        
        // Check for annotations (signature fields)
        if (page.annotations.count > 0) {
          for (int j = 0; j < page.annotations.count; j++) {
            PdfAnnotation annotation = page.annotations[j];
            
            // Check if it's a signature field
            if (annotation is PdfSignatureField || 
                annotation.toString().contains('Signature') ||
                _isSignatureField(annotation)) {
              
              Rect bounds = annotation.bounds;
              
              // Scrub the appearance - change text and colors
              _scrubAppearance(annotation);
              
              // Draw the tick mark
              _drawTickMark(page.graphics, bounds);
              
              modified = true;
            }
          }
        }
        
        // Also check for form fields (signature fields are form fields)
        if (document.form != null && document.form.fields.count > 0) {
          for (int j = 0; j < document.form.fields.count; j++) {
            PdfField field = document.form.fields[j];
            
            if (field is PdfSignatureField) {
              // Get the page and bounds
              Rect bounds = field.bounds;
              
              // Draw tick on the page where signature field is located
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
      throw Exception('Failed to process PDF: $e');
    }
  }

  bool _isSignatureField(PdfAnnotation annotation) {
    // Check various ways to identify signature fields
    try {
      String annotString = annotation.toString().toLowerCase();
      return annotString.contains('sig') || 
             annotString.contains('signature') ||
             annotation is PdfSignatureField;
    } catch (e) {
      return false;
    }
  }

  void _scrubAppearance(PdfAnnotation annotation) {
    try {
      // Try to modify the appearance - this is complex in Flutter
      // Syncfusion PDF doesn't directly expose appearance stream editing
      // But we can flatten the annotation which removes the "Not Verified" text
      
      // Set flags to make it appear as valid
      annotation.flatten = true;
    } catch (e) {
      print('Error scrubbing appearance: $e');
    }
  }

  void _drawTickMark(PdfGraphics graphics, Rect bounds) {
    double w = bounds.width;
    double h = bounds.height;
    
    // Calculate points based on original Python code percentages
    double p1x = bounds.left + w * 0.38;
    double p1y = bounds.top + h * 0.45;
    double p2x = bounds.left + w * 0.48;
    double p2y = bounds.top + h * 0.22;
    double p3x = bounds.left + w * 0.64;
    double p3y = bounds.top + h * 0.76;

    double greenW = w * 0.05;
    double outlineW = greenW + (w * 0.015);
    double shadowX = w * 0.015;
    double shadowY = h * 0.025;

    // Draw shadow (black outline)
    PdfPen shadowPen = PdfPen(PdfColor(0, 0, 0), width: outlineW);
    graphics.drawLine(shadowPen, 
      Offset(p1x + shadowX, p1y + shadowY), 
      Offset(p2x + shadowX, p2y + shadowY));
    graphics.drawLine(shadowPen, 
      Offset(p2x + shadowX, p2y + shadowY), 
      Offset(p3x + shadowX, p3y + shadowY));

    // Draw black outline
    PdfPen outlinePen = PdfPen(PdfColor(0, 0, 0), width: outlineW);
    graphics.drawLine(outlinePen, Offset(p1x, p1y), Offset(p2x, p2y));
    graphics.drawLine(outlinePen, Offset(p2x, p2y), Offset(p3x, p3y));

    // Draw green tick
    PdfPen greenPen = PdfPen(PdfColor(0, 153, 38), width: greenW);
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
                    const Icon(Icons.edit_document, size: 64, color: Colors.green),
                    const SizedBox(height: 16),
                    Text('PDF Signature Stamper',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('Stamp green tick on PDF signature fields',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _pickAndStampPdf,
              icon: _isProcessing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file),
              label: Text(_isProcessing ? 'Processing...' : 'Select PDF File'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Status:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(_status, style: const TextStyle(fontSize: 14)),
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
