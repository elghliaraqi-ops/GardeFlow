import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/shift_type.dart';
import '../services/supabase_backend_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class AdminDisciplinaryAssignmentScreen extends StatefulWidget {
  final String? initialDoctorId;

  const AdminDisciplinaryAssignmentScreen({
    super.key,
    this.initialDoctorId,
  });

  @override
  State<AdminDisciplinaryAssignmentScreen> createState() =>
      _AdminDisciplinaryAssignmentScreenState();
}

class _AdminDisciplinaryAssignmentScreenState
    extends State<AdminDisciplinaryAssignmentScreen> {
  final _reasonController = TextEditingController();
  final _doctorSearchController = TextEditingController();
  final List<_DisciplinaryDraft> _drafts = [
    _DisciplinaryDraft(date: DateTime.now(), shiftId: 'urg-24h'),
  ];

  String? _doctorId;
  String _doctorSearch = '';
  bool _submitting = false;
  String? _error;

  static const _shiftIds = <String>[
    'urg-jour',
    'urg-nuit',
    'urg-24h',
    'service-jour',
    'service-nuit',
    'service-24h',
  ];

  @override
  void initState() {
    super.initState();
    _doctorId = widget.initialDoctorId;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _doctorSearchController.dispose();
    super.dispose();
  }

  String _normalize(String value) {
    var s = value.toLowerCase();
    const replacements = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a',
      'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      '’': ' ', "'": ' ', '-': ' ',
    };
    for (final e in replacements.entries) {
      s = s.replaceAll(e.key, e.value);
    }
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _dateKey(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);

  Future<void> _pickDate(int index) async {
    final current = _drafts[index].date;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(today) ? today : current,
      firstDate: today,
      lastDate: DateTime(today.year + 3, 12, 31),
      locale: const Locale('fr', 'FR'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _drafts[index].date = picked;
      _error = null;
    });
  }

  void _addDraft() {
    final base = _drafts.isEmpty ? DateTime.now() : _drafts.last.date;
    setState(() {
      _drafts.add(_DisciplinaryDraft(
        date: base.add(const Duration(days: 1)),
        shiftId: 'urg-24h',
      ));
      _error = null;
    });
  }

  void _removeDraft(int index) {
    if (_drafts.length <= 1) return;
    setState(() {
      _drafts.removeAt(index);
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final state = context.read<AppState>();
    final me = state.currentUser;
    if (me?.role != UserRole.admin) {
      setState(() => _error = 'Action réservée à l’administrateur.');
      return;
    }

    final doctor = state.users
        .where((u) => u.id == _doctorId && u.accountStatus == AccountStatus.active)
        .firstOrNull;
    if (doctor == null) {
      setState(() => _error = 'Sélectionnez un médecin.');
      return;
    }

    final dates = <String>{};
    for (final draft in _drafts) {
      final key = _dateKey(draft.date);
      if (!dates.add(key)) {
        setState(() => _error = 'Une même date ne peut être ajoutée qu’une seule fois.');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await SupabaseBackendService.instance.client.rpc(
        'admin_assign_disciplinary_guards',
        params: {
          'p_owner_id': doctor.id,
          'p_assignments': _drafts
              .map((d) => {
                    'date': _dateKey(d.date),
                    'shift_id': d.shiftId,
                  })
              .toList(growable: false),
          'p_reason': _reasonController.text.trim(),
        },
      );

      final map = result is Map
          ? Map<String, dynamic>.from(result)
          : const <String, dynamic>{};
      final rawEntryIds = map['entry_ids'];
      final entryIds = rawEntryIds is List
          ? rawEntryIds
              .map((e) => e?.toString().trim() ?? '')
              .where((id) => id.isNotEmpty)
              .toList(growable: false)
          : const <String>[];

      if (entryIds.isNotEmpty) {
        await Future.wait<void>(
          entryIds.map((entryId) async {
            try {
              await SupabaseBackendService.instance.triggerPush(
                'disciplinary_assigned',
                entryId,
              );
            } catch (e) {
              debugPrint(
                'Push garde disciplinaire non envoyé pour $entryId: $e',
              );
            }
          }),
        );
      }

      await state.refreshBackend();
      if (!mounted) return;

      final applied = (map['applied'] as num?)?.toInt() ?? _drafts.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$applied garde${applied > 1 ? 's' : ''} disciplinaire${applied > 1 ? 's' : ''} attribuée${applied > 1 ? 's' : ''} à ${doctor.fullName}.',
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = _friendlyError(e.toString());
      });
    }
  }

  String _friendlyError(String raw) {
    final text = raw.replaceAll('PostgrestException(message: ', '');
    if (raw.contains('déjà une affectation')) {
      return 'Une date sélectionnée contient déjà une garde ou un congé. Choisissez une autre date ou supprimez d’abord l’affectation existante.';
    }
    if (raw.contains('déjà commencée ou passée')) {
      return 'Une des gardes sélectionnées est déjà commencée ou passée.';
    }
    if (raw.contains('Réservée') || raw.contains('administrateur')) {
      return 'Cette action est réservée à l’administrateur.';
    }
    return 'Attribution impossible : $text';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.currentUser;
    if (me?.role != UserRole.admin) {
      return Scaffold(
        backgroundColor: AppColors.paper,
        appBar: AppBar(title: const Text('Gardes disciplinaires')),
        body: const Center(child: Text('Accès administrateur requis.')),
      );
    }

    final allDoctors = state.users
        .where((u) => u.accountStatus == AccountStatus.active)
        .toList()
      ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    final q = _normalize(_doctorSearch);
    final doctors = q.isEmpty
        ? allDoctors
        : allDoctors.where((u) {
            final haystack = _normalize(
              '${u.fullName} ${u.service} ${u.hospital} ${u.phone}',
            );
            return haystack.contains(q);
          }).toList();

    final selectedDoctor = _doctorId == null
        ? null
        : allDoctors.where((u) => u.id == _doctorId).firstOrNull;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        surfaceTintColor: Colors.transparent,
        title: GardeFlowTitle('Gardes disciplinaires'),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.gavel_rounded,
                      color: AppColors.danger,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Attribuer une ou plusieurs gardes',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'La garde disciplinaire est immédiatement ajoutée au calendrier du médecin. Elle ne peut pas être supprimée, transférée ou échangée par le médecin.',
                          style: TextStyle(
                            color: AppColors.inkSoft,
                            fontSize: 11.5,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _doctorSearchController,
              enabled: !_submitting,
              decoration: InputDecoration(
                labelText: 'Rechercher un médecin',
                hintText: 'Nom, service, établissement ou téléphone',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _doctorSearch.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _doctorSearchController.clear();
                          setState(() => _doctorSearch = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              onChanged: (value) => setState(() => _doctorSearch = value),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: selectedDoctor != null &&
                      doctors.any((u) => u.id == selectedDoctor.id)
                  ? selectedDoctor.id
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Médecin destinataire',
                prefixIcon: Icon(Icons.person_rounded),
              ),
              items: doctors
                  .map(
                    (u) => DropdownMenuItem(
                      value: u.id,
                      child: Text(
                        '${u.fullName} · ${u.service}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (value) => setState(() {
                        _doctorId = value;
                        _error = null;
                      }),
            ),
            if (selectedDoctor != null) ...[
              const SizedBox(height: 9),
              Text(
                '${selectedDoctor.hospital} · ${selectedDoctor.gradeLabel}',
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Gardes à attribuer',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _submitting || _drafts.length >= 31 ? null : _addDraft,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Ajouter'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < _drafts.length; i++) ...[
              _DisciplinaryDraftCard(
                index: i,
                draft: _drafts[i],
                enabled: !_submitting,
                canRemove: _drafts.length > 1,
                shiftIds: _shiftIds,
                onPickDate: () => _pickDate(i),
                onShiftChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _drafts[i].shiftId = value;
                    _error = null;
                  });
                },
                onRemove: () => _removeDraft(i),
              ),
              if (i != _drafts.length - 1) const SizedBox(height: 10),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              enabled: !_submitting,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Motif administratif (facultatif)',
                hintText: 'Visible dans le journal des actions administrateur',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppColors.danger.withOpacity(0.22)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 11.5,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.gavel_rounded),
                label: Text(
                  _submitting
                      ? 'Attribution en cours…'
                      : 'Attribuer ${_drafts.length} garde${_drafts.length > 1 ? 's' : ''} disciplinaire${_drafts.length > 1 ? 's' : ''}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisciplinaryDraftCard extends StatelessWidget {
  final int index;
  final _DisciplinaryDraft draft;
  final bool enabled;
  final bool canRemove;
  final List<String> shiftIds;
  final VoidCallback onPickDate;
  final ValueChanged<String?> onShiftChanged;
  final VoidCallback onRemove;

  const _DisciplinaryDraftCard({
    required this.index,
    required this.draft,
    required this.enabled,
    required this.canRemove,
    required this.shiftIds,
    required this.onPickDate,
    required this.onShiftChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Garde ${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (canRemove)
                IconButton(
                  tooltip: 'Retirer cette garde',
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppColors.danger,
                ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 520;
              final dateButton = OutlinedButton.icon(
                onPressed: enabled ? onPickDate : null,
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(
                  DateFormat('EEE d MMM yyyy', 'fr_FR').format(draft.date),
                ),
              );
              final shiftField = DropdownButtonFormField<String>(
                value: draft.shiftId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Type de garde'),
                items: shiftIds.map((id) {
                  final shift = ShiftCatalog.byId(id);
                  final prefix = id.startsWith('urg-') ? 'Urgences' : 'Service';
                  return DropdownMenuItem(
                    value: id,
                    child: Text('$prefix · ${shift.label}'),
                  );
                }).toList(),
                onChanged: enabled ? onShiftChanged : null,
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    dateButton,
                    const SizedBox(height: 10),
                    shiftField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: dateButton),
                  const SizedBox(width: 10),
                  Expanded(child: shiftField),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DisciplinaryDraft {
  DateTime date;
  String shiftId;

  _DisciplinaryDraft({
    required this.date,
    required this.shiftId,
  });
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}