import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _fullScreenPreferenceKey = 'guard_fullscreen_alarm';
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

  Future<void> _setFullScreenAlarm(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fullScreenPreferenceKey, enabled);
    if (!mounted) return;
    setState(() => _fullScreenAlarm = enabled);
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
              SizedBox(height: 5),
              Text(
                'Vous pouvez programmer jusqu’à 3 alarmes avant chaque garde validée.',
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.inkSoft),
              ),
              SizedBox(height: AppSpace.lg),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in available)
                    ActionChip(
                      avatar: Icon(Icons.alarm_rounded, size: 17),
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
                  SizedBox(width: 9),
                  Text(
                    'Batterie Android / Samsung',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                'Pour éviter qu’Android limite GardeFlow en arrière-plan :',
                style: TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 10),
              _GuideLine(
                number: '1',
                text: 'Ouvrez Paramètres Android → Applications → GardeFlow.',
              ),
              _GuideLine(
                number: '2',
                text: 'Ouvrez Batterie puis choisissez « Non restreinte ».',
              ),
              _GuideLine(
                number: '3',
                text: 'Sur Samsung, retirez GardeFlow des applications en veille si elle y apparaît.',
              ),
              SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('J’ai compris'),
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
        title: GardeFlowTitle('Rappels de garde'),
      ),
      body: ListView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          34,
        ),
        children: [
          SectionLabel('Rappels et alarme'),
          Container(
            padding: EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
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
                  offset: Offset(0, 8),
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
                  child: Icon(
                    Icons.alarm_on_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alarme de garde',
                        style: TextStyle(
                          color: Colors.white,
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Une vraie alarme locale : sonnerie longue, vibration et écran plein écran jusqu’à Arrêter.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 10),
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
                          Spacer(),
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

          SizedBox(height: AppSpace.xl),
          SectionLabel('Affichage de l’alarme'),
          AppCard(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.fullscreen_rounded,
                    color: AppColors.brand,
                    size: 25,
                  ),
                ),
                SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Alarme plein écran',
                        style: TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Afficher le visuel JOUR, NUIT ou 24H quand l’alarme sonne.',
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 11.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Switch(
                  value: _fullScreenAlarm,
                  onChanged: !_fullScreenPreferenceLoaded || _saving
                      ? null
                      : _setFullScreenAlarm,
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
                SizedBox(height: 4),
                Text(
                  'Elles sont programmées uniquement pour les gardes d’un calendrier définitivement validé.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.inkSoft),
                ),
                SizedBox(height: 13),
                for (final minutes in delays)
                  Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.symmetric(
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
                        SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            appState.reminderDelayLabel(minutes),
                            style: TextStyle(
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
                          icon: Icon(
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
                    icon: Icon(Icons.add_alarm_rounded),
                    label: Text('Ajouter une alarme'),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: AppSpace.xl),
          SectionLabel('Fiabilité Android'),
          AppCard(
            padding: EdgeInsets.all(AppSpace.lg),
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
                      child: Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.brand,
                      ),
                    ),
                    SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pour une fiabilité maximale',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SizedBox(height: 4),
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
                SizedBox(height: 14),
                _ReliabilityLine(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notifications autorisées',
                  text: 'Android doit laisser GardeFlow afficher l’alarme et son écran de réveil.',
                ),
                SizedBox(height: 10),
                _ReliabilityLine(
                  icon: Icons.alarm_on_outlined,
                  title: 'Alarmes et rappels autorisés',
                  text: 'Permet une programmation exacte, même téléphone verrouillé.',
                ),
                SizedBox(height: 10),
                _ReliabilityLine(
                  icon: Icons.battery_saver_outlined,
                  title: 'Batterie non restreinte',
                  text: 'Recommandé surtout sur Samsung pour éviter la mise en veille agressive.',
                ),
                SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _configureAndroid(appState),
                    icon: Icon(Icons.settings_rounded),
                    label: Text(
                      'Configurer les autorisations Android',
                    ),
                  ),
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _requestNotifications,
                        icon: Icon(
                          Icons.notifications_none_rounded,
                          size: 18,
                        ),
                        label: Text('Notifications'),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _showBatteryHelp,
                        icon: Icon(
                          Icons.battery_saver_rounded,
                          size: 18,
                        ),
                        label: Text('Batterie'),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable:
                      NotificationService.instance.reminderStatus,
                  builder: (context, status, _) => Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.paperAlt,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 17,
                          color: AppColors.inkSoft,
                        ),
                        SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            status,
                            style: TextStyle(
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

          SizedBox(height: AppSpace.xl),
          SectionLabel('Test'),
          AppCard(
            padding: EdgeInsets.all(AppSpace.lg),
            color: AppColors.brandSoft,
            shadow: [],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                SizedBox(height: 8),
                Text(
                  'Le test doit lancer une vraie sonnerie en boucle avec l’écran d’alarme. Elle ne s’arrête que lorsque vous appuyez sur Arrêter.',
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 11.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _testAlarm(appState),
                    icon: Icon(Icons.alarm_rounded),
                    label: Text('Lancer le test'),
                  ),
                ),
                SizedBox(height: 9),
                Text(
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
                  SizedBox(width: 9),
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
        SizedBox(width: 9),
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
              SizedBox(height: 2),
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
      padding: EdgeInsets.only(bottom: 9),
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
          SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 3),
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

class _AppearanceChoice extends StatelessWidget {
  final String label;
  final String subtitle;
  final String value;
  final Color swatch;
  final bool selected;
  final VoidCallback? onTap;

  const _AppearanceChoice({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.swatch,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selectedBorder =
        value == 'white' ? AppColors.inkSoft : swatch;

    return Material(
      color: selected ? swatch.withOpacity(0.16) : AppColors.paperAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? selectedBorder : AppColors.line,
              width: selected ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: swatch,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: value == 'white'
                        ? Color(0xFFCBD6D0)
                        : swatch,
                    width: 1.2,
                  ),
                ),
              ),
              SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 19,
                  color: AppColors.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ApplicationSettingsScreen extends StatelessWidget {
  const ApplicationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    Widget choice({
      required String label,
      required String subtitle,
      required String value,
      required Color swatch,
    }) {
      return _AppearanceChoice(
        label: label,
        subtitle: subtitle,
        value: value,
        swatch: swatch,
        selected: appState.appearanceTheme == value,
        onTap: () {
          appState.setAppearanceTheme(value);
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle('Réglages de l’application'),
      ),
      body: ListView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          34,
        ),
        children: [
          SectionLabel('Thème de l’application'),
          AppCard(
            padding: EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.palette_rounded,
                        color: AppColors.brand,
                        size: 25,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Choisissez l’apparence générale de GardeFlow. Le vert reste le thème par défaut.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.inkSoft,
                              height: 1.4,
                            ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: AppSpace.lg),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 10) / 2;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Vert',
                            subtitle: 'Par défaut',
                            value: 'green',
                            swatch: Color(0xFF138A55),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Rouge',
                            subtitle: 'Rouge profond',
                            value: 'red',
                            swatch: Color(0xFFD94A43),
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Blanc',
                            subtitle: 'Ancien mode clair',
                            value: 'white',
                            swatch: Colors.white,
                          ),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: choice(
                            label: 'Noir',
                            subtitle: 'Mode sombre',
                            value: 'black',
                            swatch: Color(0xFF101311),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: 34),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 280,
                  height: 126,
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Image.asset(
                    'assets/branding/elghali_signature.webp',
                    width: 260,
                    height: 112,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    gaplessPlayback: true,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Elghali Production © 2026',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.25,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Version 11.6.66',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.inkFaint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
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

