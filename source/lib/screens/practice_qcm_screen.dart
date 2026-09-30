import 'package:flutter/material.dart';

import '../models/qcm_models.dart';
import '../services/clinical_case_service.dart';

class PracticeQcmScreen extends StatefulWidget {
  const PracticeQcmScreen({super.key});

  @override
  State<PracticeQcmScreen> createState() => _PracticeQcmScreenState();
}

class _PracticeQcmScreenState extends State<PracticeQcmScreen> {
  static const _bg = Color(0xFF062E20);
  static const _surface = Color(0xFF0B4933);
  static const _elevated = Color(0xFF116044);
  static const _accent = Color(0xFF20D67A);
  static const _secondary = Color(0xFFB8D6C9);
  static const _line = Color(0xFF287154);

  final _service = ClinicalCaseService.instance;
  String _period = 'month';
  bool _promotionOnly = true;
  bool _loading = true;
  QcmRanks _ranks = const QcmRanks();
  List<QcmLeaderboardEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ranks = await _service.qcmRanks(period: _period);
      final entries = await _service.qcmLeaderboard(
        period: _period,
        promotion: _promotionOnly ? ranks.promotionNumber : null,
      );
      if (!mounted) return;
      setState(() {
        _ranks = ranks;
        _entries = entries;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _changePeriod(String value) async {
    if (value == _period) return;
    setState(() => _period = value);
    await _load();
  }

  Future<void> _changeScope(bool promotionOnly) async {
    if (promotionOnly == _promotionOnly) return;
    setState(() => _promotionOnly = promotionOnly);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final rank = _promotionOnly ? _ranks.promotionRank : _ranks.globalRank;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('QCM · Practice', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: RefreshIndicator(
        color: _accent,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: [
            const Text(
              'Vos statistiques QCM',
              style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'Réponses aux cas cliniques publiés dans le fil d’accueil.',
              style: TextStyle(color: _secondary, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _Metric(value: '${_ranks.answered}', label: 'Répondus')),
                const SizedBox(width: 8),
                Expanded(child: _Metric(value: '${_ranks.correct}', label: 'Corrects')),
                const SizedBox(width: 8),
                Expanded(child: _Metric(value: '${_ranks.accuracy.toStringAsFixed(0)}%', label: 'Réussite')),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: _accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Votre classement', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(
                          !_ranks.leaderboardOptIn
                              ? 'Participation au classement désactivée dans Practice'
                              : rank == null
                                  ? 'Disponible après votre première réponse QCM'
                                  : '${rank}e ${_promotionOnly ? 'de votre promotion' : 'toutes promotions'}',
                          style: const TextStyle(color: _secondary, fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _Segment(label: 'Ce mois', selected: _period == 'month', onTap: () => _changePeriod('month'))),
                const SizedBox(width: 8),
                Expanded(child: _Segment(label: 'Cette année', selected: _period == 'year', onTap: () => _changePeriod('year'))),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _Segment(label: 'Ma promotion', selected: _promotionOnly, onTap: () => _changeScope(true))),
                const SizedBox(width: 8),
                Expanded(child: _Segment(label: 'Toutes promotions', selected: !_promotionOnly, onTap: () => _changeScope(false))),
              ],
            ),
            const SizedBox(height: 18),
            const Text('Classement QCM', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: _accent)),
              )
            else if (!_ranks.leaderboardOptIn)
              const _Empty(message: 'Activez votre participation au classement dans Practice pour apparaître dans les classements.')
            else if (_entries.isEmpty)
              const _Empty(message: 'Aucune réponse QCM classée pour cette période.')
            else
              for (final entry in _entries) ...[
                _RankRow(entry: entry),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 14),
            const Text(
              'Le classement QCM reflète uniquement l’activité et les réponses aux exercices pédagogiques. Il ne mesure ni la compétence clinique ni la qualité des soins.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _secondary, fontSize: 10.5, height: 1.4, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String value;
  final String label;
  const _Metric({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: _PracticeQcmScreenState._surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _PracticeQcmScreenState._line),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(color: _PracticeQcmScreenState._secondary, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Segment({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? _PracticeQcmScreenState._elevated : _PracticeQcmScreenState._surface,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: selected ? _PracticeQcmScreenState._accent : _PracticeQcmScreenState._line),
            ),
            alignment: Alignment.center,
            child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: selected ? Colors.white : _PracticeQcmScreenState._secondary, fontSize: 11, fontWeight: FontWeight.w900)),
          ),
        ),
      );
}

class _RankRow extends StatelessWidget {
  final QcmLeaderboardEntry entry;
  const _RankRow({required this.entry});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _PracticeQcmScreenState._surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _PracticeQcmScreenState._line),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _PracticeQcmScreenState._elevated,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text('${entry.rank}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w900)),
                  Text('${entry.correct} correctes / ${entry.answered} · ${entry.accuracy.toStringAsFixed(0)}%', style: const TextStyle(color: _PracticeQcmScreenState._secondary, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (entry.promotionNumber != null)
              Text('P${entry.promotionNumber}', style: const TextStyle(color: _PracticeQcmScreenState._accent, fontSize: 10.5, fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

class _Empty extends StatelessWidget {
  final String message;
  const _Empty({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _PracticeQcmScreenState._surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _PracticeQcmScreenState._line),
        ),
        child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _PracticeQcmScreenState._secondary, fontSize: 11.5, height: 1.4, fontWeight: FontWeight.w700)),
      );
}
