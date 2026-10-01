import 'package:flutter/material.dart';

import '../models/qcm_models.dart';
import '../services/clinical_case_service.dart';
import '../theme/screen_decor.dart';

class PracticeQcmScreen extends StatefulWidget {
  const PracticeQcmScreen({super.key});

  @override
  State<PracticeQcmScreen> createState() => _PracticeQcmScreenState();
}

class _PracticeQcmScreenState extends State<PracticeQcmScreen> {
  static const _bg = Color(0xFF071526);
  static const _surface = Color(0xFF10243A);
  static const _elevated = Color(0xFF17314E);
  static const _accent = Color(0xFF5BE7B0);
  static const _purple = Color(0xFF8B6CFF);
  static const _blue = Color(0xFF3295FF);
  static const _gold = Color(0xFFFFD166);
  static const _pink = Color(0xFFFF6FAE);
  static const _secondary = Color(0xFFB9CBE0);
  static const _line = Color(0xFF244B68);

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
    return DecorScaffold(scene: ScreenDecorScene.practice, 
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'QCM · Practice',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        ),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        color: _accent,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 16, 17),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6B50E8), Color(0xFF226FC6), Color(0xFF0B8F76)],
                  stops: [0, .55, 1],
                ),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white24),
                boxShadow: [
                  BoxShadow(
                    color: _purple.withOpacity(.25),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -14,
                    top: -24,
                    child: Icon(
                      Icons.quiz_rounded,
                      size: 108,
                      color: Colors.white.withOpacity(.09),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(.13),
                          borderRadius: BorderRadius.circular(17),
                          border: Border.all(color: _gold.withOpacity(.34)),
                        ),
                        child: const Icon(Icons.sports_esports_rounded, color: _gold, size: 27),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'QCM ARENA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .45,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Scores, précision et classement des défis Practice',
                              style: TextStyle(
                                color: Color(0xFFE9F2FF),
                                fontSize: 11.2,
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.bolt_rounded, color: _gold, size: 27),
                    ],
                  ),
                ],
              ),
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
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [_purple.withOpacity(.24), _surface, _blue.withOpacity(.12)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _purple.withOpacity(.38)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: _gold),
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
            const Row(children: [Icon(Icons.leaderboard_rounded, color: _gold, size: 20), SizedBox(width: 8), Text('LEADERBOARD QCM', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: .25))]),
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
    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _PracticeQcmScreenState._purple.withOpacity(.26),
          _PracticeQcmScreenState._surface,
          _PracticeQcmScreenState._blue.withOpacity(.15),
        ],
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _PracticeQcmScreenState._purple.withOpacity(.34)),
      boxShadow: [
        BoxShadow(
          color: _PracticeQcmScreenState._purple.withOpacity(.10),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: _PracticeQcmScreenState._secondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? _PracticeQcmScreenState._purple.withOpacity(.30)
        : _PracticeQcmScreenState._surface,
    borderRadius: BorderRadius.circular(15),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected
                ? _PracticeQcmScreenState._purple
                : _PracticeQcmScreenState._line,
            width: selected ? 1.3 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _PracticeQcmScreenState._purple.withOpacity(.16),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected
                ? Colors.white
                : _PracticeQcmScreenState._secondary,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    ),
  );
}

class _RankRow extends StatelessWidget {
  final QcmLeaderboardEntry entry;
  const _RankRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final medal = entry.rank == 1
        ? '🥇'
        : entry.rank == 2
            ? '🥈'
            : entry.rank == 3
                ? '🥉'
                : null;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            entry.rank <= 3
                ? _PracticeQcmScreenState._gold.withOpacity(.13)
                : _PracticeQcmScreenState._purple.withOpacity(.10),
            _PracticeQcmScreenState._surface,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: entry.rank <= 3
              ? _PracticeQcmScreenState._gold.withOpacity(.42)
              : _PracticeQcmScreenState._purple.withOpacity(.22),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _PracticeQcmScreenState._elevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              medal ?? '${entry.rank}',
              style: TextStyle(
                color: Colors.white,
                fontSize: medal == null ? 13 : 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.correct} correctes / ${entry.answered} · ${entry.accuracy.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: _PracticeQcmScreenState._secondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (entry.promotionNumber != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: _PracticeQcmScreenState._accent.withOpacity(.10),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'P${entry.promotionNumber}',
                style: const TextStyle(
                  color: _PracticeQcmScreenState._accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
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
