import 'package:flutter/material.dart';

import '../models/practice_models.dart';

abstract final class _Palette {
  static const bg = Color(0xFF071526);
  static const surface = Color(0xFF10243A);
  static const raised = Color(0xFF17314E);
  static const line = Color(0xFF244B68);
  static const mint = Color(0xFF5BE7B0);
  static const gold = Color(0xFFFFD166);
  static const text = Color(0xFFF5F8FF);
  static const secondary = Color(0xFFB9CBE0);
}

class PracticeHomeHero extends StatelessWidget {
  const PracticeHomeHero({
    super.key,
    required this.answered,
    required this.accuracy,
    required this.xp,
    required this.streak,
    required this.level,
    required this.loading,
    required this.onStart,
    required this.onQcmRanking,
  });
  final int answered, xp, streak, level;
  final double accuracy;
  final bool loading;
  final VoidCallback onStart, onQcmRanking;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(23),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF563EB7), Color(0xFF204A82), Color(0xFF0B6059)],
      ),
      border: Border.all(color: Colors.white24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.sports_esports_rounded, color: _Palette.gold, size: 21),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'PRACTICE · ESPACE D’ENTRAÎNEMENT',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Progresse, raisonne, maîtrise.',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            height: 1.15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Cas cliniques, QCM, défis et progression',
          style: TextStyle(color: Color(0xFFE2ECFF), fontSize: 12),
        ),
        const SizedBox(height: 13),
        Row(
          children: [
            _Metric('QCM répondus', loading ? '—' : answered.toString()),
            const SizedBox(width: 7),
            _Metric(
              'Réussite',
              loading ? '—' : accuracy.toStringAsFixed(0) + '%',
            ),
            const SizedBox(width: 7),
            _Metric('Niveau', loading ? '—' : level.toString()),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          loading
              ? 'Chargement de votre progression…'
              : xp.toString() +
                    ' XP Practice clinique · ' +
                    streak.toString() +
                    ' garde(s) de série',
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 13),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              backgroundColor: _Palette.mint,
              foregroundColor: _Palette.bg,
              minimumSize: const Size(0, 47),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(
              'Explorer les cas et leurs QCM',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onQcmRanking,
            icon: const Icon(Icons.leaderboard_outlined, size: 16),
            label: const Text(
              'Stats et classement QCM',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
          ),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 9.5),
          ),
        ],
      ),
    ),
  );
}

class PracticeCompactModeCard extends StatelessWidget {
  const PracticeCompactModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.label,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle, label;
  final Color accent;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Ink(
        height: 158,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: accent.withOpacity(.42)),
          gradient: LinearGradient(
            colors: [accent.withOpacity(.20), _Palette.surface],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: accent, size: 24),
                const Spacer(),
                Icon(Icons.north_east_rounded, color: accent, size: 20),
              ],
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _Palette.text,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _Palette.secondary, fontSize: 10.5),
            ),
            const SizedBox(height: 7),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 9,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class PracticeInlineNavigation extends StatelessWidget {
  const PracticeInlineNavigation({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: _Palette.surface,
    borderRadius: BorderRadius.circular(15),
    child: ListTile(
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: _Palette.line),
        borderRadius: BorderRadius.circular(15),
      ),
      onTap: onTap,
      leading: Icon(icon, color: _Palette.mint),
      title: Text(
        title,
        style: const TextStyle(
          color: _Palette.text,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        style: const TextStyle(color: _Palette.secondary, fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: _Palette.mint),
    ),
  );
}

class PracticeAchievementsPreview extends StatelessWidget {
  const PracticeAchievementsPreview({
    super.key,
    required this.achievements,
    required this.loading,
    required this.onOpen,
  });
  final List<PracticeAchievement> achievements;
  final bool loading;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final unlocked = achievements.where((a) => a.unlocked).length;
    final pending = achievements.where((a) => !a.unlocked).toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));
    return Material(
      color: _Palette.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _Palette.gold.withOpacity(.36)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.emoji_events_outlined, color: _Palette.gold),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Collection de succès',
                      style: TextStyle(
                        color: _Palette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: _Palette.gold),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                loading
                    ? 'Chargement…'
                    : unlocked.toString() +
                          ' / ' +
                          achievements.length.toString() +
                          ' succès débloqués',
                style: const TextStyle(color: _Palette.secondary),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: achievements.isEmpty
                      ? 0
                      : unlocked / achievements.length,
                  minHeight: 8,
                  color: _Palette.gold,
                  backgroundColor: _Palette.raised,
                ),
              ),
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 11),
                Text(
                  'À PROXIMITÉ · ' + pending.first.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _Palette.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  pending.first.progress.toString() +
                      ' / ' +
                      pending.first.threshold.toString(),
                  style: const TextStyle(
                    color: _Palette.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
