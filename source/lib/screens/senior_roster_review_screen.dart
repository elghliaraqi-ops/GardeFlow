import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/senior_oncall_import.dart';
import '../models/shared_resource.dart';
import '../services/supabase_backend_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class SeniorRosterReviewScreen extends StatefulWidget {
  final SharedResource resource;

  const SeniorRosterReviewScreen({
    super.key,
    required this.resource,
  });

  @override
  State<SeniorRosterReviewScreen> createState() => _SeniorRosterReviewScreenState();
}

class _SeniorRosterReviewScreenState extends State<SeniorRosterReviewScreen> {
  final _backend = SupabaseBackendService.instance;
  SeniorOnCallImport? _import;
  List<_EditableSeniorRow> _rows = <_EditableSeniorRow>[];
  bool _loading = true;
  bool _publishing = false;
  bool _reanalyzing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceAnalyze = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = !forceAnalyze;
      _reanalyzing = forceAnalyze;
      _error = null;
    });

    try {
      SeniorOnCallImport? import;
      if (!forceAnalyze) {
        import = await _backend.fetchSeniorOnCallImportForResource(
          widget.resource.id,
        );
      }
      import ??= await _backend.analyzeSeniorRosterPhoto(widget.resource.id);
      if (!mounted) return;
      setState(() {
        _import = import;
        _rows = import!.draftRows
            .map((row) => _EditableSeniorRow.fromMap(
                  row,
                  fallbackService: import!.detectedService,
                ))
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Analyse impossible : $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _reanalyzing = false;
        });
      }
    }
  }

  void _addRow() {
    final service = _import?.detectedService ?? '';
    setState(() {
      _rows.add(_EditableSeniorRow(
        name: '',
        service: service,
        phone: '',
        datesText: '',
        confidence: 1,
      ));
    });
  }

  void _removeRow(int index) {
    setState(() => _rows.removeAt(index));
  }

  List<String>? _parseDates(
    String raw, {
    required int? fallbackMonth,
    required int? fallbackYear,
  }) {
    final values = raw
        .split(RegExp(r'[,;\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final result = <String>[];
    for (final value in values) {
      DateTime? parsed;

      final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
      if (iso != null) {
        parsed = DateTime.tryParse(value);
      } else {
        final full = RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$')
            .firstMatch(value);
        if (full != null) {
          final day = int.parse(full.group(1)!);
          final month = int.parse(full.group(2)!);
          final year = int.parse(full.group(3)!);
          final candidate = DateTime(year, month, day);
          if (candidate.year == year &&
              candidate.month == month &&
              candidate.day == day) {
            parsed = candidate;
          }
        } else {
          final short = RegExp(r'^(\d{1,2})[./-](\d{1,2})$')
              .firstMatch(value);
          if (short != null && fallbackYear != null) {
            final day = int.parse(short.group(1)!);
            final month = int.parse(short.group(2)!);
            final candidate = DateTime(fallbackYear, month, day);
            if (candidate.year == fallbackYear &&
                candidate.month == month &&
                candidate.day == day) {
              parsed = candidate;
            }
          } else {
            final dayOnly = int.tryParse(value);
            if (dayOnly != null &&
                fallbackMonth != null &&
                fallbackYear != null) {
              final candidate = DateTime(fallbackYear, fallbackMonth, dayOnly);
              if (candidate.year == fallbackYear &&
                  candidate.month == fallbackMonth &&
                  candidate.day == dayOnly) {
                parsed = candidate;
              }
            }
          }
        }
      }

      if (parsed == null) return null;
      result.add(
        '${parsed.year.toString().padLeft(4, '0')}-'
        '${parsed.month.toString().padLeft(2, '0')}-'
        '${parsed.day.toString().padLeft(2, '0')}',
      );
    }

    return result.toSet().toList()..sort();
  }

  Future<void> _publish() async {
    final import = _import;
    if (import == null || _publishing) return;

    final payload = <Map<String, dynamic>>[];
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final name = row.name.trim();
      final service = row.service.trim();
      final phone = row.phone.trim();
      if (name.isEmpty && service.isEmpty && row.datesText.trim().isEmpty) {
        continue;
      }
      if (name.isEmpty || service.isEmpty) {
        _showError('Ligne ${i + 1} : le nom et le service sont obligatoires.');
        return;
      }

      final dates = _parseDates(
        row.datesText,
        fallbackMonth: import.detectedMonth,
        fallbackYear: import.detectedYear,
      );
      if (dates == null || dates.isEmpty) {
        _showError(
          'Ligne ${i + 1} : vérifiez les dates. Formats acceptés : '
          'JJ/MM/AAAA, AAAA-MM-JJ, JJ/MM ou jour seul si le mois est détecté.',
        );
        return;
      }

      payload.add({
        'name': name,
        'service': service,
        'phone': phone,
        'dates': dates,
        'confidence': row.confidence,
      });
    }

    if (payload.isEmpty) {
      _showError('Ajoutez au moins une astreinte avant de publier.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publier les astreintes ?'),
        content: Text(
          '${payload.length} ligne${payload.length > 1 ? 's' : ''} '
          'sera${payload.length > 1 ? 'ont' : ''} intégrée${payload.length > 1 ? 's' : ''} '
          'au calendrier Sénior. Les numéros disponibles seront ajoutés à l’annuaire sans doublon.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded),
            label: const Text('Valider et publier'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _publishing = true);
    try {
      final result = await _backend.publishSeniorOnCallImport(
        importId: import.id,
        rows: payload,
      );
      if (!mounted) return;
      final roster = (result['roster_rows'] as num?)?.toInt() ?? payload.length;
      final contacts =
          (result['directory_contacts_added'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$roster ligne${roster > 1 ? 's' : ''} publiée${roster > 1 ? 's' : ''} · '
            '$contacts nouveau${contacts > 1 ? 'x' : ''} contact${contacts > 1 ? 's' : ''}.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        _showError('Publication impossible : $e');
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _engineLabel(String value) {
    switch (value) {
      case 'openai_vision':
        return 'Analyse visuelle';
      case 'tesseract_supabase_ai':
        return 'OCR + analyse structurée';
      case 'manual_review_required':
        return 'Vérification manuelle requise';
      default:
        return value.isEmpty ? 'Analyse' : value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle('Vérifier l’analyse'),
        actions: [
          IconButton(
            tooltip: 'Réanalyser la photo',
            onPressed: _loading || _reanalyzing || _publishing
                ? null
                : () => _load(forceAnalyze: true),
            icon: _reanalyzing
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome_rounded),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.sm,
                  AppSpace.lg,
                  AppSpace.md,
                ),
                child: FilledButton.icon(
                  onPressed: _publishing ? null : _publish,
                  icon: _publishing
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.publish_rounded),
                  label: Text(
                    _publishing ? 'Publication…' : 'Valider et publier',
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.document_scanner_outlined,
                size: 48,
                color: AppColors.warning,
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.ink),
              ),
              const SizedBox(height: AppSpace.md),
              FilledButton.icon(
                onPressed: () => _load(forceAnalyze: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final import = _import!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        110,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.lgR,
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: AppColors.brand,
                    size: 21,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.resource.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _InfoChip(
                    icon: Icons.memory_rounded,
                    label: _engineLabel(import.analysisEngine),
                  ),
                  if (import.detectedService.isNotEmpty)
                    _InfoChip(
                      icon: Icons.medical_services_rounded,
                      label: import.detectedService,
                    ),
                  if (import.detectedMonth != null &&
                      import.detectedYear != null)
                    _InfoChip(
                      icon: Icons.calendar_month_rounded,
                      label:
                          '${import.detectedMonth!.toString().padLeft(2, '0')}/${import.detectedYear}',
                    ),
                  _InfoChip(
                    icon: Icons.analytics_outlined,
                    label:
                        'Confiance ${(import.confidence * 100).round()} %',
                  ),
                ],
              ),
            ],
          ),
        ),
        if (import.warnings.isNotEmpty) ...[
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(
                AppColors.isDarkMode ? 0.16 : 0.10,
              ),
              borderRadius: AppRadius.mdR,
              border: Border.all(
                color: AppColors.warning.withOpacity(0.55),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warning,
                      size: 20,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'Points à vérifier',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                for (final warning in import.warnings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $warning',
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                'Données extraites',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_rows.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpace.xl),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppRadius.lgR,
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  size: 42,
                  color: AppColors.inkFaint,
                ),
                const SizedBox(height: 9),
                Text(
                  'Aucune ligne fiable n’a été reconnue automatiquement.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Ajoutez les lignes manuellement ou relancez l’analyse. '
                  'Rien n’est publié sans votre validation.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        for (var i = 0; i < _rows.length; i++)
          _DraftRowCard(
            key: ValueKey('senior-draft-$i-${_rows[i].name}'),
            index: i,
            row: _rows[i],
            onDelete: () => _removeRow(i),
          ),
      ],
    );
  }
}

class _EditableSeniorRow {
  String name;
  String service;
  String phone;
  String datesText;
  double confidence;

  _EditableSeniorRow({
    required this.name,
    required this.service,
    required this.phone,
    required this.datesText,
    required this.confidence,
  });

  factory _EditableSeniorRow.fromMap(
    Map<String, dynamic> map, {
    required String fallbackService,
  }) {
    final rawDates = map['dates'];
    final dates = rawDates is List
        ? rawDates.map((e) => e.toString()).toList()
        : const <String>[];
    return _EditableSeniorRow(
      name: (map['name'] as String?) ?? '',
      service: ((map['service'] as String?) ?? '').trim().isEmpty
          ? fallbackService
          : (map['service'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
      datesText: dates.map(_displayDate).join(', '),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.5,
    );
  }

  static String _displayDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd/MM/yyyy').format(parsed);
  }
}

class _DraftRowCard extends StatelessWidget {
  final int index;
  final _EditableSeniorRow row;
  final VoidCallback onDelete;

  const _DraftRowCard({
    super.key,
    required this.index,
    required this.row,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: AppColors.brand,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Confiance ${(row.confidence * 100).round()} %',
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Supprimer cette ligne',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: row.name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nom du médecin',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            onChanged: (value) => row.name = value,
          ),
          const SizedBox(height: AppSpace.sm),
          TextFormField(
            initialValue: row.service,
            decoration: const InputDecoration(
              labelText: 'Service / type d’astreinte',
              prefixIcon: Icon(Icons.medical_services_outlined),
            ),
            onChanged: (value) => row.service = value,
          ),
          const SizedBox(height: AppSpace.sm),
          TextFormField(
            initialValue: row.phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Numéro (facultatif)',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            onChanged: (value) => row.phone = value,
          ),
          const SizedBox(height: AppSpace.sm),
          TextFormField(
            initialValue: row.datesText,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Dates de garde',
              hintText: '01/09/2026, 08/09/2026, 15/09/2026',
              prefixIcon: Icon(Icons.event_outlined),
            ),
            onChanged: (value) => row.datesText = value,
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        borderRadius: AppRadius.pillR,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.brand),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: AppColors.inkSoft,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
