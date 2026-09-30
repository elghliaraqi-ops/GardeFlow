from pathlib import Path

path = Path('source/lib/screens/practice_screen.dart')
text = path.read_text(encoding='utf-8')
original = text

old_stats = """            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MiniMetric(label: 'Malades vus', value: '${_stats.patients}'),
                _MiniMetric(label: 'En attente', value: '${_stats.waiting}'),
                _MiniMetric(label: 'Sortants', value: '${_stats.discharged}'),
                _MiniMetric(
                    label: 'Avis spécialisés',
                    value: '${_stats.specialistOpinions}'),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              style: const TextStyle(color: Colors.white),
              decoration: _practiceInputDecoration(
                  'Rechercher un patient, motif, box…', Icons.search_rounded),
            ),
"""
new_stats = """            _HistorySummaryCard(stats: _stats),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: TextField(
                controller: _search,
                style: const TextStyle(color: Colors.white, fontSize: 13.5),
                decoration: _historySearchDecoration(),
              ),
            ),
"""
if old_stats in text:
    text = text.replace(old_stats, new_stats, 1)
elif '_HistorySummaryCard(stats: _stats)' not in text:
    raise SystemExit('History metrics/search block not found; refusing unsafe patch')

old_scope_scroll = """            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  if (widget.guard != null) _scopeChip('guard', 'Cette garde'),
                  _scopeChip('month', 'Ce mois'),
                  _scopeChip('year', 'Cette année'),
                  _scopeChip('all', 'Toutes'),
                ],
              ),
            ),
"""
new_scope_scroll = """            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 18),
              child: Row(
                children: <Widget>[
                  if (widget.guard != null) _scopeChip('guard', 'Cette garde'),
                  _scopeChip('month', 'Ce mois'),
                  _scopeChip('year', 'Cette année'),
                  _scopeChip('all', 'Toutes'),
                ],
              ),
            ),
"""
if old_scope_scroll in text:
    text = text.replace(old_scope_scroll, new_scope_scroll, 1)

old_filter_scroll = """            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'Tous'),
                  _filterChip('waiting', 'En attente'),
                  _filterChip('specialist', 'Avis spécialisé'),
                  _filterChip('discharged', 'Sortants'),
                  _filterChip('hospitalized', 'Hospitalisés'),
                  _filterChip('prescription', 'Ordonnance faite'),
                ],
              ),
            ),
            const SizedBox(height: 8),
"""
new_filter_scroll = """            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 18),
              child: Row(
                children: [
                  _filterChip('all', 'Tous'),
                  _filterChip('waiting', 'En attente'),
                  _filterChip('specialist', 'Avis'),
                  _filterChip('discharged', 'Sortants'),
                  _filterChip('hospitalized', 'Hospitalisés'),
                  _filterChip('prescription', 'Ordonnance faite'),
                ],
              ),
            ),
            const SizedBox(height: 14),
"""
if old_filter_scroll in text:
    text = text.replace(old_filter_scroll, new_filter_scroll, 1)

old_scope_chip = """  Widget _scopeChip(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 7),
        child: ChoiceChip(
          selected: _scope == key,
          label: Text(label),
          onSelected: (_) {
            setState(() => _scope = key);
            _load();
          },
          selectedColor: PracticeColors.accent,
          backgroundColor: PracticeColors.surface,
          labelStyle: TextStyle(
              color: _scope == key ? PracticeColors.background : Colors.white,
              fontWeight: FontWeight.w800),
          side: BorderSide.none,
        ),
      );

  Widget _filterChip(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 7),
        child: FilterChip(
          selected: _filter == key,
          label: Text(label),
          onSelected: (_) {
            setState(() => _filter = key);
            _load();
          },
          selectedColor: PracticeColors.elevated,
          backgroundColor: PracticeColors.surface,
          checkmarkColor: PracticeColors.accent,
          labelStyle:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          side: const BorderSide(color: PracticeColors.line),
        ),
      );
"""
new_scope_chip = """  Widget _scopeChip(String key, String label) {
    final selected = _scope == key;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        label: Text(label),
        onSelected: (_) {
          setState(() => _scope = key);
          _load();
        },
        selectedColor: PracticeColors.elevated,
        backgroundColor: PracticeColors.surface,
        labelStyle: TextStyle(
          color: selected ? PracticeColors.accent : PracticeColors.text,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        side: BorderSide(
          color: selected
              ? PracticeColors.accent.withOpacity(.32)
              : Colors.transparent,
        ),
      ),
    );
  }

  Widget _filterChip(String key, String label) {
    final selected = _filter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: FilterChip(
        selected: selected,
        visualDensity: VisualDensity.compact,
        label: Text(label),
        onSelected: (_) {
          setState(() => _filter = key);
          _load();
        },
        selectedColor: PracticeColors.elevated,
        backgroundColor: PracticeColors.surface,
        checkmarkColor: PracticeColors.accent,
        labelStyle: TextStyle(
          color: selected ? PracticeColors.accent : PracticeColors.text,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
        side: BorderSide(
          color: selected
              ? PracticeColors.accent.withOpacity(.28)
              : PracticeColors.line.withOpacity(.38),
        ),
      ),
    );
  }
"""
if old_scope_chip in text:
    text = text.replace(old_scope_chip, new_scope_chip, 1)
elif 'Widget _scopeChip(String key, String label) {' not in text:
    raise SystemExit('Scope/filter chip block not found; refusing unsafe patch')

old_patient_tile = """class _PatientTile extends StatelessWidget {
  final PracticeCase value;
  final VoidCallback onTap;
  const _PatientTile({required this.value, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: PracticeColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: PracticeColors.line)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Text(value.patientLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900)),
                      if (value.pendingSync) ...[
                        const SizedBox(width: 7),
                        const Icon(Icons.cloud_upload_outlined,
                            color: PracticeColors.waiting, size: 15),
                      ],
                    ]),
                    const SizedBox(height: 4),
                    Text(value.displayReason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: PracticeColors.textSecondary,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 5),
                    Text(
                        [
                          if (value.arrivalTime != null)
                            DateFormat('HH:mm').format(value.arrivalTime!),
                          if ((value.location ?? '').trim().isNotEmpty)
                            value.location!.trim(),
                        ].join(' · '),
                        style: const TextStyle(
                            color: PracticeColors.textSecondary,
                            fontSize: 10.5)),
                    const SizedBox(height: 8),
                    Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: _caseBadges(value)),
                  ])),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded,
                  color: PracticeColors.textSecondary),
            ]),
          ),
        ),
      );
}
"""
new_patient_tile = """class _PatientTile extends StatelessWidget {
  final PracticeCase value;
  final VoidCallback onTap;
  const _PatientTile({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final timeLabel = value.arrivalTime == null
        ? ''
        : DateFormat('HH:mm').format(value.arrivalTime!);
    final locationLabel = _practiceCaseLocationLabel(value.location);
    final badges = _caseBadges(value);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
          decoration: BoxDecoration(
            color: PracticeColors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            value.patientLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (value.pendingSync) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.cloud_upload_outlined,
                            color: PracticeColors.waiting,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (timeLabel.isNotEmpty)
                    Text(
                      timeLabel,
                      style: const TextStyle(
                        color: PracticeColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: PracticeColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value.displayReason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PracticeColors.textSecondary,
                  fontSize: 13.2,
                  height: 1.32,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (locationLabel.isNotEmpty) ...[
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.place_outlined,
                      color: PracticeColors.textSecondary,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      locationLabel,
                      style: const TextStyle(
                        color: PracticeColors.textSecondary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              if (badges.isNotEmpty) ...[
                const SizedBox(height: 9),
                Wrap(spacing: 5, runSpacing: 5, children: badges),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
"""
if old_patient_tile in text:
    text = text.replace(old_patient_tile, new_patient_tile, 1)
elif 'final timeLabel = value.arrivalTime == null' not in text:
    raise SystemExit('Patient tile block not found; refusing unsafe patch')

history_widgets = """
class _HistorySummaryCard extends StatelessWidget {
  final PracticeStats stats;
  const _HistorySummaryCard({required this.stats});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: PracticeColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Expanded(
              child: _HistoryMetric(value: '${stats.patients}', label: 'Vus'),
            ),
            const _HistoryMetricDivider(),
            Expanded(
              child: _HistoryMetric(value: '${stats.waiting}', label: 'Attente'),
            ),
            const _HistoryMetricDivider(),
            Expanded(
              child: _HistoryMetric(value: '${stats.discharged}', label: 'Sortants'),
            ),
            const _HistoryMetricDivider(),
            Expanded(
              child: _HistoryMetric(
                value: '${stats.specialistOpinions}',
                label: 'Avis',
              ),
            ),
          ],
        ),
      );
}

class _HistoryMetric extends StatelessWidget {
  final String value;
  final String label;
  const _HistoryMetric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: PracticeColors.textSecondary,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}

class _HistoryMetricDivider extends StatelessWidget {
  const _HistoryMetricDivider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 34,
        color: PracticeColors.line.withOpacity(.55),
      );
}
"""
if 'class _HistorySummaryCard extends StatelessWidget' not in text:
    marker = 'class _PatientTile extends StatelessWidget {'
    if marker not in text:
        raise SystemExit('Patient tile marker not found for history widget insertion')
    text = text.replace(marker, history_widgets + '\n' + marker, 1)

helpers = """
InputDecoration _historySearchDecoration() => InputDecoration(
      hintText: 'Rechercher un patient, motif, box…',
      hintStyle: const TextStyle(
        color: PracticeColors.textSecondary,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: const Icon(
        Icons.search_rounded,
        color: PracticeColors.textSecondary,
        size: 20,
      ),
      filled: true,
      fillColor: PracticeColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: PracticeColors.line.withOpacity(.52),
          width: .8,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: PracticeColors.accent, width: 1.2),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );

String _practiceCaseLocationLabel(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return '';
  final lower = value.toLowerCase();
  if (lower.startsWith('box ') || lower.startsWith('zone ')) return value;
  if (RegExp(r'^\\d+$').hasMatch(value)) return 'Box $value';
  return value;
}

"""
if '_historySearchDecoration() =>' not in text:
    marker = 'InputDecoration _practiceInputDecoration(String hint, [IconData? icon]) =>'
    if marker not in text:
        raise SystemExit('Input decoration marker not found')
    text = text.replace(marker, helpers + marker, 1)

if text == original:
    print('Practice history polish already applied; no changes.')
else:
    path.write_text(text, encoding='utf-8')
    print('Practice history polish applied.')
