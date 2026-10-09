import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/widgets/practice_qcm_medical_illustration.dart';

void main() {
  const explanation =
      'IRM pelvienne : séquences T2.\n\n§IMAGE_SPEC§\n'
      '{"query":"rectal cancer T2 axial MRI","modality":"IRM T2",'
      '"purpose":"montrer la tumeur","image_type":"radiology_scan",'
      '"anatomy":"rectum","plane":"axial","required_features":["tumor"],'
      '"excluded_features":["book cover"]}'
      '\n\n§SOURCES§\nrevue|||Source|||Organisation|||2026|||https://example.org/a';
  test('all corrections hide JSON and preserve clinical text', () {
    expect(
      PracticeQcmImageMetadata.visibleText(explanation),
      'IRM pelvienne : séquences T2.',
    );
    expect(
      PracticeQcmImageMetadata.fromCorrection(explanation)?['image_type'],
      'radiology_scan',
    );
  });
  test('legacy correction image marker remains readable without URL trust', () {
    const prior =
        'Correction médicale.\n\n§IMAGES§\n'
        'Rectum|||https://upload.wikimedia.org/wikipedia/commons/a.jpg|||'
        'https://commons.wikimedia.org/wiki/Rectum';
    expect(PracticeQcmImageMetadata.visibleText(prior), 'Correction médicale.');
    final desc = PracticeQcmImageMetadata.legacyRequest(
      prior,
      'Quel est le signal IRM ?',
    );
    expect(desc?['query'], contains('Quel est le signal IRM ?'));
  });
  test('malformed image JSON never hides or crashes the correction', () {
    const incorrect =
        'Texte clair\n§IMAGE_SPEC§\n{invalid-json}\n§SOURCES§\nsource';
    expect(PracticeQcmImageMetadata.fromCorrection(incorrect), isNull);
    expect(PracticeQcmImageMetadata.visibleText(incorrect), 'Texte clair');
  });
  test('no metadata means no unexpected image search', () {
    expect(
      PracticeQcmImageMetadata.fromCorrection('Explication simple'),
      isNull,
    );
    expect(
      PracticeQcmImageMetadata.legacyRequest('Explication simple', 'QCM'),
      isNull,
    );
  });
  test(
    'old QCM with no image JSON can recover imaging intent and case context',
    () {
      final request = PracticeQcmImageMetadata.legacyRequest(
        'La séquence IRM T2 permet d’apprécier la tumeur.',
        'Quel aspect retrouve-t-on en IRM T2 ?',
        context: 'Cancer du rectum · TDM et IRM',
      );
      expect(request, isNotNull);
      expect(request!['image_type'], 'radiology_scan');
      expect((request['query'] as String).toLowerCase(), contains('rectum'));
    },
  );

  test(
    'historic rectal anatomy must not become tumor MRI just due to case topic',
    () {
      final request = PracticeQcmImageMetadata.legacyRequest(
        'Étudier les rapports anatomiques du mésorectum.\n\n§IMAGES§\n'
            'Orientation anatomique du rectum et sphincters|||https://example.org/bad.jpg',
        'Identifier les sphincters et le mésorectum',
        context: 'Cancer du rectum',
      );
      expect(request!['image_type'], 'anatomical_diagram');
      expect((request['query'] as String).toLowerCase(), contains('rectum'));
      expect(request['query'], isNot(contains('example.org')));
    },
  );

  test('old non-visual QCM keeps its correction and skips image lookups', () {
    expect(
      PracticeQcmImageMetadata.legacyRequest(
        'Le traitement antibiotique est indiqué.',
        'Quelle antibiothérapie prescrire ?',
        context: 'Cholécystite aiguë',
      ),
      isNull,
    );
  });
}
