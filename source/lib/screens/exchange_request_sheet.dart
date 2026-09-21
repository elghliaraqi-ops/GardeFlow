import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/planning_entry.dart';
import '../models/shift_type.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../ui/components.dart';
import '../ui/planning_access.dart';
import '../data/hospitals.dart';

enum _Mode { transfer, exchange }

class ExchangeRequestSheet extends StatefulWidget {
  final String dateStr;
  final PlanningEntry entry;
  final bool initialExchange;
  const ExchangeRequestSheet({super.key, required this.dateStr, required this.entry, this.initialExchange = false});
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
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialExchange ? _Mode.exchange : _Mode.transfer;
  }

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
    final shift = ShiftCatalog.byId(widget.entry.shiftId);
    final sourceIsService = widget.entry.shiftId.startsWith('service-');
    final exchangeMode = _mode == _Mode.exchange;
    final targets = state.exchangeTargets(sameServiceOnly: exchangeMode && sourceIsService);
    final search = _normalizeDoctorSearch(_doctorSearch);
    final filteredTargets = search.isEmpty
        ? targets
        : targets.where((c) {
            final haystack = _normalizeDoctorSearch('${c.name} ${c.service}');
            return haystack.contains(search);
          }).toList();
    final dateLabel = DateFormat('EEEE d MMMM', 'fr_FR').format(DateTime.parse(widget.dateStr));
    final selectedDoctor = _doctorId == null ? null : targets.where((c) => c.id == _doctorId).firstOrNull;
    final allTargetEntries = selectedDoctor == null
        ? <PlanningEntry>[]
        : state.exchangeableEntriesFor(selectedDoctor.id, excludingDate: widget.dateStr);
    final targetEntries = selectedDoctor == null
        ? <PlanningEntry>[]
        : allTargetEntries.where((e) {
            if (!exchangeMode) return true;
            final targetIsService = e.shiftId.startsWith('service-');
            if (targetIsService && selectedDoctor.service != state.currentUser?.service) return false;
            return true;
          }).toList();
    final selectedTargetEntryId =
        _targetEntryId != null && targetEntries.any((e) => e.id == _targetEntryId) ? _targetEntryId : null;
    final selectedTarget = targetEntries.where((e) => e.id == selectedTargetEntryId).firstOrNull;
    final targetReason = selectedDoctor == null ? null : exchangeMode
        ? selectedTarget == null ? null : swapTargetDisabledReason(state, widget.entry, selectedDoctor, selectedTarget)
        : transferTargetDisabledReason(state, widget.entry, selectedDoctor);

    final sourceReason = exchangeDisabledReason(state, widget.entry);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(left: AppSpace.xl, right: AppSpace.xl, top: AppSpace.sm, bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('À qui souhaitez-vous proposer cette garde ?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpace.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
              decoration: BoxDecoration(color: shift.color, borderRadius: AppRadius.smR),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(shift.icon, size: 15, color: shift.textColor),
                const SizedBox(width: AppSpace.xs),
                Flexible(child: Text('$dateLabel · ${shift.label}', style: TextStyle(fontSize: 12.5, color: shift.textColor, fontWeight: FontWeight.w700))),
              ]),
            ),
            const SizedBox(height: AppSpace.lg),
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.transfer, icon: Icon(Icons.arrow_forward_rounded, size: 16), label: Text('Transfert')),
                ButtonSegment(value: _Mode.exchange, icon: Icon(Icons.swap_horiz_rounded, size: 16), label: Text('Échange')),
              ],
              selected: {_mode},
              onSelectionChanged: _sending ? null : (v) => setState(() {
                _mode = v.first;
                _doctorId = null;
                _targetEntryId = null;
                _error = null;
              }),
            ),
            const SizedBox(height: AppSpace.sm),
            _RuleNotice(
              text: _mode == _Mode.transfer
                  ? 'Transfert : vous donnez cette garde à un collègue du même hôpital. Il doit accepter, puis l’admin valide.'
                  : sourceIsService
                      ? 'Échange Service : uniquement avec un médecin de votre service. Si les deux gardes sont des gardes de Service, l’échange est appliqué dès l’acceptation du collègue, sans validation admin. Si une garde Urgences intervient, l’admin doit valider.'
                      : 'Échange Urgences : possible avec tout médecin du même hôpital et validation admin obligatoire. Une garde de Service ne peut être choisie que si le médecin appartient au même service que vous.',
              icon: _mode == _Mode.transfer
                  ? Icons.arrow_forward_rounded
                  : sourceIsService
                      ? Icons.groups_2_rounded
                      : Icons.local_hospital_rounded,
            ),
            const SizedBox(height: AppSpace.lg),
            if (targets.isEmpty)
              Text('Aucun autre médecin inscrit dans votre établissement.', style: Theme.of(context).textTheme.bodyMedium)
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filteredTargets.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                      final doctor = filteredTargets[index];
                      final reason = exchangeMode ? null : transferTargetDisabledReason(state, widget.entry, doctor);
                      final unavailable = reason != null;
                      return DoctorTile(
                        name: doctor.name,
                        subtitle: '${doctor.service ?? ''} · ${hospitalDisplayName(doctor.hospital)}${reason == null ? '' : '\n$reason'}',
                        selected: selectedDoctor?.id == doctor.id,
                        trailing: unavailable ? const Icon(Icons.lock_outline_rounded) : null,
                        onTap: unavailable || _sending ? null : () {
                          FocusScope.of(context).unfocus();
                          setState(() { _doctorId = doctor.id; _targetEntryId = null; _error = null; });
                        },
                      );
                    },
                  ),
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
                      final reason = swapTargetDisabledReason(state, widget.entry, selectedDoctor, e);
                      return DropdownMenuItem(value: e.id, enabled: reason == null,
                        child: Text('$d · ${sh.label}${reason == null ? '' : ' · indisponible'}', overflow: TextOverflow.ellipsis));
                    }).toList(),
                    onChanged: (v) => setState(() {
                      _targetEntryId = v;
                      _error = null;
                    }),
                  ),
              ],
            ],
            if (sourceReason != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(sourceReason)),
            if (targetReason != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(targetReason)),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.sm),
              Row(children: [
                Icon(Icons.error_rounded, size: 15, color: AppColors.danger),
                const SizedBox(width: 6),
                Expanded(child: Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600))),
              ]),
            ],
            const SizedBox(height: AppSpace.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: targets.isEmpty || selectedDoctor == null || sourceReason != null || targetReason != null || _sending || (exchangeMode && selectedTargetEntryId == null)
                    ? null
                    : () async {
                        final doctor = _doctorId == null ? null : targets.where((c) => c.id == _doctorId).firstOrNull;
                        if (doctor == null) {
                          setState(() => _error = 'Sélectionnez un médecin destinataire.');
                          return;
                        }
                        setState(() => _sending = true);
                        String? err;
                        if (_mode == _Mode.transfer) {
                          err = await state.createTransferRequest(widget.dateStr, widget.entry, doctor);
                        } else {
                          final available = state.exchangeableEntriesFor(doctor.id, excludingDate: widget.dateStr).where((e) {
                            final targetIsService = e.shiftId.startsWith('service-');
                            if (targetIsService && doctor.service != state.currentUser?.service) return false;
                            return true;
                          }).toList();
                          if (available.isEmpty) {
                            setState(() { _sending = false; _error = '${doctor.name} n’a aucune garde compatible avec les règles d’échange.'; });
                            return;
                          }
                          final targetEntry = _targetEntryId == null ? null : available.where((e) => e.id == _targetEntryId).firstOrNull;
                          if (targetEntry == null) {
                            setState(() { _sending = false; _error = 'Sélectionnez la garde à recevoir en échange.'; });
                            return;
                          }
                          err = await state.createSwapRequest(widget.dateStr, widget.entry, doctor, targetEntry);
                        }
                        if (!context.mounted) return;
                        if (err != null) {
                          setState(() { _sending = false; _error = err; });
                          return;
                        }
                        Navigator.of(context).pop();
                      },
                child: Text(_sending ? 'Envoi…' : _mode == _Mode.transfer ? 'Envoyer la demande de transfert' : 'Envoyer la demande d’échange', textAlign: TextAlign.center),
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
