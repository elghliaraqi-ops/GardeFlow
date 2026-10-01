import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../theme/screen_decor.dart';

class SettingsScreen extends StatefulWidget {
  final bool reminderFocus;

  const SettingsScreen({super.key, this.reminderFocus = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _presets = <int>[2880, 1440, 720, 360, 180, 120, 60, 30];
  static const _fullScreenPreferenceKey = 'guard_fullscreen_alarm';

  bool _saving = false;
  bool _migratedToAlarm = false;
  bool _fullScreenAlarm = true;
  bool _fullScreenPreferenceLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFullScreenPreference();
  }

  Future<void> _loadFullScreenPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_fullScreenPreferenceKey) ?? true;
    if (!mounted) return;
    setState(() {
      _fullScreenAlarm = enabled;
      _fullScreenPreferenceLoaded = true;
    });
  }

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
        // Le menu doit rester utilisable même si Android refuse un accès.
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

  Future<void> _setFullScreenAlarm(
    AppState appState,
    bool enabled,
  ) async {
    await _run(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_fullScreenPreferenceKey, enabled);
      if (mounted) setState(() => _fullScreenAlarm = enabled);

      if (enabled) {
        await appState.setReminderSoundMode('alarm');
        await NotificationService.instance.prepareAlarmModePermissions();
      }
      await appState.rescheduleAllReminders();
    });
  }

  Future<void> _setVibration(
    AppState appState,
    bool enabled,
  ) async {
    await _run(() async {
      await appState.setReminderVibration(enabled);
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

  Future<void> _testAlarm(AppState appState) async {
    await _run(() async {
      await appState.setReminderSoundMode('alarm');
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
          padding: EdgeInsets.fromLTRB(
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
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: AppColors.inkSoft,
                    ),
              ),
              SizedBox(height: AppSpace.lg),
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
          padding: EdgeInsets.fromLTRB(
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
                  Icon(
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
              Text(
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
                text:
                    'Sur Samsung, retirez GardeFlow des applications en veille si elle y apparaît.',
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

    return DecorScaffold(scene: ScreenDecorScene.settings, 
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle('Rappels de garde'),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.lg,
            34,
          ),
          children: [
            _AlarmHero(
              enabled: appState.notificationsOn,
              saving: _saving,
              onChanged: (value) => _toggleAlarm(appState, value),
            ),
            SizedBox(height: AppSpace.xl),

            SectionLabel('Comportement de l’alarme'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _AlarmSettingTile(
                    icon: Icons.open_in_full_rounded,
                    title: 'Écran plein écran prioritaire',
                    subtitle:
                        'Au déclenchement, GardeFlow ouvre un véritable écran d’alarme au premier plan, y compris sur l’écran verrouillé lorsque Android l’autorise.',
                    trailing: Switch(
                      value: _fullScreenAlarm,
                      onChanged: !_fullScreenPreferenceLoaded || _saving
                          ? null
                          : (value) =>
                              _setFullScreenAlarm(appState, value),
                    ),
                  ),
                  const _TileDivider(),
                  _AlarmSettingTile(
                    icon: Icons.vibration_rounded,
                    title: 'Vibration continue',
                    subtitle:
                        'Le téléphone vibre pendant la sonnerie jusqu’à votre action.',
                    trailing: Switch(
                      value: appState.reminderVibration,
                      onChanged: _saving
                          ? null
                          : (value) => _setVibration(appState, value),
                    ),
                  ),
                  const _TileDivider(),
                  const _AlarmSettingTile(
                    icon: Icons.snooze_rounded,
                    title: 'Rappel rapide',
                    subtitle:
                        'Le bouton « RAPPEL 9 MIN » reporte l’alarme sans supprimer la garde.',
                    trailing: _FixedBadge(label: '9 MIN'),
                  ),
                  const _TileDivider(),
                  const _AlarmSettingTile(
                    icon: Icons.lock_clock_rounded,
                    title: 'Sonnerie longue',
                    subtitle:
                        'La sonnerie ne s’arrête pas automatiquement : il faut appuyer sur « J’AI VU — ARRÊTER ».',
                    trailing: _FixedBadge(label: 'ACTIF'),
                  ),
                ],
              ),
            ),

            SizedBox(height: AppSpace.xl),
            SectionLabel('Quand sonner ?'),
            AppCard(
              padding: EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Alarmes avant chaque garde',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Les alarmes sont programmées uniquement pour les gardes d’un calendrier définitivement validé.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.inkSoft,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 13),
                  for (final minutes in delays)
                    _DelayTile(
                      label: appState.reminderDelayLabel(minutes),
                      saving: _saving,
                      onDelete: () => _removeDelay(appState, minutes),
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

            SizedBox(height: AppSpace.xl),
            SectionLabel('État des alarmes Android'),
            AppCard(
              padding: EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder<String>(
                    valueListenable:
                        NotificationService.instance.reminderStatus,
                    builder: (context, status, _) {
                      final problem =
                          status.toLowerCase().contains('non prête') ||
                              status.toLowerCase().contains('impossible') ||
                              status.toLowerCase().contains('indisponible') ||
                              status.toLowerCase().contains('vérifiez');
                      return _ReadinessBanner(
                        ready: !problem,
                        status: status,
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  const _PermissionLine(
                    icon: Icons.notifications_active_rounded,
                    title: 'Notifications',
                    text:
                        'Nécessaires pour afficher l’alarme et ses commandes système.',
                  ),
                  const SizedBox(height: 11),
                  const _PermissionLine(
                    icon: Icons.alarm_on_rounded,
                    title: 'Alarmes exactes',
                    text:
                        'Permettent de sonner à l’heure prévue, même en veille.',
                  ),
                  const SizedBox(height: 11),
                  const _PermissionLine(
                    icon: Icons.fullscreen_rounded,
                    title: 'Plein écran',
                    text:
                        'Autorise l’écran d’alarme à passer au premier plan sur Android compatible.',
                  ),
                  const SizedBox(height: 11),
                  const _PermissionLine(
                    icon: Icons.battery_saver_rounded,
                    title: 'Batterie non restreinte',
                    text:
                        'Recommandé surtout sur Samsung pour éviter la mise en veille agressive.',
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          _saving ? null : () => _configureAndroid(appState),
                      icon: const Icon(Icons.verified_user_rounded),
                      label: const Text(
                        'Vérifier / activer les autorisations',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showBatteryHelp,
                      icon: const Icon(Icons.battery_saver_rounded),
                      label: const Text('Réglages batterie Samsung / Android'),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: AppSpace.xl),
            SectionLabel('Test plein écran'),
            AppCard(
              padding: EdgeInsets.all(AppSpace.lg),
              color: AppColors.brandSoft,
              shadow: const [],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.brand,
                        size: 25,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tester comme une vraie garde',
                              style: TextStyle(
                                color: AppColors.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Le téléphone va sonner, vibrer et ouvrir l’écran d’alarme. Utilisez ensuite « RAPPEL 9 MIN » ou « J’AI VU — ARRÊTER ».',
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
                  const SizedBox(height: 13),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed:
                          _saving ? null : () => _testAlarm(appState),
                      icon: const Icon(Icons.alarm_rounded),
                      label: const Text('LANCER L’ALARME PLEIN ÉCRAN'),
                    ),
                  ),
                ],
              ),
            ),

            if (appState.nextReminderSummary != null) ...[
              SizedBox(height: AppSpace.lg),
              AppCard(
                padding: EdgeInsets.all(AppSpace.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.event_available_rounded,
                      color: AppColors.brand,
                      size: 20,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        appState.nextReminderSummary!,
                        style: TextStyle(
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
      ),
    );
  }
}

class _AlarmHero extends StatelessWidget {
  final bool enabled;
  final bool saving;
  final ValueChanged<bool> onChanged;

  const _AlarmHero({
    required this.enabled,
    required this.saving,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandDark, AppColors.brand],
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withOpacity(0.22),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.alarm_on_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ALARME DE GARDE',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Une véritable alarme prioritaire : sonnerie longue, vibration et écran plein écran au premier plan.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontSize: 11.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  enabled
                      ? Icons.check_circle_rounded
                      : Icons.pause_circle_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    enabled
                        ? 'Alarmes activées'
                        : 'Alarmes désactivées',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: saving ? null : onChanged,
                  activeColor: Colors.white,
                  activeTrackColor: Colors.white.withOpacity(0.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlarmSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _AlarmSettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: AppColors.brand,
              size: 22,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

class _FixedBadge extends StatelessWidget {
  final String label;

  const _FixedBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.brand.withOpacity(0.18),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.brand,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _DelayTile extends StatelessWidget {
  final String label;
  final bool saving;
  final VoidCallback onDelete;

  const _DelayTile({
    required this.label,
    required this.saving,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Icon(
            Icons.alarm_rounded,
            color: AppColors.brand,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Supprimer',
            visualDensity: VisualDensity.compact,
            onPressed: saving ? null : onDelete,
            icon: Icon(
              Icons.close_rounded,
              size: 19,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadinessBanner extends StatelessWidget {
  final bool ready;
  final String status;

  const _ReadinessBanner({
    required this.ready,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ready ? AppColors.brand : Colors.orangeAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withOpacity(0.24),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready
                ? Icons.verified_rounded
                : Icons.warning_amber_rounded,
            color: accent,
            size: 21,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready
                      ? 'Alarmes prêtes'
                      : 'Configuration à vérifier',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 10.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _PermissionLine({
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
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.paperAlt,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 18,
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
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: TextStyle(
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

class _TileDivider extends StatelessWidget {
  const _TileDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: AppSpace.lg,
      endIndent: AppSpace.lg,
      color: AppColors.line,
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
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
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
                style: TextStyle(
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
