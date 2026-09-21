import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Un type de garde : Service/Urgences × Jour/24H/Nuit, plus Congé.
class ShiftType {
  final String id;
  final String label;
  final String? start; // null pour Congé (pas de notification associée)
  final String? end;
  final Color color;
  final Color textColor;
  final IconData icon;

  const ShiftType({
    required this.id,
    required this.label,
    required this.start,
    required this.end,
    required this.color,
    required this.textColor,
    required this.icon,
  });

  bool get hasSchedule => start != null;
}

/// Catalogue statique de tous les types de garde, équivalent à `shiftInfo` côté web.
class ShiftCatalog {
  ShiftCatalog._();

  static const serviceJour = ShiftType(
    id: 'service-jour',
    label: 'Jour',
    start: '08:00',
    end: '20:00',
    color: AppColors.serviceJour,
    textColor: AppColors.serviceJourText,
    icon: Icons.wb_sunny_outlined,
  );

  static const service24h = ShiftType(
    id: 'service-24h',
    label: '24H',
    start: '08:00',
    end: '08:00',
    color: AppColors.service24h,
    textColor: AppColors.service24hText,
    icon: Icons.brightness_medium_outlined,
  );

  static const serviceNuit = ShiftType(
    id: 'service-nuit',
    label: 'Nuit',
    start: '20:00',
    end: '08:00',
    color: AppColors.serviceNuit,
    textColor: AppColors.serviceNuitText,
    icon: Icons.nightlight_outlined,
  );

  static const urgJour = ShiftType(
    id: 'urg-jour',
    label: 'Jour',
    start: '08:00',
    end: '20:00',
    color: AppColors.urgJour,
    textColor: AppColors.urgJourText,
    icon: Icons.wb_sunny_outlined,
  );

  static const urg24h = ShiftType(
    id: 'urg-24h',
    label: '24H',
    start: '08:00',
    end: '08:00',
    color: AppColors.urg24h,
    textColor: AppColors.urg24hText,
    icon: Icons.brightness_medium_outlined,
  );

  static const urgNuit = ShiftType(
    id: 'urg-nuit',
    label: 'Nuit',
    start: '20:00',
    end: '08:00',
    color: AppColors.urgNuit,
    textColor: AppColors.urgNuitText,
    icon: Icons.nightlight_outlined,
  );

  static const conge = ShiftType(
    id: 'conge',
    label: 'Congé',
    start: null,
    end: null,
    color: AppColors.conge,
    textColor: AppColors.congeText,
    icon: Icons.beach_access_outlined,
  );

  static const all = <ShiftType>[
    serviceJour, service24h, serviceNuit,
    urgJour, urg24h, urgNuit,
    conge,
  ];

  static ShiftType byId(String id) => all.firstWhere((s) => s.id == id);
}
