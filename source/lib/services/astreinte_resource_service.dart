import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/hospitals.dart';
import '../models/shared_resource.dart';
import 'supabase_backend_service.dart';

/// Upload sécurisé des supports d'astreinte Sénior.
///
/// Le `kind` historique `astreinte_photo` est volontairement conservé pour
/// rester compatible avec les politiques RLS, les requêtes et les imports
/// déjà déployés. La collection accepte désormais aussi PDF, XLS et XLSX.
class AstreinteResourceService {
  AstreinteResourceService._();

  static final instance = AstreinteResourceService._();

  static const int maxBytes = 12 * 1024 * 1024;

  static const Set<String> _allowedExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'pdf',
    'xls',
    'xlsx',
  };

  SupabaseClient get _client => SupabaseBackendService.instance.client;

  Future<SharedResource> upload({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String hospital,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Session Supabase absente.');
    if (!kHospitals.contains(hospital)) {
      throw ArgumentError('Établissement invalide.');
    }
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('Fichier vide ou supérieur à 12 Mo.');
    }

    final extension = _safeExtension(fileName);
    if (!_allowedExtensions.contains(extension)) {
      throw ArgumentError(
        'Format non pris en charge. Utilisez JPG, PNG, WEBP, PDF, XLS ou XLSX.',
      );
    }

    final contentType = _normalizedMime(extension, mimeType);
    final hospitalSlot = hospital == kHospitalBouskoura
        ? 'hm6_bouskoura'
        : hospital == kHospitalRabat
            ? 'hm6_rabat'
            : 'hck_casa';
    final path =
        'astreinte/$hospitalSlot/${uid}_${DateTime.now().microsecondsSinceEpoch}.$extension';

    await _client.storage.from(SupabaseBackendService.sharedBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );

    try {
      final row = await _client
          .from('shared_resources')
          .insert({
            'kind': 'astreinte_photo',
            'hospital': hospital,
            'storage_path': path,
            'display_name': fileName,
            'mime_type': contentType,
            'uploaded_by': uid,
          })
          .select()
          .single();
      return SharedResource.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      await _client.storage
          .from(SupabaseBackendService.sharedBucket)
          .remove([path]);
      rethrow;
    }
  }

  static String _safeExtension(String fileName) {
    final clean = fileName.trim();
    final dot = clean.lastIndexOf('.');
    if (dot <= 0 || dot == clean.length - 1) return '';
    return clean
        .substring(dot + 1)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _normalizedMime(String extension, String requested) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      default:
        return requested.trim().isEmpty
            ? 'application/octet-stream'
            : requested.trim();
    }
  }
}
