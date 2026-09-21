import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
Future<void> _processPdf(String inputPath, String password) async {
  setState(() {
    _status = 'Uploading to server...';
  });

  try {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('https://your-api.com/stamp'),
    );
    
    request.files.add(await http.MultipartFile.fromPath('pdf', inputPath));
    request.fields['password'] = password;
    
    var response = await request.send();
    
    if (response.statusCode == 200) {
      var bytes = await response.stream.toBytes();
      
      // Save to file
      Directory? outputDir = await getExternalStorageDirectory();
      String fileName = inputPath.split('/').last.replaceAll('.pdf', '_stamped.pdf');
      String outputPath = '${outputDir!.path}/$fileName';
      
      File outputFile = File(outputPath);
      await outputFile.writeAsBytes(bytes);
      
      setState(() {
        _status = '✓ Success!\n\n$outputPath';
        _outputPath = outputPath;
        _isProcessing = false;
      });
    } else {
      setState(() {
        _status = '✗ Server error';
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
