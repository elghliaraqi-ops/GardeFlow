import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/practice_daily_models.dart';
import '../services/practice_daily_service.dart';
import 'practice_daily_screen.dart';
import 'practice_daily_visual_theme.dart';

/// Personal archive. Replays can be done repeatedly; the official score is immutable.
class PracticeDailyHistoryScreen extends StatefulWidget {
  const PracticeDailyHistoryScreen({super.key});

  @override
  State<PracticeDailyHistoryScreen> createState() =>
      _PracticeDailyHistoryScreenState();
}

class _PracticeDailyHistoryScreenState
    extends State<PracticeDailyHistoryScreen> {
  static const Color _background = Color(0xFF071526);
  static const Color _surface = Color(0xFF10243A);
  static const Color _mint = Color(0xFF5BE7B0);
  static const Color _gold = Color(0xFFFFD166);

  List<PracticeDailyHistoryEntry> _entries = [];
  bool _busy = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_busy) return;
    if (reset) {
      setState(() {
        _entries = [];
        _hasMore = true;
      });
    }
    if (!_hasMore) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final batch = await PracticeDailyService.instance.history(
        limit: 30,
        offset: _entries.length,
      );
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, ...batch];
        _hasMore = batch.length == 30;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Impossible de charger l’historique : $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replay(PracticeDailyHistoryEntry item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeDailyScreen(replayDay: item.day),
      ),
    );
    if (mounted) await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _entries.length;
    final replayCount = _entries.fold<int>(
      0,
      (count, item) => count + item.replayCount,
    );
    return Theme(
      data: PracticeDailyVisualTheme.from(context),
      child: Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Historique Practice',
          style: TextStyle(color: PracticeDailyVisualTheme.text,
            fontSize: 18, fontWeight: FontWeight.w800)),
        foregroundColor: Colors.white,
        backgroundColor: _background,
        actions: [
          IconButton(
            tooltip: 'Quitter l’historique',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.exit_to_app_rounded),
          ),
          IconButton(
            tooltip: 'Actualiser l’historique',
            onPressed: _busy ? null : () => _load(reset: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: PracticeDailyVisualTheme.pageGradient,
        ),
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: PracticeDailyVisualTheme.cardGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Mes défis terminés',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Retrouvez vos cas cliniques et vos QCM de cours. '
                  'Rejouer crée un nouveau score d’entraînement sans '
                  'modifier la note officielle du calendrier.',
                  style: TextStyle(color: Color(0xFFB9CBE0), height: 1.45),
                ),
                const SizedBox(height: 14),
                Text(
                  '$completedCount défis affichés · $replayCount relectures',
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: Color(0xFFF28C8C))),
          ],
          if (_busy) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(color: _mint),
          ],
          if (!_busy && _entries.isEmpty) ...[
            const SizedBox(height: 30),
            const Center(
              child: Text(
                'Aucun défi terminé pour le moment.\n'
                'Votre premier défi apparaîtra ici après validation.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFFB9CBE0)),
              ),
            ),
          ],
          for (final item in _entries) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: const Color(0xFF244B68)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('d MMMM yyyy', 'fr').format(item.day),
                    style: const TextStyle(color: _gold, fontSize: 13),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.mode == 'cas_clinique'
                        ? 'Cas clinique progressif'
                        : '10 QCM de cours',
                    style: const TextStyle(color: Color(0xFFB9CBE0)),
                  ),
                  const SizedBox(height: 11),
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    children: [
                      Text(
                        'Note officielle : ${item.officialScore}/10',
                        style: const TextStyle(
                          color: _mint,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item.lastReplayScore != null)
                        Text(
                          'Dernier rejeu : ${item.lastReplayScore}/10',
                          style: const TextStyle(color: Colors.white),
                        ),
                      Text(
                        '${item.replayCount} rejeu(x)',
                        style: const TextStyle(color: Color(0xFFB9CBE0)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _replay(item),
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Rejouer'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_hasMore && !_busy) ...[
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () => _load(),
              child: const Text('Afficher plus de défis'),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.exit_to_app_rounded),
              label: const Text('Quitter l’historique'),
            ),
          ),
        ],
        ),
      ),
      ),
    );
  }
}
