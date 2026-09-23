import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/intern_promotions.dart';
import '../models/app_user.dart';
import '../models/leave_request.dart';
import '../models/planning_entry.dart';
import '../models/planning_month.dart';
import '../models/shift_type.dart';
import '../state/app_state.dart';
import '../services/push_notification_service.dart';
import '../services/supabase_backend_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'admin_screen.dart';
import 'announcements_screen.dart';
import 'astreinte_screen.dart';
import 'directory_screen.dart';
import 'exchange_request_sheet.dart';
import 'junior_oncall_screen.dart';
import 'notifications_screen.dart';
import 'official_planning_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import 'senior_oncall_screen.dart';
import 'daily_news_section.dart';

/// Coque principale V11.6.18.
///
/// Les quatre espaces principaux restent montés dans un IndexedStack afin de
/// conserver leur état. Le bouton + est une action et non un onglet.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final me = appState.currentUser;

    if (me != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && appState.currentUser != null) {
          PushNotificationService.instance.navigationReady(
            isAdmin: appState.currentUser!.role == UserRole.admin,
          );
        }
      });
    }

    if (me == null) {
      return Scaffold(
        backgroundColor: AppColors.paper,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      extendBody: false,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _GlobalTopBar(
              title: ['Accueil', 'Planning', 'Annuaire', 'Astreintes'][_tab],
              appState: appState,
              onNotifications: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NotificationsScreen()),
              ),
              onAccount: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ProfileScreen()),
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _DashboardView(
                    appState: appState,
                    onOpenPlanning: () => setState(() => _tab = 1),
                    onOpenDirectory: () => setState(() => _tab = 2),
                    onOpenProfile: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProfileScreen()),
                    ),
                  ),
                  _PlanningView(appState: appState),
                  DirectoryScreen(embedded: true),
                  _AstreintesHubView(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _MainBottomBar(
        selectedIndex: _tab,
        onSelected: (value) => setState(() => _tab = value),
        onReminders: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SettingsScreen(reminderFocus: true),
          ),
        ),
      ),
    );
  }

  Future<void> _showQuickAdd(BuildContext context, AppState appState) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QuickAddGuardSheet(appState: appState),
    );
    if (!mounted || result != true) return;
    setState(() => _tab = 1);
  }
}

class _GlobalTopBar extends StatelessWidget {
  final String title;
  final AppState appState;
  final VoidCallback onNotifications;
  final VoidCallback onAccount;

  const _GlobalTopBar({
    required this.title,
    required this.appState,
    required this.onNotifications,
    required this.onAccount,
  });

  @override
  Widget build(BuildContext context) {
    final user = appState.currentUser;
    if (user == null) return const SizedBox.shrink();

    final badge = appState.totalBadgeCount;
    final rawInitial = user.nom.trim();
    final initial = rawInitial.isEmpty
        ? 'D'
        : rawInitial.substring(0, 1).toUpperCase();

    return Container(
      height: 58,
      padding: EdgeInsets.fromLTRB(16, 7, 13, 6),
      decoration: BoxDecoration(
        color: AppColors.paper,
        border: Border(
          bottom: BorderSide(color: AppColors.line.withOpacity(0.55)),
        ),
      ),
      child: Row(
        children: [
          GardeFlowLogo(size: 38),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
                letterSpacing: -0.35,
              ),
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(13),
                child: InkWell(
                  onTap: onNotifications,
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.notifications_none_rounded,
                      color: AppColors.ink,
                      size: 21,
                    ),
                  ),
                ),
              ),
              if (badge > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    constraints: BoxConstraints(minWidth: 18, minHeight: 18),
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.paper, width: 2),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(width: 9),
          Tooltip(
            message: 'Mon compte',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAccount,
                customBorder: CircleBorder(),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.brandDark, AppColors.brand],
                    ),
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brand.withOpacity(0.16),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AstreintesHubView extends StatefulWidget {
  const _AstreintesHubView();

  @override
  State<_AstreintesHubView> createState() => _AstreintesHubViewState();
}

class _AstreintesHubViewState extends State<_AstreintesHubView> {
  bool _showSenior = false;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.paper,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: _AstreinteModeSwitch(
              showSenior: _showSenior,
              onChanged: (senior) {
                if (senior == _showSenior) return;
                setState(() => _showSenior = senior);
              },
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _showSenior ? 0 : 1,
              children: const [
                SeniorOnCallScreen(embedded: true),
                JuniorOnCallScreen(embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AstreinteModeSwitch extends StatelessWidget {
  final bool showSenior;
  final ValueChanged<bool> onChanged;

  const _AstreinteModeSwitch({
    required this.showSenior,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AstreinteModeButton(
              label: 'Juniors',
              icon: Icons.calendar_view_week_rounded,
              selected: !showSenior,
              onTap: () => onChanged(false),
            ),
          ),
          SizedBox(width: 5),
          Expanded(
            child: _AstreinteModeButton(
              label: 'Séniors',
              icon: Icons.calendar_month_rounded,
              selected: showSenior,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _AstreinteModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _AstreinteModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.brand.withOpacity(0.18),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
              SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.inkSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AstreinteFeatureCard extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final String trailingLabel;
  final VoidCallback onTap;

  const _AstreinteFeatureCard({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.trailingLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Ink(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(0.06),
                blurRadius: 20,
                offset: Offset(0, 9),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: accent, size: 27),
                  ),
                  Spacer(),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.paper,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              Text(
                eyebrow,
                style: TextStyle(
                  color: accent,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              SizedBox(height: 5),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.35,
                ),
              ),
              SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.touch_app_outlined, size: 16, color: accent),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      trailingLabel,
                      style: TextStyle(
                        color: accent,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  final AppState appState;
  final VoidCallback onOpenPlanning;
  final VoidCallback onOpenDirectory;
  final VoidCallback onOpenProfile;

  const _DashboardView({
    required this.appState,
    required this.onOpenPlanning,
    required this.onOpenDirectory,
    required this.onOpenProfile,
  });

  List<PlanningEntry> _futureGuards(AppUser me) {
    final entries =
        appState.planning
            .where(
              (entry) =>
                  (entry.ownerId == me.id || entry.ownerPhone == me.phone) &&
                  entry.shiftId != 'conge' &&
                  appState.isPlanningEntryApproved(entry) &&
                  !appState.guardHasStarted(entry),
            )
            .toList()
          ..sort((a, b) {
            final ad = DateTime.parse(a.dateStr);
            final bd = DateTime.parse(b.dateStr);
            final cmp = ad.compareTo(bd);
            if (cmp != 0) return cmp;
            final ashift = ShiftCatalog.byId(a.shiftId);
            final bshift = ShiftCatalog.byId(b.shiftId);
            return (ashift.start ?? '').compareTo(bshift.start ?? '');
          });
    return entries;
  }

  int _guardsThisMonth(AppUser me, DateTime now) {
    return appState.planning.where((entry) {
      if (entry.ownerId != me.id && entry.ownerPhone != me.phone) return false;
      if (entry.shiftId == 'conge') return false;
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null) return false;
      return date.year == now.year && date.month == now.month;
    }).length;
  }

  int _guardsThisMonthByCategory(
    AppUser me,
    DateTime now, {
    required bool urgence,
  }) {
    return appState.planning.where((entry) {
      if (entry.ownerId != me.id && entry.ownerPhone != me.phone) return false;
      if (entry.shiftId == 'conge') return false;
      final date = DateTime.tryParse(entry.dateStr);
      if (date == null || date.year != now.year || date.month != now.month)
        return false;
      final id = entry.shiftId.toLowerCase();
      final isUrgence = id.contains('urg');
      return urgence ? isUrgence : !isUrgence;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final me = appState.currentUser;
    if (me == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final future = _futureGuards(me);
    final next = future.isEmpty ? null : future.first;
    final now = DateTime.now();
    final hour = now.hour;
    final isNight = hour >= 18 || hour < 6;
    final greeting = isNight ? 'Bonsoir' : 'Bonjour';
    final monthlyCount = _guardsThisMonth(me, now);
    final urgenceMonthlyCount = _guardsThisMonthByCategory(
      me,
      now,
      urgence: true,
    );
    final serviceMonthlyCount = _guardsThisMonthByCategory(
      me,
      now,
      urgence: false,
    );

    final rawDate = DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(now);
    final dateLabel = rawDate.isEmpty
        ? ''
        : rawDate[0].toUpperCase() + rawDate.substring(1);
    final timeLabel = DateFormat('HH:mm').format(now);

    final heroColors = isNight
        ? const [Color(0xFF071426), Color(0xFF123D70)]
        : const [Color(0xFF55C2FF), Color(0xFF087FE8)];

    return ListView(
      physics: BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(18, 22, 18, 32),
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(22, 24, 22, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: heroColors,
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withOpacity(isNight ? 0.12 : 0.20),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -8,
                top: -14,
                child: Icon(
                  isNight ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                  size: 104,
                  color: Colors.white.withOpacity(0.12),
                ),
              ),
              Positioned(
                right: 18,
                bottom: -34,
                child: Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.055),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting Dr ${me.nom}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 30,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.7,
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        isNight
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        color: Colors.white.withOpacity(0.86),
                        size: 18,
                      ),
                      SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'On est le $dateLabel, il est $timeLabel',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.90),
                            fontSize: 13.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 17),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.13),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.14)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_month_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 7),
                            Text(
                              '$monthlyCount garde${monthlyCount > 1 ? 's' : ''} au total ce mois',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _MonthlyGuardChip(
                              label: 'Urgences',
                              value: urgenceMonthlyCount,
                            ),
                            _MonthlyGuardChip(
                              label: 'Service',
                              value: serviceMonthlyCount,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 24),
        Text(
          'Prochaine garde à venir',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontFamily: 'SpaceGrotesk',
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
        SizedBox(height: 6),
        Text(
          next == null
              ? 'Aucune garde validée à venir pour le moment.'
              : 'Voici votre prochaine garde programmée.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.inkSoft, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 14),
        _NextGuardCard(entry: next, onTap: onOpenPlanning),
        SizedBox(height: 14),
        Center(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.brandBright, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Actualités plus bas',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(width: 6),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.brandBright,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 14),
        DailyNewsSection(),
      ],
    );
  }
}

class _MonthlyGuardChip extends StatelessWidget {
  final String label;
  final int value;
  const _MonthlyGuardChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.13),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: Colors.white.withOpacity(0.13)),
    ),
    child: Text(
      '$label · $value',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class _BadgeCount extends StatelessWidget {
  final int value;
  const _BadgeCount({required this.value});

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minWidth: 19, minHeight: 19),
    alignment: Alignment.center,
    padding: EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: AppColors.danger,
      borderRadius: AppRadius.pillR,
      border: Border.all(color: AppColors.paper, width: 2),
    ),
    child: Text(
      value > 99 ? '99+' : '$value',
      style: TextStyle(
        color: Colors.white,
        fontSize: 8.5,
        fontWeight: FontWeight.w900,
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color tint;

  const _MetricCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.fromLTRB(12, 12, 10, 11),
    shadow: [],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: tint, size: 19),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9.8,
            fontWeight: FontWeight.w700,
            color: AppColors.inkSoft,
          ),
        ),
      ],
    ),
  );
}

class _NextGuardCard extends StatelessWidget {
  final PlanningEntry? entry;
  final VoidCallback onTap;

  const _NextGuardCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (entry == null) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: AppColors.line),
          boxShadow: AppShadow.low,
        ),
        child: Row(
          children: [
            Icon(
              Icons.event_available_rounded,
              color: AppColors.brand,
              size: 28,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Aucune garde à venir.',
                style: TextStyle(
                  color: AppColors.inkSoft,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final current = entry!;
    final shift = ShiftCatalog.byId(current.shiftId);
    final shiftId = shift.id.toLowerCase();
    final shiftLabel = shift.label.trim();

    final isUrgence =
        shiftId.startsWith('urg-') ||
        shiftId.contains('urgence') ||
        shiftLabel.toLowerCase().contains('urgence');
    final is24h =
        shiftId.contains('24h') ||
        shiftId.contains('24-h') ||
        shiftLabel.toLowerCase().contains('24h');
    final isNight =
        !is24h &&
        (shiftId.contains('nuit') || shiftLabel.toLowerCase().contains('nuit'));

    final category = isUrgence ? 'URGENCES' : 'SERVICE';
    final period = is24h
        ? '24H'
        : isNight
        ? 'NUIT'
        : 'JOUR';

    final date = DateTime.tryParse(current.dateStr);
    final dateLabel = date == null
        ? current.dateStr
        : DateFormat('EEE d MMMM', 'fr_FR').format(date);

    final timeLabel = is24h
        ? '08:00 → 08:00'
        : isNight
        ? '20:00 → 08:00'
        : '08:00 → 20:00';

    final guardTitle = shiftLabel.isEmpty
        ? 'Garde de \${period.toLowerCase()}'
        : shiftLabel;

    final colors = is24h
        ? const [
            Color(0xFF60CAFF),
            Color(0xFF2392EA),
            Color(0xFF173E72),
            Color(0xFF071426),
          ]
        : isNight
        ? const [Color(0xFF071426), Color(0xFF123D70)]
        : const [Color(0xFF62CBFF), Color(0xFF168DE9)];

    final stops = is24h ? const [0.0, 0.44, 0.58, 1.0] : null;

    final mainIcon = is24h
        ? Icons.brightness_6_rounded
        : isNight
        ? Icons.nightlight_round
        : Icons.wb_sunny_rounded;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
              stops: stops,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: colors.last.withOpacity(0.24),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Stack(
              children: [
                Positioned(
                  right: -12,
                  top: -16,
                  child: Icon(
                    is24h
                        ? Icons.brightness_6_rounded
                        : isNight
                        ? Icons.nightlight_round
                        : Icons.wb_sunny_rounded,
                    size: 102,
                    color: Colors.white.withOpacity(0.12),
                  ),
                ),
                if (isNight || is24h) ...[
                  const Positioned(
                    right: 86,
                    top: 20,
                    child: Icon(
                      Icons.star_rounded,
                      size: 12,
                      color: Colors.white54,
                    ),
                  ),
                  const Positioned(
                    right: 54,
                    top: 64,
                    child: Icon(
                      Icons.star_rounded,
                      size: 8,
                      color: Colors.white38,
                    ),
                  ),
                  const Positioned(
                    right: 126,
                    top: 82,
                    child: Icon(
                      Icons.star_rounded,
                      size: 7,
                      color: Colors.white38,
                    ),
                  ),
                ],
                Positioned(
                  right: -28,
                  bottom: -46,
                  child: Container(
                    width: 138,
                    height: 138,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.07),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 17, 15, 17),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(19),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                          ),
                        ),
                        child: Icon(mainIcon, color: Colors.white, size: 31),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PROCHAINE GARDE',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.82),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.75,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$category • $period',
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'SpaceGrotesk',
                                fontSize: 22,
                                height: 1.08,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              guardTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.92),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 13),
                            _NextGuardInfoLine(
                              icon: Icons.calendar_month_rounded,
                              text: dateLabel,
                            ),
                            const SizedBox(height: 6),
                            _NextGuardInfoLine(
                              icon: Icons.schedule_rounded,
                              text: timeLabel,
                            ),
                            const SizedBox(height: 6),
                            _NextGuardInfoLine(
                              icon: isUrgence
                                  ? Icons.emergency_rounded
                                  : Icons.medical_services_rounded,
                              text: isUrgence
                                  ? 'Garde aux urgences'
                                  : 'Garde de service',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(top: 42),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white.withOpacity(0.90),
                          size: 29,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextGuardInfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _NextGuardInfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.90), size: 16),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.94),
              fontSize: 12.5,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _DashboardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;

  const _DashboardAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgR,
        child: AppCard(
          padding: const EdgeInsets.all(14),
          shadow: AppShadow.low,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tint.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: tint, size: 23),
              ),
              const Spacer(),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceShortcut extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color tint;
  final VoidCallback onTap;

  const _ServiceShortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: AppRadius.lgR,
      child: AppCard(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        shadow: [],
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: tint.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: tint, size: 22),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
          ],
        ),
      ),
    ),
  );
}

class _PlanningView extends StatelessWidget {
  final AppState appState;

  const _PlanningView({required this.appState});

  @override
  Widget build(BuildContext context) {
    final promotionLabel = InternPromotions.labelFor(
      appState.currentUser,
      firstYearPromotion: appState.currentFirstYearPromotion,
    );
    final now = DateTime.now();
    final visibleMonth = appState.visibleMonth;
    final visibleMonthStart = DateTime(
      visibleMonth.year,
      visibleMonth.month,
      1,
    );
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final isPastMonth = visibleMonthStart.isBefore(currentMonthStart);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Row(
            children: [
              Expanded(
                flex: 10,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OfficialPlanningScreen(),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(999),
                    child: Ink(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.line),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navy.withOpacity(0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 17,
                            color: AppColors.urg24h,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Planning officiel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.ink,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (promotionLabel != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  flex: 11,
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: AppColors.brandBright,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.school_rounded,
                          size: 16,
                          color: AppColors.brandBright,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            promotionLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 10.8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              const _AnnouncementsCompactButton(),
            ],
          ),
        ),
        _MonthBar(appState: appState),
        _WeekdaysRow(),
        SizedBox(height: 2),
        Expanded(child: _CalendarGrid()),
        if (!isPastMonth)
          _ShiftTray(
            enabled: appState.canEditMyPlanningMonth(appState.visibleMonth),
          ),
      ],
    );
  }
}

class _AnnouncementsCompactButton extends StatefulWidget {
  const _AnnouncementsCompactButton();

  @override
  State<_AnnouncementsCompactButton> createState() =>
      _AnnouncementsCompactButtonState();
}

class _AnnouncementsCompactButtonState
    extends State<_AnnouncementsCompactButton> {
  StreamSubscription? _realtime;
  int _newCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    final backend = SupabaseBackendService.instance;
    if (backend.enabled) {
      _realtime = backend.client
          .from('public_announcements')
          .stream(primaryKey: ['id'])
          .listen((_) => _refresh(), onError: (_) {});
    }
  }

  @override
  void dispose() {
    _realtime?.cancel();
    super.dispose();
  }

  String? _seenKey() {
    final userId = context.read<AppState>().currentUser?.id;
    if (userId == null || userId.isEmpty) return null;
    return 'guardeflow_announcements_seen_$userId';
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final backend = SupabaseBackendService.instance;
    final key = _seenKey();
    if (!backend.enabled || key == null) {
      if (mounted && _newCount != 0) setState(() => _newCount = 0);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenRaw = prefs.getString(key);
      final seenAt = seenRaw == null ? null : DateTime.tryParse(seenRaw);
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final rows = await backend.client
          .from('public_announcements')
          .select('created_at')
          .isFilter('closed_at', null)
          .gte('date_str', today)
          .order('created_at', ascending: false)
          .limit(150);
      var count = 0;
      for (final raw in rows as List) {
        final row = Map<String, dynamic>.from(raw as Map);
        final createdAt = DateTime.tryParse('${row['created_at']}');
        if (createdAt != null &&
            (seenAt == null || createdAt.isAfter(seenAt))) {
          count++;
        }
      }
      if (!mounted || count == _newCount) return;
      setState(() => _newCount = count);
    } catch (_) {
      // Le badge ne doit jamais bloquer l'ouverture du planning.
    }
  }

  Future<void> _openAnnouncements() async {
    final key = _seenKey();
    if (key != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, DateTime.now().toUtc().toIso8601String());
    }
    if (!mounted) return;
    setState(() => _newCount = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnnouncementsScreen()),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Annonces',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openAnnouncements,
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.navy.withOpacity(0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.campaign_rounded,
                  size: 20,
                  color: AppColors.brandBright,
                ),
              ),
            ),
          ),
          if (_newCount > 0)
            Positioned(
              right: -5,
              top: -5,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.paper, width: 2),
                ),
                child: Text(
                  _newCount > 99 ? '99+' : '$_newCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlanningShortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _PlanningShortcut({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: AppColors.navy.withOpacity(0.035),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainBottomBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onReminders;

  const _MainBottomBar({
    required this.selectedIndex,
    required this.onSelected,
    required this.onReminders,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    Widget item(int index, IconData icon, IconData selectedIcon, String label) {
      final selected = selectedIndex == index;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onSelected(index),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: EdgeInsets.fromLTRB(2, 6, 2, 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: Duration(milliseconds: 180),
                    width: 38,
                    height: 28,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.brandSoft
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      selected ? selectedIcon : icon,
                      color: selected ? AppColors.brand : AppColors.inkSoft,
                      size: 21,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.05,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.brand : AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 72 + bottomInset,
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.08),
            blurRadius: 18,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: 72,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  item(0, Icons.home_outlined, Icons.home_rounded, 'Accueil'),
                  item(
                    1,
                    Icons.calendar_month_outlined,
                    Icons.calendar_month_rounded,
                    'Planning',
                  ),
                  SizedBox(width: 74),
                  item(
                    2,
                    Icons.badge_outlined,
                    Icons.badge_rounded,
                    'Annuaire',
                  ),
                  item(
                    3,
                    Icons.medical_services_outlined,
                    Icons.medical_services_rounded,
                    'Astreintes',
                  ),
                ],
              ),
              Positioned(
                top: -18,
                child: Tooltip(
                  message: 'Réglages des rappels de garde',
                  child: Material(
                    color: Colors.transparent,
                    shape: CircleBorder(),
                    child: InkWell(
                      onTap: onReminders,
                      customBorder: CircleBorder(),
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.brandDark, AppColors.brand],
                          ),
                          border: Border.all(color: AppColors.card, width: 4),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brand.withOpacity(0.30),
                              blurRadius: 15,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.white,
                          size: 27,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 42,
                child: Text(
                  'Rappels',
                  style: TextStyle(
                    color: AppColors.brandDark,
                    fontSize: 8.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAddGuardSheet extends StatefulWidget {
  final AppState appState;
  const _QuickAddGuardSheet({required this.appState});

  @override
  State<_QuickAddGuardSheet> createState() => _QuickAddGuardSheetState();
}

class _QuickAddGuardSheetState extends State<_QuickAddGuardSheet> {
  DateTime _date = DateTime.now();
  ShiftType _shift = ShiftCatalog.serviceJour;
  bool _saving = false;

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(DateTime(now.year, now.month, now.day))
          ? now
          : _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2, 12, 31),
      locale: const Locale('fr', 'FR'),
    );
    if (chosen != null && mounted) setState(() => _date = chosen);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final error = await widget.appState.placeShift(
      AppState.dateKey(_date),
      _shift.id,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ajouter une garde',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 4),
            Text(
              'Même logique que le calendrier : choisissez une date et une tuile.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: 16),
            InkWell(
              onTap: _chooseDate,
              borderRadius: AppRadius.mdR,
              child: AppCard(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shadow: [],
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      color: AppColors.brand,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(_date),
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.inkFaint,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Type de garde',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final shift in ShiftCatalog.all)
                  ChoiceChip(
                    selected: _shift.id == shift.id,
                    showCheckmark: false,
                    avatar: Icon(
                      shift.icon,
                      size: 17,
                      color: _shift.id == shift.id
                          ? Colors.white
                          : shift.textColor,
                    ),
                    label: Text(
                      shift.id == 'conge'
                          ? 'Congé'
                          : '${shift.id.startsWith('urg-') ? 'Urg.' : 'Service'} · ${shift.label}',
                    ),
                    onSelected: (_) => setState(() => _shift = shift),
                  ),
              ],
            ),
            SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(Icons.add_rounded),
                label: Text(_saving ? 'Enregistrement…' : 'Ajouter la garde'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =======================================================================
// BARRE SUPÉRIEURE — identité, statut du jour, accès rapides.
// =======================================================================

class _TopBar extends StatefulWidget {
  final AppState appState;
  final AppUser user;
  const _TopBar({required this.appState, required this.user});

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  late DateTime _now;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      if (now.minute != _now.minute ||
          now.day != _now.day ||
          now.hour != _now.hour) {
        setState(() => _now = now);
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hour = _now.hour;
    final greeting = hour >= 5 && hour < 18 ? 'Bonjour' : 'Bonsoir';
    final entry = widget.appState.myEntryForDate(AppState.dateKey(_now));
    final status = _statusFor(entry, widget.appState);
    final isAdmin = widget.user.role == UserRole.admin;
    final badge = widget.appState.totalBadgeCount;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.xs,
      ),
      child: Column(
        children: [
          Row(
            children: [
              GardeFlowLogo(size: 44),
              SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'GardeFlow',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '$greeting Dr ${widget.user.nom}',
                            style: Theme.of(context).textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isAdmin) ...[
                          SizedBox(width: 6),
                          Pill(
                            text: 'ADMIN',
                            background: AppColors.ink,
                            foreground: Colors.white,
                            fontSize: 9,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 1),
                    Text(
                      status.title,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppSpace.sm),
              _BellButton(
                badge: badge,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => NotificationsScreen()),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpace.sm),
          _NavRail(isAdmin: isAdmin),
        ],
      ),
    );
  }

  _TodayStatus _statusFor(PlanningEntry? entry, AppState appState) {
    if (entry == null) {
      return _TodayStatus(
        title: 'Rien de prévu aujourd’hui',
        icon: Icons.event_available_rounded,
        background: AppColors.paperAlt,
        foreground: AppColors.ink,
      );
    }
    final shift = ShiftCatalog.byId(entry.shiftId);
    if (shift.id == 'conge') {
      final leave = appState.leaveRequestForEntry(entry);
      final pending = leave?.status == LeaveRequestStatus.pendingAdmin;
      return _TodayStatus(
        title: pending
            ? 'Congé en attente de validation'
            : 'Vous êtes en congé aujourd’hui',
        icon: pending
            ? Icons.hourglass_top_rounded
            : Icons.beach_access_rounded,
        background: shift.color,
        foreground: shift.textColor,
      );
    }
    final isUrgence = shift.id.startsWith('urg-');
    final location = isUrgence ? 'Urgences' : 'Service';
    final schedule = shift.start == null
        ? ''
        : ' · ${shift.start} → ${shift.end}';
    return _TodayStatus(
      title: '$location · ${shift.label}$schedule',
      icon: shift.icon,
      background: shift.color,
      foreground: shift.textColor,
    );
  }
}

class _TodayStatus {
  final String title;
  final IconData icon;
  final Color background;
  final Color foreground;
  const _TodayStatus({
    required this.title,
    required this.icon,
    required this.background,
    required this.foreground,
  });
}

class _BellButton extends StatelessWidget {
  final int badge;
  final VoidCallback onTap;
  const _BellButton({required this.badge, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        SoftIconButton(
          icon: Icons.notifications_rounded,
          onTap: onTap,
          tooltip: 'Notifications',
        ),
        if (badge > 0)
          Positioned(
            top: -3,
            right: -3,
            child: Container(
              constraints: BoxConstraints(minWidth: 18, minHeight: 18),
              alignment: Alignment.center,
              padding: EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.urgNuit,
                borderRadius: AppRadius.pillR,
                border: Border.all(color: AppColors.paper, width: 2),
              ),
              child: Text(
                badge > 99 ? '99+' : '$badge',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Rangée d'accès rapides — remplace les grandes cartes d'origine par des
/// puces compactes icône + libellé, pour libérer de la hauteur au profit
/// du calendrier tout en gardant exactement les mêmes destinations.
class _NavRail extends StatefulWidget {
  final bool isAdmin;
  const _NavRail({required this.isAdmin});

  @override
  State<_NavRail> createState() => _NavRailState();
}

class _NavRailState extends State<_NavRail> {
  final ScrollController _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollState());
  }

  @override
  void didUpdateWidget(covariant _NavRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncScrollState());
  }

  @override
  void dispose() {
    _controller.removeListener(_syncScrollState);
    _controller.dispose();
    super.dispose();
  }

  void _syncScrollState() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final left = position.pixels > 4;
    final right = position.pixels < position.maxScrollExtent - 4;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  Future<void> _scrollBy(double delta) async {
    if (!_controller.hasClients) return;
    final target = (_controller.offset + delta).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    await _controller.animateTo(
      target.toDouble(),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <_NavItem>[
      _NavItem(
        Icons.picture_as_pdf_rounded,
        'Planning de Garde Officiel',
        AppColors.urg24h,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OfficialPlanningScreen()),
        ),
      ),
      _NavItem(
        Icons.badge_rounded,
        'Annuaire',
        AppColors.catService,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DirectoryScreen()),
        ),
      ),
      _NavItem(
        Icons.medical_services_rounded,
        'Séniors d’astreinte',
        AppColors.conge,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SeniorOnCallScreen()),
        ),
      ),
      _NavItem(
        Icons.groups_2_rounded,
        'Juniors d’astreinte',
        AppColors.service24h,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => JuniorOnCallScreen()),
        ),
      ),
      _NavItem(
        Icons.tune_rounded,
        'Réglages',
        AppColors.inkSoft,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SettingsScreen()),
        ),
      ),
      if (widget.isAdmin)
        _NavItem(
          Icons.admin_panel_settings_rounded,
          'Vue Admin',
          AppColors.ink,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AdminScreen()),
          ),
        ),
    ];

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          _ScrollHintButton(
            icon: Icons.chevron_left_rounded,
            enabled: _canScrollLeft,
            tooltip: 'Voir les accès précédents',
            onTap: () => _scrollBy(-220),
          ),
          Expanded(
            child: ClipRect(
              child: ListView.separated(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                physics: BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                itemCount: items.length,
                separatorBuilder: (_, __) => SizedBox(width: 8),
                itemBuilder: (context, i) => _NavChip(item: items[i]),
              ),
            ),
          ),
          _ScrollHintButton(
            icon: Icons.chevron_right_rounded,
            enabled: _canScrollRight,
            tooltip: 'Voir les autres accès',
            onTap: () => _scrollBy(220),
          ),
        ],
      ),
    );
  }
}

class _ScrollHintButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  const _ScrollHintButton({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: Duration(milliseconds: 160),
      opacity: enabled ? 1 : 0.18,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: AppRadius.pillR,
          child: SizedBox(
            width: 34,
            height: 46,
            child: Icon(
              icon,
              size: 22,
              color: enabled ? AppColors.ink : AppColors.inkFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;
  _NavItem(this.icon, this.label, this.accent, this.onTap);
}

class _NavChip extends StatelessWidget {
  final _NavItem item;
  const _NavChip({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: AppRadius.mdR,
        onTap: item.onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.mdR,
            border: Border.all(color: AppColors.line),
            boxShadow: [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 27,
                height: 27,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: item.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(item.icon, size: 16, color: item.accent),
              ),
              SizedBox(width: 7),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =======================================================================
// BARRE DE MOIS — navigation + statut de validation, en une seule ligne.
// =======================================================================

class _MonthBar extends StatelessWidget {
  final AppState appState;
  const _MonthBar({required this.appState});

  @override
  Widget build(BuildContext context) {
    final month = appState.visibleMonth;
    final record = appState.myPlanningMonth(month);
    final status = record?.status ?? PlanningMonthStatus.draft;
    final monthLabel = _capitalize(DateFormat.yMMMM('fr_FR').format(month));
    final now = DateTime.now();
    final isPastMonth = DateTime(
      month.year,
      month.month,
      1,
    ).isBefore(DateTime(now.year, now.month, 1));

    String statusLabel;
    IconData statusIcon;
    Color statusBg;
    Color statusFg;
    String? reopenReason;

    switch (status) {
      case PlanningMonthStatus.approved:
        statusLabel = 'Validé';
        statusIcon = Icons.verified_rounded;
        statusBg = AppColors.success;
        statusFg = Colors.white;
        break;
      case PlanningMonthStatus.draft:
      case PlanningMonthStatus.submitted:
      case PlanningMonthStatus.rejected:
        reopenReason = record?.rejectionReason?.trim();
        final reopened = reopenReason != null && reopenReason.isNotEmpty;
        statusLabel = reopened ? 'Rouvert' : 'En préparation';
        statusIcon = reopened
            ? Icons.lock_open_rounded
            : Icons.edit_calendar_rounded;
        statusBg = reopened ? Color(0xFFB3261E) : AppColors.paperAlt;
        statusFg = reopened ? Colors.white : AppColors.ink;
        break;
    }

    final canSubmit = !isPastMonth && status != PlanningMonthStatus.approved;

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 42,
            child: Row(
              children: [
                _MonthArrowButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: appState.previousMonth,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      monthLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'SpaceGrotesk',
                        color: AppColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.45,
                      ),
                    ),
                  ),
                ),
                _MonthArrowButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: appState.nextMonth,
                ),
              ],
            ),
          ),
          if (!isPastMonth) ...[
            SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => _showMonthInfo(context, status, reopenReason),
                  child: Container(
                    height: 30,
                    padding: EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 15, color: statusFg),
                        SizedBox(width: 5),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            color: statusFg,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (canSubmit) ...[
                  SizedBox(width: 8),
                  _ValidateButton(appState: appState, month: month),
                ],
              ],
            ),
            if (canSubmit) ...[
              SizedBox(height: 5),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Validation automatique : 7 jours après la publication ou le remplacement du planning officiel.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.inkSoft,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _showMonthInfo(
    BuildContext context,
    PlanningMonthStatus status,
    String? reopenReason,
  ) {
    late String title;
    late String detail;
    switch (status) {
      case PlanningMonthStatus.approved:
        title = 'Calendrier validé définitivement';
        detail = 'Le mois est verrouillé. Un administrateur peut supprimer une garde validée ou rouvrir le calendrier pour correction.';
        break;
      case PlanningMonthStatus.draft:
      case PlanningMonthStatus.submitted:
      case PlanningMonthStatus.rejected:
        if (reopenReason != null && reopenReason.isNotEmpty) {
          title = 'Calendrier rouvert par un administrateur';
          detail =
              'Motif : $reopenReason. Modifiez vos tuiles puis validez à nouveau le mois. Sans validation manuelle, le calendrier sera automatiquement validé 7 jours après la publication ou le remplacement du planning officiel.';
        } else {
          title = 'Calendrier en préparation';
          detail = 'Placez vos tuiles Service, Urgences et Congé puis validez définitivement le mois. Sans validation manuelle, le calendrier sera automatiquement validé 7 jours après la publication ou le remplacement du planning officiel.';
        }
        break;
    }
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: AppSpace.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            AppSpace.sm,
            AppSpace.xl,
            AppSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: AppSpace.sm),
              Text(detail, style: Theme.of(sheetContext).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MonthArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandSoft,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: AppColors.brand, size: 26),
        ),
      ),
    );
  }
}

class _ValidateButton extends StatelessWidget {
  final AppState appState;
  final DateTime month;
  const _ValidateButton({required this.appState, required this.month});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: FilledButton(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Valider définitivement ce calendrier ?'),
              content: const Text(
                'Après validation, vous ne pourrez plus déplacer, remplacer ni retirer vos tuiles. '
                'Seul un administrateur pourra supprimer une garde validée ou rouvrir le mois pour correction. '
                'Les tuiles Congé seront envoyées à l’administration pour approbation.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Valider définitivement'),
                ),
              ],
            ),
          );
          if (confirm != true || !context.mounted) return;
          final err = await appState.submitMyPlanningMonth(month);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err ?? 'Calendrier validé définitivement.')),
          );
        },
        child: const Text('Valider'),
      ),
    );
  }
}

// =======================================================================
// JOURS DE LA SEMAINE
// =======================================================================

class _WeekdaysRow extends StatelessWidget {
  const _WeekdaysRow();
  @override
  Widget build(BuildContext context) {
    const days = ['L', 'Ma', 'Me', 'J', 'V', 'S', 'D'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.xs,
        AppSpace.lg,
        0,
      ),
      child: Row(
        children: days
            .map(
              (d) => Expanded(
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// =======================================================================
// GRILLE DU CALENDRIER — cœur de l'écran, toujours entièrement visible.
// =======================================================================

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final month = appState.visibleMonth;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final todayKey = AppState.dateKey(DateTime.now());
    final monthStatus =
        appState.myPlanningMonth(month)?.status ?? PlanningMonthStatus.draft;
    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final viewedMonthStart = DateTime(month.year, month.month, 1);
    final isPastMonth = viewedMonthStart.isBefore(currentMonthStart);
    final monthEditable =
        !isPastMonth && appState.canEditMyPlanningMonth(month);
    final monthApproved = monthStatus == PlanningMonthStatus.approved;
    final totalCells = firstWeekday + daysInMonth;
    final rows = ((totalCells + 6) ~/ 7).clamp(5, 6);

    final cells = <Widget>[];

    for (var i = 0; i < firstWeekday; i++) {
      cells.add(
        KeyedSubtree(key: ValueKey('empty-$i'), child: const SizedBox.shrink()),
      );
    }

    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final dateStr = AppState.dateKey(date);
      final entry = appState.myEntryForDate(dateStr);
      final editable =
          monthEditable &&
          !appState.dateIsPast(dateStr) &&
          (entry == null ||
              (!entry.isDisciplinary && !appState.isApprovedLeaveEntry(entry)));
      final canExchange =
          monthApproved &&
          entry != null &&
          !entry.isDisciplinary &&
          ShiftCatalog.byId(entry.shiftId).hasSchedule &&
          !appState.guardHasStarted(entry);

      cells.add(
        KeyedSubtree(
          key: ValueKey(dateStr),
          child: _DayCell(
            day: d,
            dateStr: dateStr,
            isToday: dateStr == todayKey,
            entry: entry,
            editable: editable,
            locked: !monthEditable,
            canExchange: canExchange,
            onDrop: (shiftId) async {
              final err = await appState.placeShift(dateStr, shiftId);
              if (err != null && context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(err)));
              }
            },
            onRemove: entry == null
                ? null
                : () async {
                    final err = await appState.removeShift(entry.id);
                    if (err != null && context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(err)));
                    }
                  },
            onExchange: entry == null
                ? null
                : () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    showDragHandle: true,
                    builder: (_) =>
                        ExchangeRequestSheet(dateStr: dateStr, entry: entry),
                  ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 5),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 5.0;
          final itemWidth = (constraints.maxWidth - gap * 6) / 7;
          final itemHeight = (constraints.maxHeight - gap * (rows - 1)) / rows;
          final safeHeight = itemHeight.isFinite && itemHeight > 1
              ? itemHeight
              : 1.0;
          final aspectRatio = itemWidth / safeHeight;

          return GridView.count(
            key: ValueKey('grid-${month.year}-${month.month}'),
            crossAxisCount: 7,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
            childAspectRatio: aspectRatio,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: cells,
          );
        },
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final String dateStr;
  final bool isToday;
  final PlanningEntry? entry;
  final bool editable;
  final bool locked;
  final bool canExchange;
  final ValueChanged<String> onDrop;
  final VoidCallback? onRemove;
  final VoidCallback? onExchange;

  const _DayCell({
    required this.day,
    required this.dateStr,
    required this.isToday,
    required this.entry,
    required this.editable,
    required this.locked,
    required this.canExchange,
    required this.onDrop,
    required this.onRemove,
    required this.onExchange,
  });

  @override
  Widget build(BuildContext context) {
    final currentEntry = entry;
    final shift = currentEntry == null
        ? null
        : ShiftCatalog.byId(currentEntry.shiftId);
    final isUrgence = shift?.id.startsWith('urg-') ?? false;
    final isLeave = shift?.id == 'conge';
    final isDisciplinary = currentEntry?.isDisciplinary ?? false;

    String? groupLabel;
    String? shiftLabel;
    if (shift != null) {
      if (isLeave) {
        final leave = context.watch<AppState>().leaveRequestForEntry(
          currentEntry!,
        );
        final pending = leave?.status == LeaveRequestStatus.pendingAdmin;
        groupLabel = 'CONGÉ';
        shiftLabel = pending ? 'Attente' : 'Congé';
      } else {
        groupLabel = isUrgence ? 'URG' : 'SERV';
        shiftLabel = shift.label;
      }
    }

    return DragTarget<String>(
      onWillAcceptWithDetails: (_) => editable,
      onAcceptWithDetails: (details) => onDrop(details.data),
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty && editable;
        final background = hovering
            ? Color(0xFFDCEBFF)
            : shift?.color ?? AppColors.card;
        final foreground = shift?.textColor ?? AppColors.ink;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: canExchange ? onExchange : null,
          child: AnimatedContainer(
            duration: Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hovering || isToday
                    ? AppColors.brand
                    : shift != null
                    ? foreground.withOpacity(0.15)
                    : AppColors.line,
                width: hovering ? 2 : (isToday ? 1.8 : 1),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.navy.withOpacity(
                    shift != null ? 0.075 : 0.035,
                  ),
                  blurRadius: shift != null ? 9 : 5,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(4, 25, 4, 4),
                    child: Center(
                      child: hovering && shift == null
                          ? Icon(
                              Icons.add_rounded,
                              color: AppColors.brand,
                              size: 24,
                            )
                          : shift == null
                          ? SizedBox.shrink()
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    groupLabel!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: foreground.withOpacity(0.84),
                                      fontSize: 10.5,
                                      height: 1,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.25,
                                    ),
                                  ),
                                  SizedBox(height: 3),
                                  Text(
                                    shiftLabel!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: foreground,
                                      fontFamily: 'SpaceGrotesk',
                                      fontSize: 12,
                                      height: 1,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
                Positioned(
                  top: 5,
                  left: 5,
                  child: Container(
                    constraints: BoxConstraints(minWidth: 23, minHeight: 23),
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isToday
                          ? AppColors.brandDark
                          : shift != null
                          ? (AppColors.isDarkMode
                                ? AppColors.paperAlt.withOpacity(0.96)
                                : Colors.white.withOpacity(0.78))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$day',
                      style: TextStyle(
                        color: isToday ? Colors.white : AppColors.ink,
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                if (isDisciplinary)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Tooltip(
                      message:
                          'Garde disciplinaire · suppression admin uniquement',
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFFB42318),
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: Icon(
                            Icons.lock_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (editable && currentEntry != null && onRemove != null)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: _CalendarCellAction(
                      tooltip: 'Retirer cette garde',
                      icon: Icons.close_rounded,
                      onTap: onRemove!,
                      compact: true,
                      foreground: Color(0xFFB42318),
                      background: Color(0xFFFFE7E5),
                    ),
                  )
                else if (canExchange && onExchange != null)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: _CalendarCellAction(
                      tooltip: 'Transfert / échange',
                      icon: Icons.swap_horiz_rounded,
                      onTap: onExchange!,
                      compact: true,
                      foreground: Colors.white,
                      background: AppColors.brandDark,
                    ),
                  )
                else if (locked && currentEntry == null)
                  Positioned(
                    top: 7,
                    right: 7,
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 12,
                      color: AppColors.inkFaint,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CalendarCellAction extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;
  final Color foreground;
  final Color background;

  const _CalendarCellAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    required this.compact,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 26.0 : 31.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: CircleBorder(),
        elevation: 3,
        shadowColor: AppColors.navy.withOpacity(0.20),
        child: InkWell(
          onTap: onTap,
          customBorder: CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: compact ? 15 : 18, color: foreground),
          ),
        ),
      ),
    );
  }
}

class _ShiftChip extends StatelessWidget {
  final PlanningEntry entry;

  const _ShiftChip({required this.entry});

  @override
  Widget build(BuildContext context) {
    final shift = ShiftCatalog.byId(entry.shiftId);
    final isUrgence = shift.id.startsWith('urg-');
    final isLeave = shift.id == 'conge';
    final leave = isLeave
        ? context.watch<AppState>().leaveRequestForEntry(entry)
        : null;
    final pendingLeave = leave?.status == LeaveRequestStatus.pendingAdmin;

    final groupLabel = isLeave
        ? 'CONGÉ'
        : isUrgence
        ? 'URG'
        : 'SERV';
    final shiftLabel = isLeave
        ? (pendingLeave ? 'Attente' : 'Congé')
        : shift.label;

    return LayoutBuilder(
      builder: (context, constraints) {
        final short = constraints.maxHeight < 48;

        return Container(
          width: double.infinity,
          height: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 3, vertical: short ? 3 : 5),
          decoration: BoxDecoration(
            color: shift.color,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: shift.textColor.withOpacity(0.12),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: shift.textColor.withOpacity(0.06),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!short) ...[
                  Icon(shift.icon, size: 18, color: shift.textColor),
                  const SizedBox(height: 3),
                ],
                Text(
                  groupLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.35,
                    color: shift.textColor.withOpacity(0.84),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  shiftLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontSize: 12.5,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: shift.textColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =======================================================================
// PLATEAU DE TUILES — drag-and-drop identique, habillage modernisé.
// =======================================================================

class _ShiftTray extends StatelessWidget {
  final bool enabled;

  const _ShiftTray({required this.enabled});

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Container(
        height: 42,
        margin: EdgeInsets.fromLTRB(8, 2, 8, 5),
        padding: EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withOpacity(0.05),
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: AppColors.inkSoft,
            ),
            SizedBox(width: 7),
            Text(
              'Planning validé · tuiles verrouillées',
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 92,
      padding: EdgeInsets.fromLTRB(7, 6, 7, 7),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: AppColors.line)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withOpacity(0.08),
            blurRadius: 16,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _PlanningShiftGroup(
              title: 'SERVICE',
              icon: Icons.local_hospital_outlined,
              accent: AppColors.brand,
              shifts: [
                ShiftCatalog.serviceJour,
                ShiftCatalog.service24h,
                ShiftCatalog.serviceNuit,
              ],
            ),
          ),
          SizedBox(width: 5),
          Expanded(
            child: _PlanningShiftGroup(
              title: 'URGENCES',
              icon: Icons.emergency_rounded,
              accent: AppColors.danger,
              shifts: [
                ShiftCatalog.urgJour,
                ShiftCatalog.urg24h,
                ShiftCatalog.urgNuit,
              ],
            ),
          ),
          SizedBox(width: 5),
          SizedBox(
            width: 54,
            child: Container(
              padding: EdgeInsets.fromLTRB(4, 5, 4, 5),
              decoration: BoxDecoration(
                color: AppColors.conge.withOpacity(0.42),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: AppColors.congeText.withOpacity(0.13),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'CONGÉ',
                    maxLines: 1,
                    style: TextStyle(
                      color: AppColors.congeText,
                      fontSize: 8,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.25,
                    ),
                  ),
                  SizedBox(height: 4),
                  Expanded(
                    child: _CompactShiftTile(
                      shift: ShiftCatalog.conge,
                      enabled: true,
                      showLabel: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanningShiftGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final List<ShiftType> shifts;

  const _PlanningShiftGroup({
    required this.title,
    required this.icon,
    required this.accent,
    required this.shifts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 4, 5, 5),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.055),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: accent.withOpacity(0.18)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 15,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 10, color: accent),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 8.2,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.28,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < shifts.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: _CompactShiftTile(shift: shifts[i], enabled: true),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactShiftTile extends StatelessWidget {
  final ShiftType shift;
  final bool enabled;
  final bool showLabel;

  const _CompactShiftTile({
    required this.shift,
    required this.enabled,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      decoration: BoxDecoration(
        color: shift.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: shift.textColor.withOpacity(0.11)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(shift.icon, size: showLabel ? 14 : 19, color: shift.textColor),
            if (showLabel) ...[
              const SizedBox(height: 2),
              Text(
                shift.label,
                maxLines: 1,
                style: TextStyle(
                  color: shift.textColor,
                  fontFamily: 'SpaceGrotesk',
                  fontSize: 9.2,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Draggable<String>(
      data: shift.id,
      maxSimultaneousDrags: enabled ? 1 : 0,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 56, height: 58, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.28, child: tile),
      child: tile,
    );
  }
}

class _TrayRow extends StatelessWidget {
  final String label;
  final Color accent;
  final List<ShiftType> shifts;
  final bool enabled;

  const _TrayRow({
    required this.label,
    required this.accent,
    required this.shifts,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: AppColors.inkSoft,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        SizedBox(height: 6),
        Row(
          children: shifts
              .map(
                (shift) => Expanded(
                  child: _ShiftTile(shift: shift, enabled: enabled),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _ShiftTile extends StatelessWidget {
  final ShiftType shift;
  final bool enabled;

  const _ShiftTile({required this.shift, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: shift.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: shift.textColor.withOpacity(0.09)),
        boxShadow: [
          BoxShadow(
            color: shift.textColor.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(shift.icon, size: 20, color: shift.textColor),
          const SizedBox(height: 3),
          Text(
            shift.label,
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: shift.textColor,
            ),
          ),
        ],
      ),
    );

    return Draggable<String>(
      data: shift.id,
      maxSimultaneousDrags: enabled ? 1 : 0,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 98,
          height: 66,
          child: Transform.scale(
            scale: 1.06,
            child: DecoratedBox(
              decoration: BoxDecoration(boxShadow: AppShadow.high),
              child: tile,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.26, child: tile),
      child: tile,
    );
  }
}

class _CongeDock extends StatelessWidget {
  final ShiftType shift;
  final bool enabled;

  const _CongeDock({required this.shift, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final dock = Container(
      width: 86,
      height: 138,
      decoration: BoxDecoration(
        color: shift.color,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: shift.textColor.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: shift.textColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.30),
              shape: BoxShape.circle,
            ),
            child: Icon(shift.icon, size: 24, color: shift.textColor),
          ),
          const SizedBox(height: 8),
          Text(
            shift.label,
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: shift.textColor,
            ),
          ),
        ],
      ),
    );

    return Draggable<String>(
      data: shift.id,
      maxSimultaneousDrags: enabled ? 1 : 0,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 86,
          height: 138,
          child: Transform.scale(
            scale: 1.05,
            child: DecoratedBox(
              decoration: BoxDecoration(boxShadow: AppShadow.high),
              child: dock,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.26, child: dock),
      child: dock,
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
