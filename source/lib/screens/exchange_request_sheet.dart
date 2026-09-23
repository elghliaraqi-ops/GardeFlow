import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/intern_promotions.dart';
import '../models/planning_entry.dart';
import '../models/shift_type.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'announcements_screen.dart';

enum _Mode { transfer, exchange }

class ExchangeRequestSheet extends StatefulWidget {
  final String dateStr;
  final PlanningEntry entry;
  const ExchangeRequestSheet({super.key, required this.dateStr, required this.entry});
  @override
  State<ExchangeRequestSheet> createState() => _ExchangeRequestSheetState();
}

class _ExchangeRequestSheetState extends State<ExchangeRequestSheet> {
  _Mode _mode = _Mode.transfer;
  String? _doctorId;
  String? _targetEntryId;
  String _doctorSearch = '';
  final TextEditingController _doctorSearchController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _doctorSearchController.dispose();
    super.dispose();
  }

  String _normalizeDoctorSearch(String value) {
    var s = value.toLowerCase();
    const replacements = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a',
      'ç': 'c',
      'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ñ': 'n',
      'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'œ': 'oe',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
      'ý': 'y', 'ÿ': 'y', 'æ': 'ae',
      '’': ' ', "'": ' ', '-': ' ',
    };
    for (final entry in replacements.entries) {
      s = s.replaceAll(entry.key, entry.value);
    }
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.currentUser;
    final shift = ShiftCatalog.byId(widget.entry.shiftId);
    final sourceIsService = widget.entry.shiftId.startsWith('service-');
    final sourceIsUrgence = widget.entry.shiftId.startsWith('urg-');
    final exchangeMode = _mode == _Mode.exchange;
    final rawTargets = state.exchangeTargets(
      sameServiceOnly: exchangeMode && sourceIsService,
    );
    final targets = rawTargets.where((contact) {
      final targetUser = state.users
          .where((u) => u.id == contact.id || u.phone == contact.phone)
          .firstOrNull;
      if (state.promotionExchangeBlocked(me, targetUser)) {
        return false;
      }
      return true;
    }).toList();
    final search = _normalizeDoctorSearch(_doctorSearch);
    final filteredTargets = search.isEmpty
        ? targets
        : targets.where((c) {
            final haystack = _normalizeDoctorSearch('${c.name} ${c.service}');
            return haystack.contains(search);
          }).toList();
    final dateLabel = DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.parse(widget.dateStr));
    final selectedDoctor = _doctorId == null ? null : targets.where((c) => c.id == _doctorId).firstOrNull;
    final selectedDoctorUser = selectedDoctor == null
        ? null
        : state.users
            .where((u) => u.id == selectedDoctor.id || u.phone == selectedDoctor.phone)
            .firstOrNull;
    final crossYearWithSelected =
        state.promotionExchangeBlocked(me, selectedDoctorUser);
    final allTargetEntries = selectedDoctor == null
        ? <PlanningEntry>[]
        : state.exchangeableEntriesFor(selectedDoctor.id, excludingDate: widget.dateStr);
    final targetEntries = selectedDoctor == null
        ? <PlanningEntry>[]
        : allTargetEntries.where((e) {
            if (!exchangeMode) return true;
            final targetIsService = e.shiftId.startsWith('service-');
            if (targetIsService && selectedDoctor.service != state.currentUser?.service) return false;
            if (crossYearWithSelected) return false;
            return true;
          }).toList();
    final selectedTargetEntryId =
        _targetEntryId != null && targetEntries.any((e) => e.id == _targetEntryId) ? _targetEntryId : null;
    final promotionLabel = InternPromotions.labelFor(
      me,
      firstYearPromotion: state.currentFirstYearPromotion,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(left: AppSpace.xl, right: AppSpace.xl, top: AppSpace.sm, bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transfert / échange de garde', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
                  decoration: BoxDecoration(color: shift.color, borderRadius: AppRadius.smR),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(shift.icon, size: 15, color: shift.textColor),
                    const SizedBox(width: AppSpace.xs),
                    Text('$dateLabel · ${shift.label}', style: TextStyle(fontSize: 12.5, color: shift.textColor, fontWeight: FontWeight.w700)),
                  ]),
                ),
                if (promotionLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: AppRadius.pillR,
                      border: Border.all(color: AppColors.brandBright, width: 1.2),
                    ),
                    child: Text(
                      promotionLabel,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AnnouncementsScreen(
                          initialEntryId: widget.entry.id,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.forum_rounded, size: 18),
                    label: const Text('Fil public'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AnnouncementsScreen(
                          initialEntryId: widget.entry.id,
                          autoOpenComposer: true,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.campaign_rounded, size: 18),
                    label: const Text('Publier'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.transfer, icon: Icon(Icons.arrow_forward_rounded, size: 16), label: Text('Transfert')),
                ButtonSegment(value: _Mode.exchange, icon: Icon(Icons.swap_horiz_rounded, size: 16), label: Text('Échange')),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() {
                _mode = v.first;
                _targetEntryId = null;
                _error = null;
              }),
            ),
            const SizedBox(height: AppSpace.sm),
            _RuleNotice(
              text: _mode == _Mode.transfer
                  ? sourceIsService
                      ? 'Transfert Service : même hôpital. La Promo ${state.currentFirstYearPromotion} (1re année) ne peut transférer qu’avec la même promotion. Les promotions antérieures peuvent transférer entre elles. Le destinataire accepte, puis l’admin valide.'
                      : 'Transfert Urgences : même hôpital. La Promo ${state.currentFirstYearPromotion} (1re année) ne peut transférer qu’avec la même promotion. Les promotions antérieures peuvent transférer entre elles. Le destinataire accepte, puis l’admin valide.'
                  : sourceIsService
                      ? 'Échange Service : uniquement avec un médecin de votre service. La Promo ${state.currentFirstYearPromotion} (1re année) ne peut échanger qu’avec la même promotion. Les promotions antérieures peuvent échanger entre elles. Entre deux gardes de Service, pas de validation admin.'
                      : 'Échange Urgences : même hôpital. La Promo ${state.currentFirstYearPromotion} (1re année) ne peut échanger qu’avec la même promotion. Les promotions antérieures peuvent échanger entre elles. Validation admin obligatoire.',
              icon: _mode == _Mode.transfer
                  ? Icons.arrow_forward_rounded
                  : sourceIsService
                      ? Icons.groups_2_rounded
                      : Icons.local_hospital_rounded,
            ),
            const SizedBox(height: AppSpace.lg),
            if (targets.isEmpty)
              Text(
                rawTargets.isNotEmpty
                    ? 'Aucun médecin compatible avec votre groupe d’ancienneté pour cette garde.'
                    : 'Aucun autre médecin disponible dans votre établissement.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else ...[
              TextField(
                controller: _doctorSearchController,
                onChanged: (value) => setState(() {
                  _doctorSearch = value;
                  _doctorId = null;
                  _targetEntryId = null;
                  _error = null;
                }),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Rechercher un médecin',
                  hintText: 'Nom ou service',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _doctorSearch.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer la recherche',
                          onPressed: () => setState(() {
                            _doctorSearchController.clear();
                            _doctorSearch = '';
                            _doctorId = null;
                            _targetEntryId = null;
                            _error = null;
                          }),
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              if (filteredTargets.isEmpty)
                Text(
                  'Aucun médecin ne correspond à votre recherche.',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                DropdownButtonFormField<String>(
                  value: selectedDoctor != null &&
                          filteredTargets.any((c) => c.id == selectedDoctor.id)
                      ? selectedDoctor.id
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Médecin destinataire',
                    helperText: search.isEmpty
                        ? '${targets.length} médecin${targets.length > 1 ? 's' : ''} disponible${targets.length > 1 ? 's' : ''}'
                        : '${filteredTargets.length} résultat${filteredTargets.length > 1 ? 's' : ''}',
                  ),
                  items: filteredTargets
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            '${c.name} · ${c.service}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    _doctorId = v;
                    _targetEntryId = null;
                    _error = null;
                  }),
                ),
              if (_mode == _Mode.exchange && selectedDoctor != null) ...[
                const SizedBox(height: AppSpace.md),
                if (targetEntries.isEmpty)
                  Text('${selectedDoctor.name} n’a aucune garde disponible à échanger.', style: Theme.of(context).textTheme.bodySmall)
                else
                  DropdownButtonFormField<String>(
                    value: selectedTargetEntryId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Garde reçue en échange'),
                    items: targetEntries.map((e) {
                      final sh = ShiftCatalog.byId(e.shiftId);
                      final d = DateFormat('EEE d MMM yyyy', 'fr_FR').format(DateTime.parse(e.dateStr));
                      return DropdownMenuItem(value: e.id, child: Text('$d · ${sh.label}', overflow: TextOverflow.ellipsis));
                    }).toList(),
                    onChanged: (v) => setState(() {
                      _targetEntryId = v;
                      _error = null;
                    }),
                  ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpace.sm),
              Row(children: [
                const Icon(Icons.error_rounded, size: 15, color: AppColors.danger),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600))),
              ]),
            ],
            const SizedBox(height: AppSpace.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: targets.isEmpty
                    ? null
                    : () async {
                        final doctor = _doctorId == null ? null : targets.where((c) => c.id == _doctorId).firstOrNull;
                        if (doctor == null) {
                          setState(() => _error = 'Sélectionnez un médecin destinataire.');
                          return;
                        }
                        String? err;
                        if (_mode == _Mode.transfer) {
                          err = await state.createTransferRequest(widget.dateStr, widget.entry, doctor);
                        } else {
                          final doctorUser = state.users
                              .where((u) => u.id == doctor.id || u.phone == doctor.phone)
                              .firstOrNull;
                          final crossYear = state.promotionExchangeBlocked(me, doctorUser);
                          final available = state.exchangeableEntriesFor(doctor.id, excludingDate: widget.dateStr).where((e) {
                            final targetIsService = e.shiftId.startsWith('service-');
                            if (targetIsService && doctor.service != state.currentUser?.service) return false;
                            if (crossYear) return false;
                            return true;
                          }).toList();
                          if (available.isEmpty) {
                            setState(() => _error = '${doctor.name} n’a aucune garde compatible avec les règles d’échange.');
                            return;
                          }
                          final targetEntry = _targetEntryId == null ? null : available.where((e) => e.id == _targetEntryId).firstOrNull;
                          if (targetEntry == null) {
                            setState(() => _error = 'Sélectionnez la garde à recevoir en échange.');
                            return;
                          }
                          err = await state.createSwapRequest(widget.dateStr, widget.entry, doctor, targetEntry);
                        }
                        if (!context.mounted) return;
                        if (err != null) {
                          setState(() => _error = err);
                          return;
                        }
                        Navigator.of(context).pop();
                      },
                child: Text(_mode == _Mode.transfer ? 'Envoyer la demande de transfert' : 'Envoyer la demande d’échange'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _RuleNotice extends StatelessWidget {
  final String text;
  final IconData icon;
  const _RuleNotice({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.brand),
          SizedBox(width: AppSpace.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45))),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> { T? get firstOrNull => isEmpty ? null : first; }
