from pathlib import Path

EXPECTED = "version: 11.6.35+195"
TARGET = "version: 11.6.36+196"

pubspec = Path("pubspec.yaml")
pub = pubspec.read_text()
if EXPECTED not in pub:
    raise SystemExit("V11.6.36: base version mismatch")
pubspec.write_text(pub.replace(EXPECTED, TARGET, 1))

settings = Path("lib/screens/settings_screen.dart")
settings.write_text(r"""import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class SettingsScreen extends StatefulWidget {
  final bool reminderFocus;

  const SettingsScreen({
    super.key,
    this.reminderFocus = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _presets = <int>[2880, 1440, 720, 360, 180, 120, 60, 30];
  bool _saving = false;
  bool _migratedToAlarm = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_migratedToAlarm) return;
    _migratedToAlarm = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final appState = context.read<AppState>();
      if (appState.reminderSoundMode == 'alarm') return;

      try {
        await appState.setReminderSoundMode('alarm');
        await appState.setReminderVibration(true);
        await appState.rescheduleAllReminders();
      } catch (_) {
        // Migration silencieuse : l'écran doit rester utilisable.
      }
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Action impossible : ${e.toString().replaceFirst('Bad state: ', '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleAlarm(AppState appState, bool enabled) async {
    await _run(() async {
      await appState.setNotificationsOn(enabled);
      if (enabled) {
        await appState.setReminderSoundMode('alarm');
        await appState.setReminderVibration(true);
        await NotificationService.instance.prepareAlarmModePermissions();
      }
      await appState.rescheduleAllReminders();
    });
  }

  Future<void> _configureAndroid(AppState appState) async {
    await _run(() async {
      await appState.setReminderSoundMode('alarm');
      await NotificationService.instance.prepareAlarmModePermissions();
      await appState.rescheduleAllReminders();
    });
  }

  Future<void> _requestNotifications() async {
    await _run(() async {
      await NotificationService.instance.requestPermission();
    });
  }

  Future<void> _testAlarm(AppState appState) async {
    await _run(() async {
      await appState.setReminderSoundMode('alarm');
      await appState.setReminderVibration(true);
      await NotificationService.instance.prepareAlarmModePermissions();
      await appState.testGuardReminder();
    });
  }

  Future<void> _addDelay(AppState appState) async {
    if (appState.reminderDelays.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Maximum : 3 alarmes avant chaque garde.'),
        ),
      );
      return;
    }

    final available = _presets
        .where((minutes) => !appState.reminderDelays.contains(minutes))
        .toList();

    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            0,
            AppSpace.lg,
            AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quand l’alarme doit-elle sonner ?',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(
                'Vous pouvez programmer jusqu’à 3 alarmes avant chaque garde validée.',
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.inkSoft),
              ),
              const SizedBox(height: AppSpace.lg),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in available)
                    ActionChip(
                      avatar: const Icon(Icons.alarm_rounded, size: 17),
                      label: Text(appState.reminderDelayLabel(minutes)),
                      onPressed: () => Navigator.pop(ctx, minutes),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    await _run(() async {
      final next = <int>{...appState.reminderDelays, choice}.toList();
      await appState.setReminderDelays(next);
      await appState.rescheduleAllReminders();
    });
  }

  Future<void> _removeDelay(AppState appState, int minutes) async {
    if (appState.reminderDelays.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gardez au moins une alarme avant la garde.'),
        ),
      );
      return;
    }

    await _run(() async {
      final next = appState.reminderDelays
          .where((value) => value != minutes)
          .toList();
      await appState.setReminderDelays(next);
      await appState.rescheduleAllReminders();
    });
  }

  void _showBatteryHelp() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            0,
            AppSpace.lg,
            AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.battery_saver_rounded,
                    color: AppColors.brand,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'Batterie Android / Samsung',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Pour éviter qu’Android limite GardeFlow en arrière-plan :',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const _GuideLine(
                number: '1',
                text: 'Ouvrez Paramètres Android → Applications → GardeFlow.',
              ),
              const _GuideLine(
                number: '2',
                text: 'Ouvrez Batterie puis choisissez « Non restreinte ».',
              ),
              const _GuideLine(
                number: '3',
                text: 'Sur Samsung, retirez GardeFlow des applications en veille si elle y apparaît.',
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('J’ai compris'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final delays = [...appState.reminderDelays]
      ..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const GardeFlowTitle('Alarme de garde'),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          34,
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.brandDark,
                  AppColors.brand,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand.withOpacity(0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.alarm_on_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Alarme de garde',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Une vraie alarme locale : sonnerie longue, vibration et écran plein écran jusqu’à Arrêter.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            appState.notificationsOn
                                ? 'ACTIVÉE'
                                : 'DÉSACTIVÉE',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          Switch(
                            value: appState.notificationsOn,
                            onChanged: _saving
                                ? null
                                : (value) => _toggleAlarm(appState, value),
                            activeColor: Colors.white,
                            activeTrackColor:
                                Colors.white.withOpacity(0.34),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.xl),
          const SectionLabel('Quand sonner ?'),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alarmes avant chaque garde',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Elles sont programmées uniquement pour les gardes d’un calendrier définitivement validé.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.inkSoft),
                ),
                const SizedBox(height: 13),
                for (final minutes in delays)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: AppColors.brand.withOpacity(0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.alarm_rounded,
                          color: AppColors.brand,
                          size: 20,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            appState.reminderDelayLabel(minutes),
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Supprimer',
                          visualDensity: VisualDensity.compact,
                          onPressed: _saving
                              ? null
                              : () => _removeDelay(appState, minutes),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 19,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _saving || delays.length >= 3
                        ? null
                        : () => _addDelay(appState),
                    icon: const Icon(Icons.add_alarm_rounded),
                    label: const Text('Ajouter une alarme'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.xl),
          const SectionLabel('Fiabilité Android'),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.brand,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pour une fiabilité maximale',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'GardeFlow programme l’alarme directement sur le téléphone. Une fois programmée, elle ne dépend plus d’Internet.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.inkSoft,
                                  height: 1.45,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const _ReliabilityLine(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notifications autorisées',
                  text: 'Android doit laisser GardeFlow afficher l’alarme et son écran de réveil.',
                ),
                const SizedBox(height: 10),
                const _ReliabilityLine(
                  icon: Icons.alarm_on_outlined,
                  title: 'Alarmes et rappels autorisés',
                  text: 'Permet une programmation exacte, même téléphone verrouillé.',
                ),
                const SizedBox(height: 10),
                const _ReliabilityLine(
                  icon: Icons.battery_saver_outlined,
                  title: 'Batterie non restreinte',
                  text: 'Recommandé surtout sur Samsung pour éviter la mise en veille agressive.',
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _configureAndroid(appState),
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text(
                      'Configurer les autorisations Android',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _requestNotifications,
                        icon: const Icon(
                          Icons.notifications_none_rounded,
                          size: 18,
                        ),
                        label: const Text('Notifications'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showBatteryHelp,
                        icon: const Icon(
                          Icons.battery_saver_rounded,
                          size: 18,
                        ),
                        label: const Text('Batterie'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable:
                      NotificationService.instance.reminderStatus,
                  builder: (context, status, _) => Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.paperAlt,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 17,
                          color: AppColors.inkSoft,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            status,
                            style: const TextStyle(
                              color: AppColors.inkSoft,
                              fontSize: 10.5,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpace.xl),
          const SectionLabel('Test'),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            color: AppColors.brandSoft,
            shadow: const [],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.play_circle_outline_rounded,
                      color: AppColors.brand,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Tester l’alarme maintenant',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Le test doit lancer une vraie sonnerie en boucle avec l’écran d’alarme. Elle ne s’arrête que lorsque vous appuyez sur Arrêter.',
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 11.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _testAlarm(appState),
                    icon: const Icon(Icons.alarm_rounded),
                    label: const Text('Lancer le test'),
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Si le test sonne correctement après avoir accordé les autorisations ci-dessus, la configuration locale de l’alarme est prête. Android peut toutefois modifier des autorisations après une mise à jour ou une réinstallation : revenez ici si un test échoue.',
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          if (appState.nextReminderSummary != null) ...[
            const SizedBox(height: AppSpace.lg),
            AppCard(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.event_available_rounded,
                    color: AppColors.brand,
                    size: 20,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      appState.nextReminderSummary!,
                      style: const TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 11.5,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReliabilityLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _ReliabilityLine({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 17,
            color: AppColors.brand,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: const TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 10.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GuideLine extends StatelessWidget {
  final String number;
  final String text;

  const _GuideLine({
    required this.number,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: AppColors.brand,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 11,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
""")

news = Path("lib/screens/daily_news_section.dart")
n = news.read_text()

old_rows = """    final rows = List<Map<String, dynamic>>.from(response as List);
    final all = rows.map(_DailyNewsItem.fromMap).toList();
    return all.take(8).toList();"""

new_rows = """    final rows = List<Map<String, dynamic>>.from(response as List);
    final instagramRows = rows.where((row) {
      final mediaType = (row['media_type'] ?? '').toString().toUpperCase();
      final externalId = (row['external_id'] ?? '').toString();
      return mediaType != 'WEB' && !externalId.startsWith('web-');
    });
    final all = instagramRows.map(_DailyNewsItem.fromMap).toList();
    return all.take(8).toList();"""

if old_rows not in n:
    raise SystemExit("V11.6.36: news rows block not found")
n = n.replace(old_rows, new_rows, 1)

n = n.replace(
    "'Vie universitaire et hospitalière'",
    "'Publications Instagram officielles'",
    1,
)
n = n.replace(
    "'Ouvrir la source'",
    "'Voir sur Instagram'",
)
n = n.replace(
    "'Les dernières actualités officielles arrivent ici.'",
    "'Les publications Instagram officielles arrivent ici.'",
)
n = n.replace(
    "'Accès direct aux comptes officiels :'",
    "'Accès direct aux comptes Instagram officiels :'",
)

news.write_text(n)

print("GardeFlow V11.6.36: Instagram uniquement + refonte Alarme de garde")
