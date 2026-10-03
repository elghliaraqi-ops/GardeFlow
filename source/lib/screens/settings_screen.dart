import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/alarm_ring_service.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/screen_decor.dart';
import '../theme/widgets.dart';

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
  bool _loadingAppleStatus = false;
  AppleAlarmKitStatus? _appleStatus;

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (_isAndroid) {
      _loadFullScreenPreference();
    } else {
      _fullScreenPreferenceLoaded = true;
    }
    if (_isIOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAppleStatus());
    }
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

  Future<void> _refreshAppleStatus() async {
    if (!_isIOS || _loadingAppleStatus) return;
    if (mounted) setState(() => _loadingAppleStatus = true);
    final status = await NotificationService.instance.appleAlarmStatus();
    await NotificationService.instance.refreshReminderStatus();
    if (!mounted) return;
    setState(() {
      _appleStatus = status;
      _loadingAppleStatus = false;
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
        // L'écran de réglages doit toujours rester accessible.
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
      if (_isIOS) await _refreshAppleStatus();
    });
  }

  Future<void> _setFullScreenAlarm(AppState appState, bool enabled) async {
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

  Future<void> _setVibration(AppState appState, bool enabled) async {
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

  Future<void> _configureIOS(AppState appState) async {
    await _run(() async {
      await appState.setReminderSoundMode('alarm');
      await NotificationService.instance.prepareAlarmModePermissions();
      await appState.rescheduleAllReminders();
      final status = await NotificationService.instance.appleAlarmStatus();
      if (mounted) setState(() => _appleStatus = status);
    });
  }

  Future<void> _openIOSSettings() async {
    final opened = await NotificationService.instance.openReminderSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible d’ouvrir les Réglages iPhone.'),
        ),
      );
    }
  }

  Future<void> _testAlarm(AppState appState) async {
    await _run(() async {
      await appState.setReminderSoundMode('alarm');
      await NotificationService.instance.prepareAlarmModePermissions();
      await appState.testGuardReminder();
      if (_isIOS) {
        final status = await NotificationService.instance.appleAlarmStatus();
        if (mounted) setState(() => _appleStatus = status);
      }
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
                'Quand le rappel doit-il sonner ?',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 5),
              Text(
                'Vous pouvez programmer jusqu’à 3 rappels avant chaque garde validée.',
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
                      avatar: Icon(
                        _isIOS
                            ? Icons.notifications_active_rounded
                            : Icons.alarm_rounded,
                        size: 17,
                      ),
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
          content: Text('Gardez au moins un rappel avant la garde.'),
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
                  Icon(Icons.battery_saver_rounded, color: AppColors.brand),
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

    return DecorScaffold(
      scene: ScreenDecorScene.settings,
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle(
          _isIOS ? 'Rappels iPhone' : 'Rappels de garde',
        ),
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
          children: _isIOS
              ? _buildIOSContent(context, appState, delays)
              : _buildAndroidContent(context, appState, delays),
        ),
      ),
    );
  }

  List<Widget> _buildIOSContent(
    BuildContext context,
    AppState appState,
    List<int> delays,
  ) {
    final apple = _appleStatus;
    final nativeReady = apple?.authorized == true;
    final supported = apple?.supported == true;
    final fallback = apple != null && !nativeReady;

    return [
      _PlatformHero(
        appleStyle: true,
        enabled: appState.notificationsOn,
        saving: _saving,
        title: 'RAPPELS iPHONE',
        subtitle:
            'Une expérience dédiée à iOS : alarme système Apple quand elle est disponible, puis mode compatible sur les iPhone plus anciens.',
        onChanged: (value) => _toggleAlarm(appState, value),
      ),
      SizedBox(height: AppSpace.xl),
      SectionLabel('Alarmes système Apple'),
      AppCard(
        padding: EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: NotificationService.instance.reminderStatus,
              builder: (context, status, _) => _ReadinessBanner(
                ready: nativeReady || fallback,
                status: _loadingAppleStatus
                    ? 'Vérification des capacités de l’iPhone…'
                    : status,
                appleStyle: true,
              ),
            ),
            const SizedBox(height: 15),
            _IOSCapabilityTile(
              icon: Icons.alarm_on_rounded,
              title: 'AlarmKit · iOS 26+',
              text: supported
                  ? (nativeReady
                      ? 'Autorisé sur cet iPhone. Les alarmes de garde sont confiées au moteur système Apple.'
                      : 'Disponible sur cet iPhone. Activez l’autorisation Apple pour utiliser le moteur système.')
                  : 'Non disponible sur cette version d’iOS. GardeFlow utilise automatiquement son moteur compatible.',
              badge: nativeReady
                  ? 'ACTIF'
                  : supported
                      ? 'À ACTIVER'
                      : 'COMPATIBLE',
              badgeReady: nativeReady,
            ),
            const SizedBox(height: 10),
            const _IOSCapabilityTile(
              icon: Icons.phone_iphone_rounded,
              title: 'Interface Apple',
              text:
                  'Sur les iPhone compatibles, l’alarme est présentée par iOS sur l’écran verrouillé et dans les surfaces système Apple.',
              badge: 'iOS',
              badgeReady: true,
            ),
            const SizedBox(height: 10),
            const _IOSCapabilityTile(
              icon: Icons.shield_outlined,
              title: 'Mode compatible iOS 13–25',
              text:
                  'Les anciens iPhone conservent les rappels sonores via le moteur local GardeFlow. Évitez de forcer la fermeture de l’app avant une garde.',
              badge: 'SECOURS',
              badgeReady: true,
            ),
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1478F2),
                  foregroundColor: Colors.white,
                ),
                onPressed: _saving ? null : () => _configureIOS(appState),
                icon: const Icon(Icons.verified_user_rounded),
                label: Text(
                  nativeReady
                      ? 'VÉRIFIER LES ALARMES APPLE'
                      : 'ACTIVER LES ALARMES APPLE',
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _openIOSSettings,
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Ouvrir Réglages iPhone'),
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: AppSpace.xl),
      SectionLabel('Comportement sur iPhone'),
      AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            const _AlarmSettingTile(
              icon: Icons.volume_up_rounded,
              title: 'Sonnerie système Apple',
              subtitle:
                  'Sur iOS 26+, le son de l’alarme est piloté par le système Apple. Sur les anciens iOS, GardeFlow utilise son moteur compatible.',
              trailing: _FixedBadge(
                label: 'AUTO',
                appleStyle: true,
              ),
              appleStyle: true,
            ),
            const _TileDivider(),
            _AlarmSettingTile(
              icon: Icons.vibration_rounded,
              title: 'Vibration du mode compatible',
              subtitle:
                  'Utilisée par le moteur local sur les anciens iPhone. AlarmKit applique lui-même le comportement système sur iOS 26+.',
              trailing: Switch.adaptive(
                value: appState.reminderVibration,
                onChanged: _saving
                    ? null
                    : (value) => _setVibration(appState, value),
              ),
              appleStyle: true,
            ),
            const _TileDivider(),
            const _AlarmSettingTile(
              icon: Icons.lock_rounded,
              title: 'Écran verrouillé',
              subtitle:
                  'L’interface iPhone reste celle d’Apple : GardeFlow ne force pas un écran Android sur iOS.',
              trailing: _FixedBadge(
                label: 'APPLE',
                appleStyle: true,
              ),
              appleStyle: true,
            ),
          ],
        ),
      ),
      SizedBox(height: AppSpace.xl),
      SectionLabel('Avant chaque garde'),
      _buildDelayCard(context, appState, delays, appleStyle: true),
      SizedBox(height: AppSpace.xl),
      SectionLabel('Test iPhone'),
      AppCard(
        padding: EdgeInsets.all(AppSpace.lg),
        color: const Color(0xFFEFF6FF),
        shadow: const [],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.notifications_active_rounded,
                  color: Color(0xFF1478F2),
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tester le vrai chemin iPhone',
                        style: TextStyle(
                          color: Color(0xFF10233E),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        nativeReady
                            ? 'Un test AlarmKit sera programmé dans quelques secondes avec l’interface système Apple.'
                            : 'Le test utilisera automatiquement le moteur compatible disponible sur cet iPhone.',
                        style: const TextStyle(
                          color: Color(0xFF536A86),
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
                  backgroundColor: const Color(0xFF1478F2),
                  foregroundColor: Colors.white,
                ),
                onPressed: _saving ? null : () => _testAlarm(appState),
                icon: const Icon(Icons.alarm_rounded),
                label: const Text('TESTER LE RAPPEL iPHONE'),
              ),
            ),
          ],
        ),
      ),
      if (appState.nextReminderSummary != null) ...[
        SizedBox(height: AppSpace.lg),
        _NextReminderCard(
          text: appState.nextReminderSummary!,
          appleStyle: true,
        ),
      ],
    ];
  }

  List<Widget> _buildAndroidContent(
    BuildContext context,
    AppState appState,
    List<int> delays,
  ) {
    return [
      _PlatformHero(
        appleStyle: false,
        enabled: appState.notificationsOn,
        saving: _saving,
        title: 'ALARME DE GARDE',
        subtitle:
            'Une véritable alarme prioritaire : sonnerie longue, vibration et écran plein écran au premier plan.',
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
                  'Au déclenchement, GardeFlow ouvre l’écran d’alarme au premier plan, y compris sur l’écran verrouillé lorsque Android l’autorise.',
              trailing: Switch(
                value: _fullScreenAlarm,
                onChanged: !_fullScreenPreferenceLoaded || _saving
                    ? null
                    : (value) => _setFullScreenAlarm(appState, value),
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
                  'La sonnerie ne s’arrête pas automatiquement : utilisez « J’AI VU — ARRÊTER ».',
              trailing: _FixedBadge(label: 'ACTIF'),
            ),
          ],
        ),
      ),
      SizedBox(height: AppSpace.xl),
      SectionLabel('Quand sonner ?'),
      _buildDelayCard(context, appState, delays),
      SizedBox(height: AppSpace.xl),
      SectionLabel('État des alarmes Android'),
      AppCard(
        padding: EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<String>(
              valueListenable: NotificationService.instance.reminderStatus,
              builder: (context, status, _) {
                final lower = status.toLowerCase();
                final problem = lower.contains('non prête') ||
                    lower.contains('impossible') ||
                    lower.contains('indisponible') ||
                    lower.contains('vérifiez');
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
              text: 'Permettent de sonner à l’heure prévue, même en veille.',
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
                onPressed: _saving ? null : () => _configureAndroid(appState),
                icon: const Icon(Icons.verified_user_rounded),
                label: const Text('Vérifier / activer les autorisations'),
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
                onPressed: _saving ? null : () => _testAlarm(appState),
                icon: const Icon(Icons.alarm_rounded),
                label: const Text('LANCER L’ALARME PLEIN ÉCRAN'),
              ),
            ),
          ],
        ),
      ),
      if (appState.nextReminderSummary != null) ...[
        SizedBox(height: AppSpace.lg),
        _NextReminderCard(text: appState.nextReminderSummary!),
      ],
    ];
  }

  Widget _buildDelayCard(
    BuildContext context,
    AppState appState,
    List<int> delays, {
    bool appleStyle = false,
  }) {
    final accent = appleStyle ? const Color(0xFF1478F2) : AppColors.brand;
    return AppCard(
      padding: EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            appleStyle
                ? 'Rappels avant chaque garde'
                : 'Alarmes avant chaque garde',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Ils sont programmés uniquement pour les gardes d’un calendrier définitivement validé.',
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
              appleStyle: appleStyle,
            ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: appleStyle
                  ? OutlinedButton.styleFrom(foregroundColor: accent)
                  : null,
              onPressed:
                  _saving || delays.length >= 3 ? null : () => _addDelay(appState),
              icon: Icon(
                appleStyle
                    ? Icons.add_alert_rounded
                    : Icons.add_alarm_rounded,
              ),
              label: Text(
                appleStyle ? 'Ajouter un rappel' : 'Ajouter une alarme',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformHero extends StatelessWidget {
  final bool appleStyle;
  final bool enabled;
  final bool saving;
  final String title;
  final String subtitle;
  final ValueChanged<bool> onChanged;

  const _PlatformHero({
    required this.appleStyle,
    required this.enabled,
    required this.saving,
    required this.title,
    required this.subtitle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appleStyle
        ? const [Color(0xFF102A56), Color(0xFF1478F2)]
        : [AppColors.brandDark, AppColors.brand];
    return Container(
      padding: EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: colors.last.withOpacity(0.22),
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
                child: Icon(
                  appleStyle
                      ? Icons.phone_iphone_rounded
                      : Icons.alarm_on_rounded,
                  color: Colors.white,
                  size: 31,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                        ? (appleStyle
                            ? 'Rappels iPhone activés'
                            : 'Alarmes activées')
                        : (appleStyle
                            ? 'Rappels iPhone désactivés'
                            : 'Alarmes désactivées'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                Switch.adaptive(
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

class _IOSCapabilityTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String badge;
  final bool badgeReady;

  const _IOSCapabilityTile({
    required this.icon,
    required this.title,
    required this.text,
    required this.badge,
    required this.badgeReady,
  });

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1478F2);
    final badgeColor = badgeReady ? blue : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FD),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5ECF5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE7F1FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: blue, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF10233E),
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: Color(0xFF60738B),
                    fontSize: 10.8,
                    height: 1.42,
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

class _AlarmSettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final bool appleStyle;

  const _AlarmSettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.appleStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = appleStyle ? const Color(0xFF1478F2) : AppColors.brand;
    final soft = appleStyle ? const Color(0xFFE7F1FF) : AppColors.brandSoft;
    return Padding(
      padding: EdgeInsets.all(AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: accent, size: 22),
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
  final bool appleStyle;

  const _FixedBadge({required this.label, this.appleStyle = false});

  @override
  Widget build(BuildContext context) {
    final accent = appleStyle ? const Color(0xFF1478F2) : AppColors.brand;
    final soft = appleStyle ? const Color(0xFFE7F1FF) : AppColors.brandSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
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
  final bool appleStyle;

  const _DelayTile({
    required this.label,
    required this.saving,
    required this.onDelete,
    this.appleStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = appleStyle ? const Color(0xFF1478F2) : AppColors.brand;
    final soft = appleStyle ? const Color(0xFFF1F6FD) : AppColors.brandSoft;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: accent.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(
            appleStyle
                ? Icons.notifications_active_rounded
                : Icons.alarm_rounded,
            color: accent,
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
  final bool appleStyle;

  const _ReadinessBanner({
    required this.ready,
    required this.status,
    this.appleStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = ready
        ? (appleStyle ? const Color(0xFF1478F2) : AppColors.brand)
        : Colors.orangeAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ready ? Icons.verified_rounded : Icons.warning_amber_rounded,
            color: accent,
            size: 22,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              status,
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                height: 1.35,
              ),
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
        Icon(icon, color: AppColors.brand, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                color: AppColors.inkSoft,
                fontFamily: 'Inter',
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: '$title · ',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GuideLine extends StatelessWidget {
  final String number;
  final String text;

  const _GuideLine({required this.number, required this.text});

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
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
      color: AppColors.inkSoft.withOpacity(0.10),
    );
  }
}

class _NextReminderCard extends StatelessWidget {
  final String text;
  final bool appleStyle;

  const _NextReminderCard({required this.text, this.appleStyle = false});

  @override
  Widget build(BuildContext context) {
    final accent = appleStyle ? const Color(0xFF1478F2) : AppColors.brand;
    return AppCard(
      padding: EdgeInsets.all(AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_available_rounded, color: accent, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
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
    );
  }
}
