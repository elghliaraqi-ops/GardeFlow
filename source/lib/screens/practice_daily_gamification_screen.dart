import 'package:flutter/material.dart';

import '../models/practice_daily_gamification_models.dart';
import '../services/practice_daily_gamification_service.dart';
import 'practice_daily_history_screen.dart';
import 'practice_daily_screen.dart';
import 'practice_daily_visual_theme.dart';

const _ink = Color(0xFF071526);
const _surface = Color(0xFF10243A);
const _mint = Color(0xFF5BE7B0);
const _gold = Color(0xFFFFD166);
const _soft = Color(0xFFB9CBE0);
const _violet = Color(0xFF9886FF);

IconData _badgeIcon(String name) => switch (name) {
  'fire' => Icons.local_fire_department_rounded,
  'calendar' => Icons.calendar_month_rounded,
  'star' => Icons.star_rounded,
  'target' => Icons.track_changes_rounded,
  'medal' => Icons.military_tech_rounded,
  'trophy' => Icons.emoji_events_rounded,
  _ => Icons.flag_rounded,
};

class PracticeDailyGameHubCard extends StatefulWidget {
  const PracticeDailyGameHubCard({super.key});

  @override
  State<PracticeDailyGameHubCard> createState() =>
      _PracticeDailyGameHubCardState();
}

class _PracticeDailyGameHubCardState extends State<PracticeDailyGameHubCard> {
  PracticeDailyGameProfile? _profile;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await PracticeDailyGamificationService.instance.profile();
      if (mounted)
        setState(() {
          _profile = profile;
          _error = null;
          _busy = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = 'Progression indisponible hors connexion';
        });
    }
  }

  Future<void> _navigate(Widget destination) async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => destination));
    if (mounted) await _load();
  }

  Widget _metric(IconData icon, String value, String label, Color color) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.052),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(.075)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 17),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _soft, fontSize: 10),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final value = _profile;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 17, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF193C56), Color(0xFF10243A), Color(0xFF102A35)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF386C77)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _mint.withOpacity(.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bolt_rounded, color: _mint, size: 25),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TON DÉFI QUOTIDIEN',
                      style: TextStyle(
                        color: _mint,
                        fontWeight: FontWeight.w900,
                        fontSize: 10.5,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '10 QCM. Chaque jour.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (value?.finishedToday == true)
                const Icon(Icons.verified_rounded, color: _mint),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            value?.finishedToday == true
                ? 'Défi terminé ! Continue ta progression ou rejoue un ancien cas.'
                : 'Un nouveau défi médical, des XP et des badges à débloquer.',
            style: const TextStyle(color: _soft, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (_busy)
            const LinearProgressIndicator(color: _mint, minHeight: 3)
          else if (value != null) ...[
            Row(
              children: [
                Text(
                  'Niveau ${value.level} · ${value.levelName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  '${value.totalXp} XP',
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: value.levelProgress,
                minHeight: 7,
                backgroundColor: Colors.white.withOpacity(.09),
                valueColor: const AlwaysStoppedAnimation<Color>(_mint),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value.level >= 10
                  ? 'Niveau maximal atteint'
                  : '${value.nextLevelXp - value.totalXp} XP pour le niveau suivant',
              style: const TextStyle(color: _soft, fontSize: 10.5),
            ),
            const SizedBox(height: 13),
            Row(
              children: [
                _metric(
                  Icons.local_fire_department_rounded,
                  '${value.currentStreak} j',
                  'Série',
                  _gold,
                ),
                const SizedBox(width: 7),
                _metric(
                  Icons.check_circle_outline_rounded,
                  '${value.daysCompleted}',
                  'Défis',
                  _mint,
                ),
                const SizedBox(width: 7),
                _metric(
                  Icons.workspace_premium_rounded,
                  '${value.unlockedCount}/${value.badges.length}',
                  'Badges',
                  _violet,
                ),
              ],
            ),
            if (value.badges.isNotEmpty) ...[
              const SizedBox(height: 13),
              const Text(
                'MES BADGES',
                style: TextStyle(
                  color: _soft,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 7),
              SizedBox(
                height: 69,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: value.badges.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final badge = value.badges[index];
                    return Tooltip(
                      message: '${badge.title} · ${badge.description}',
                      child: Container(
                        width: 80,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: badge.unlocked
                              ? _gold.withOpacity(.11)
                              : Colors.white.withOpacity(.035),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: badge.unlocked
                                ? _gold.withOpacity(.34)
                                : Colors.white.withOpacity(.06),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              _badgeIcon(badge.icon),
                              size: 21,
                              color: badge.unlocked
                                  ? _gold
                                  : _soft.withOpacity(.4),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              badge.title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 9,
                                height: 1.1,
                                color: badge.unlocked ? Colors.white : _soft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ] else if (_error != null)
            Text(_error!, style: const TextStyle(color: _soft, fontSize: 12)),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _navigate(const PracticeDailyScreen()),
              icon: Icon(
                value?.finishedToday == true
                    ? Icons.check_circle_outline_rounded
                    : Icons.play_arrow_rounded,
              ),
              label: Text(
                value?.finishedToday == true
                    ? 'Voir mon défi du jour'
                    : 'Commencer le défi du jour',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _mint,
                foregroundColor: _ink,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _navigate(const PracticeDailyLeaderboardScreen()),
                  icon: const Icon(Icons.leaderboard_rounded, size: 17),
                  label: const Text('Classement'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _navigate(const PracticeDailyHistoryScreen()),
                  icon: const Icon(Icons.history_rounded, size: 17),
                  label: const Text('Historique'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'XP des défis uniquement · Rejouer ne donne pas de nouveaux XP.',
            style: TextStyle(color: _soft, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// Small but always-visible CTA inside the existing home Practice card.
class PracticeDailyHomePulse extends StatefulWidget {
  const PracticeDailyHomePulse({super.key});

  @override
  State<PracticeDailyHomePulse> createState() => _PracticeDailyHomePulseState();
}

class _PracticeDailyHomePulseState extends State<PracticeDailyHomePulse> {
  PracticeDailyGameProfile? _profile;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final data = await PracticeDailyGamificationService.instance.profile();
      if (mounted) setState(() => _profile = data);
    } catch (_) {
      // Keep the daily challenge CTA available while offline.
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final data = _profile;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.065),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(.13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 23, color: _gold),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'DÉFI DU JOUR · 10 QCM',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (data?.finishedToday == true)
                const Icon(Icons.check_circle_rounded, size: 18, color: _mint),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            data == null
                ? 'Cours ou cas clinique progressif · Un défi chaque jour'
                : 'Niv. ${data.level} · ${data.totalXp} XP  •  '
                      '${data.currentStreak} jour(s) de série  •  '
                      '${data.unlockedCount} badges',
            style: const TextStyle(color: _soft, fontSize: 11.5),
          ),
          if (data != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(90),
              child: LinearProgressIndicator(
                value: data.levelProgress,
                minHeight: 5,
                backgroundColor: Colors.white.withOpacity(.12),
                valueColor: const AlwaysStoppedAnimation<Color>(_mint),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _open(const PracticeDailyScreen()),
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: Text(
                    data?.finishedToday == true ? 'Mon défi' : 'Jouer',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _mint,
                    foregroundColor: _ink,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _open(const PracticeDailyLeaderboardScreen()),
                  icon: const Icon(Icons.emoji_events_outlined, size: 17),
                  label: const Text('Classement'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PracticeDailyLeaderboardScreen extends StatefulWidget {
  const PracticeDailyLeaderboardScreen({super.key});

  @override
  State<PracticeDailyLeaderboardScreen> createState() =>
      _PracticeDailyLeaderboardScreenState();
}

class _PracticeDailyLeaderboardScreenState
    extends State<PracticeDailyLeaderboardScreen> {
  String _period = 'month';
  List<PracticeDailyGameRank> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await PracticeDailyGamificationService.instance.leaderboard(
        period: _period,
        limit: 50,
      );
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Classement momentanément indisponible.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = (() {
      try {
        return PracticeDailyGamificationService.instance.currentUserId;
      } catch (_) {
        return '';
      }
    })();

    return Theme(
      data: PracticeDailyVisualTheme.from(context),
      child: Scaffold(
        backgroundColor: _ink,
        appBar: AppBar(
        title: const Text('Classement · Défis quotidiens',
          style: TextStyle(
            color: PracticeDailyVisualTheme.text,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        backgroundColor: _ink,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Quitter le classement',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.exit_to_app_rounded),
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
          const Text(
            'LE PODIUM DES DÉFIS',
            style: TextStyle(
              color: _gold,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Un classement distinct des QCM et des gardes. '
            'Seuls les premiers résultats quotidiens rapportent des XP. '
            'Les profils ayant désactivé leur participation sont exclus.',
            style: TextStyle(color: _soft, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'month', label: Text('Ce mois')),
              ButtonSegment(value: 'all', label: Text('Tout le temps')),
            ],
            selected: {_period},
            onSelectionChanged: (values) {
              setState(() => _period = values.first);
              _load();
            },
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(color: _mint),
          ],
          if (_error != null) ...[
            const SizedBox(height: 15),
            Text(_error!, style: const TextStyle(color: _soft)),
            OutlinedButton(onPressed: _load, child: const Text('Réessayer')),
          ],
          if (!_loading && _rows.isEmpty && _error == null) ...[
            const SizedBox(height: 30),
            const Center(
              child: Text(
                'Aucun défi terminé pour cette période.',
                style: TextStyle(color: _soft),
              ),
            ),
          ],
          for (final item in _rows) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: item.userId == user ? _mint.withOpacity(.14) : _surface,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: item.userId == user
                      ? _mint.withOpacity(.50)
                      : const Color(0xFF244B68),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 35,
                    child: Text(
                      '#${item.rank}',
                      style: TextStyle(
                        color: item.rank <= 3 ? _gold : _soft,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.userId == user
                              ? '${item.displayName} · Vous'
                              : item.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${item.completedDays} défis · '
                          '${item.perfectDays} sans-faute'
                          '${item.hospital.isNotEmpty ? ' · ${item.hospital}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _soft, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${item.xp} XP',
                    style: const TextStyle(
                      color: _mint,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.exit_to_app_rounded),
              label: const Text('Quitter le classement'),
            ),
          ),
        ],
        ),
      ),
      ),
    );
  }
}
