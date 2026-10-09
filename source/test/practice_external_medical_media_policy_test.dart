import 'package:flutter_test/flutter_test.dart';
import 'package:huim6_planning/models/practice_external_medical_media_policy.dart';

void main() {
  const id = '12345678-1234-4234-a234-123456789abc';
  test('only matched Wikimedia and Openverse HTTPS previews are displayed', () {
    expect(isSupportedExternalMedicalPreview(
      Uri.parse('https://upload.wikimedia.org/example.png'),
      Uri.parse('https://commons.wikimedia.org/wiki/File:Example.png')),true);
    expect(isSupportedExternalMedicalPreview(
      Uri.parse('https://api.openverse.org/v1/images/$id/thumb/'),
      Uri.parse('https://openverse.org/image/$id')),true);
    expect(isSupportedExternalMedicalPreview(
      Uri.parse('https://api.openverse.org/v1/images/$id/thumb/'),
      Uri.parse('https://openverse.org/image/11111111-1111-4111-8111-111111111111')),false);
    expect(isSupportedExternalMedicalPreview(
      Uri.parse('http://api.openverse.org/v1/images/$id/thumb/'),
      Uri.parse('https://openverse.org/image/$id')),false);
    expect(isSupportedExternalMedicalPreview(
      Uri.parse('https://malicious.example/image.png'),
      Uri.parse('https://openverse.org/image/$id')),false);
  });
}
