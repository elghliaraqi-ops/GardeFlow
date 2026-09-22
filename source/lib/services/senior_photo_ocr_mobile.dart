import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

bool get seniorPhotoOcrSupported => true;

Future<List<Map<String, dynamic>>> recognizeSeniorPhoto(
  Uint8List bytes, {
  required String fileName,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('gardeflow_senior_ocr_');
  final extMatch = RegExp(r'\.([a-zA-Z0-9]{2,5})$').firstMatch(fileName);
  final ext = extMatch?.group(1)?.toLowerCase() ?? 'jpg';
  final file = File('${tempDir.path}/source.$ext');
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  try {
    await file.writeAsBytes(bytes, flush: true);
    final input = InputImage.fromFilePath(file.path);
    final recognized = await recognizer.processImage(input);

    final lines = <Map<String, dynamic>>[];
    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        lines.add({
          'text': line.text,
          'left': box.left,
          'top': box.top,
          'right': box.right,
          'bottom': box.bottom,
        });
      }
    }

    lines.sort((a, b) {
      final topA = (a['top'] as num?)?.toDouble() ?? 0;
      final topB = (b['top'] as num?)?.toDouble() ?? 0;
      final delta = topA - topB;
      if (delta.abs() > 8) return delta.sign.toInt();
      final leftA = (a['left'] as num?)?.toDouble() ?? 0;
      final leftB = (b['left'] as num?)?.toDouble() ?? 0;
      return leftA.compareTo(leftB);
    });
    return lines;
  } finally {
    await recognizer.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}
