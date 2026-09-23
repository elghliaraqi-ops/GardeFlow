import 'package:flutter/material.dart';

const String kDirectoryCategoryJuniors = 'medecins-juniors';
const String kDirectoryCategorySeniors = 'medecins-seniors';
const String kDirectoryCategoryNurses = 'infirmiers';
const String kDirectoryCategoryFleet = 'flottes';
const String kDirectoryCategoryMajorsSupervisors = 'majors-superviseurs';
const String kDirectoryCategoryExtensions = 'extensions';

const List<String> kManualDirectoryCategoryIds = [
  kDirectoryCategorySeniors,
  kDirectoryCategoryNurses,
  kDirectoryCategoryFleet,
  kDirectoryCategoryMajorsSupervisors,
  kDirectoryCategoryExtensions,
];

const Map<String, String> kDirectoryCategoryLabels = {
  kDirectoryCategoryJuniors: 'Médecins Juniors',
  kDirectoryCategorySeniors: 'Médecins Séniors',
  kDirectoryCategoryNurses: 'Infirmiers',
  kDirectoryCategoryFleet: 'Flottes',
  kDirectoryCategoryMajorsSupervisors: 'Majors / Superviseurs',
  kDirectoryCategoryExtensions: 'Extensions',
};

String directoryCategoryLabel(String id) => kDirectoryCategoryLabels[id] ?? id;

class DirectoryContact {
  final String id;
  final String name;
  final String phone;
  final String hospital;
  final String? service;
  final String? gradeLabel;
  final bool isAdmin;
  final String categoryId;
  final bool isManual;

  DirectoryContact({
    this.id = '',
    required this.name,
    required this.phone,
    required this.hospital,
    this.service,
    this.gradeLabel,
    this.isAdmin = false,
    this.categoryId = '',
    this.isManual = false,
  });

  String get initials {
    final cleaned = name.replaceFirst(RegExp(r'^Dr\.\s*', caseSensitive: false), '').trim();
    final parts = cleaned.split(RegExp(r'\s+'));
    final first = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : '';
    final second = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return (first + second).toUpperCase();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'hospital': hospital,
        'service': service,
        'gradeLabel': gradeLabel,
        'isAdmin': isAdmin,
        'categoryId': categoryId,
        'isManual': isManual,
      };

  factory DirectoryContact.fromJson(Map<String, dynamic> json) => DirectoryContact(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        phone: (json['phone'] as String?) ?? '',
        hospital: (json['hospital'] as String?) ?? '',
        service: json['service'] as String?,
        gradeLabel: json['gradeLabel'] as String?,
        isAdmin: json['isAdmin'] as bool? ?? false,
        categoryId: (json['categoryId'] as String?) ?? '',
        isManual: json['isManual'] as bool? ?? false,
      );
}

class DirectorySection {
  final String id;
  final String label;
  final Color color;
  final Color textColor;
  final List<DirectoryContact> contacts;

  DirectorySection({
    required this.id,
    required this.label,
    required this.color,
    required this.textColor,
    required this.contacts,
  });
}
