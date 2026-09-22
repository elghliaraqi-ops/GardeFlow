import 'dart:typed_data';

bool get seniorPhotoOcrSupported => false;

Future<List<Map<String, dynamic>>> recognizeSeniorPhoto(
  Uint8List bytes, {
  required String fileName,
}) {
  throw UnsupportedError(
    'La reconnaissance automatique des photos est disponible sur Android et iOS.',
  );
}
