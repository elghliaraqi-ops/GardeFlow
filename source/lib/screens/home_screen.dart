import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../data/hospitals.dart';
import '../models/app_user.dart';
import '../models/planning_entry.dart';
import '../models/planning_month.dart';
import '../models/shift_type.dart';
import '../services/push_notification_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import '../ui/components.dart';
import '../ui/planning_access.dart';
import '../widgets/month_navigation.dart';
import '../widgets/planning_calendar.dart';
import 'daily_news_section.dart';
import 'directory_screen.dart';
import 'more_screen.dart';
import 'notifications_screen.dart';
import 'official_planning_screen.dart';
import 'profile_screen.dart';
import 'shift_details_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.currentUser;
    if (me == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && state.currentUser != null) {
        PushNotificationService.instance.navigationReady(isAdmin: state.currentUser!.role == UserRole.admin);
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: _tab == 0 ? const Row(children: [GardeFlowLogo(size: 32), SizedBox(width: 10), Expanded(child: Text('GardeFlow', maxLines: 1, overflow: TextOverflow.ellipsis))])
            : Text(['Accueil', 'Mon planning', 'Demandes', 'Plus'][_tab]),
        actions: [
          IconButton(tooltip: 'Notifications', onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const NotificationsScreen())),
            icon: Badge.count(count: state.totalBadgeCount, isLabelVisible: state.totalBadgeCount > 0, child: const Icon(Icons.notifications_none_rounded))),
          IconButton(tooltip: 'Mon profil', onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
            icon: const Icon(Icons.account_circle_outlined)),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(top: false, bottom: false, child: IndexedStack(index: _tab, children: [
        DashboardView(onOpenPlanning: () => setState(() => _tab = 1), onOpenRequests: () => setState(() => _tab = 2)),
        const PersonalPlanningView(),
        const NotificationsScreen(embedded: true, initialIndex: 1),
        const MoreScreen(),
      ])),
      bottomNavigationBar: NavigationBar(selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Accueil'),
          const NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: 'Planning'),
          NavigationDestination(icon: Badge.count(count: state.totalBadgeCount, isLabelVisible: state.totalBadgeCount > 0, child: const Icon(Icons.inbox_outlined)), selectedIcon: const Icon(Icons.inbox_rounded), label: 'Demandes'),
          const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Plus'),
        ]),
    );
  }
}

class DashboardView extends StatefulWidget {
  final VoidCallback onOpenPlanning, onOpenRequests;
  const DashboardView({super.key, required this.onOpenPlanning, required this.onOpenRequests});
  @override
  State<DashboardView> createState() => _DashboardViewState();
}
class _DashboardViewState extends State<DashboardView> {
  Timer? _clock;
  @override
  void initState() { super.initState(); _clock = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); }); }
  @override
  void dispose() { _clock?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.currentUser;
    if (me == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final todayKey = AppState.dateKey(now);
    final own = state.planning.where((e) => e.ownerId == me.id || e.ownerPhone == me.phone).toList();
    final upcoming = own.where((e) => ShiftCatalog.byId(e.shiftId).hasSchedule && _start(e).isAfter(now)).toList()..sort((a,b) => _start(a).compareTo(_start(b)));
    final ongoing = own.where((e) => ShiftCatalog.byId(e.shiftId).hasSchedule && !_start(e).isAfter(now) && _end(e).isAfter(now)).toList()..sort((a,b) => _start(a).compareTo(_start(b)));
    final today = ongoing.isNotEmpty ? ongoing.first : state.myEntryForDate(todayKey);
    final following = upcoming.where((e) => e.id != today?.id).toList();
    final next = following.isEmpty ? null : following.first;
    final month = DateTime(now.year, now.month);
    final monthEntries = own.where((e) => e.dateStr.startsWith(DateFormat('yyyy-MM').format(month))).toList();
    final guards = monthEntries.where((e) => e.shiftId != 'conge').toList();
    final record = state.myPlanningMonth(month);
    final c = Theme.of(context).colorScheme;
    return RefreshIndicator(onRefresh: state.refreshBackend, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Text('${now.hour >= 18 || now.hour < 6 ? 'Bonsoir' : 'Bonjour'} Dr ${me.nom}', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(DateFormat('EEEE d MMMM yyyy · HH:mm', 'fr_FR').format(now), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
        const SizedBox(height: 24),
        GardeCard(entry: today, user: me, approved: today != null && state.isPlanningEntryApproved(today),
          onTap: () => AppBottomSheet.show<void>(context, builder: (_) => ShiftDetailsSheet(date: today == null ? now : DateTime.parse(today.dateStr)))),
        const SizedBox(height: 20),
        if (next != null && next.id != today?.id)
          ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event_upcoming_outlined),
            title: Text('Prochaine garde · ${DateFormat('EEE d MMM', 'fr_FR').format(DateTime.parse(next.dateStr))}'),
            subtitle: Text('${ShiftCatalog.byId(next.shiftId).label} · ${next.shiftId.startsWith('urg-') ? 'Urgences' : me.service}${state.isPlanningEntryApproved(next) ? '' : ' · provisoire'}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => AppBottomSheet.show<void>(context, builder: (_) => ShiftDetailsSheet(date: DateTime.parse(next.dateStr))))
        else if (next == null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('Aucune autre garde à venir.', style: Theme.of(context).textTheme.bodySmall)),
        Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Wrap(spacing: 20, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('${guards.length} garde${guards.length > 1 ? 's' : ''} ce mois', style: Theme.of(context).textTheme.titleMedium),
          StatusBadge(status: record?.status ?? PlanningMonthStatus.draft, reopened: record?.rejectionReason?.trim().isNotEmpty ?? false),
        ])),
        Text('${guards.where((e) => e.shiftId.startsWith('service-')).length} de service · ${guards.where((e) => e.shiftId.startsWith('urg-')).length} aux urgences', style: Theme.of(context).textTheme.bodySmall),
        if (state.totalBadgeCount > 0) Padding(padding: const EdgeInsets.only(top: 16), child: Material(color: c.primaryContainer, borderRadius: AppRadius.mdR,
          child: AppMenuItem(title: '${state.totalBadgeCount} demande${state.totalBadgeCount > 1 ? 's' : ''} à traiter', icon: Icons.mark_email_unread_outlined, onTap: widget.onOpenRequests))),
        const SizedBox(height: 24),
        AppSection(title: 'Votre calendrier', action: TextButton(onPressed: widget.onOpenPlanning, child: const Text('Ouvrir')),
          child: Column(children: [
            Text(DateFormat.yMMMM('fr_FR').format(month), style: Theme.of(context).textTheme.titleMedium),
            PlanningCalendar(month: month, entries: {for(final e in monthEntries) e.dateStr: e},
              onDayTap: (date) => AppBottomSheet.show<void>(context, builder: (_) => ShiftDetailsSheet(date: date))),
          ])),
        AppSection(title: 'Pendant la garde', child: Column(children: [
          AppMenuItem(title: 'Qui est d’astreinte ?', subtitle: 'Juniors et seniors', icon: Icons.medical_services_outlined,
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AstreintesHubScreen()))),
          AppMenuItem(title: 'Annuaire hospitalier', subtitle: 'Services, médecins et extensions', icon: Icons.contacts_outlined,
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const DirectoryScreen()))),
        ])),
        const DailyNewsSection(),
      ],
    ));
  }
  DateTime _start(PlanningEntry e) {
    final d = DateTime.parse(e.dateStr), parts = ShiftCatalog.byId(e.shiftId).start!.split(':').map(int.parse).toList();
    return DateTime(d.year, d.month, d.day, parts[0], parts[1]);
  }
  DateTime _end(PlanningEntry e) {
    final d = DateTime.parse(e.dateStr), parts = ShiftCatalog.byId(e.shiftId).end!.split(':').map(int.parse).toList();
    var end = DateTime(d.year, d.month, d.day, parts[0], parts[1]);
    if (!end.isAfter(_start(e))) end = DateTime(d.year, d.month, d.day + 1, parts[0], parts[1]);
    return end;
  }
}

class GardeCard extends StatelessWidget {
  final PlanningEntry? entry;
  final AppUser user;
  final bool approved;
  final VoidCallback onTap;
  const GardeCard({super.key, required this.entry, required this.user, required this.approved, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final shift = entry == null ? null : ShiftCatalog.byId(entry!.shiftId);
    final v = shift == null ? null : ShiftVisual.of(context, shift);
    final bg = v?.background ?? c.surfaceContainer;
    final fg = v?.foreground ?? c.onSurface;
    final night = entry?.shiftId.endsWith('nuit') ?? false;
    final leave = entry?.shiftId == 'conge';
    final full = entry?.shiftId.endsWith('24h') ?? false;
    String? timing;
    String? finish;
    if (entry != null && shift!.hasSchedule) {
      final now = DateTime.now();
      final date = DateTime.parse(entry!.dateStr);
      final startParts = shift.start!.split(':').map(int.parse).toList();
      final endParts = shift.end!.split(':').map(int.parse).toList();
      final start = DateTime(date.year, date.month, date.day, startParts[0], startParts[1]);
      var end = DateTime(date.year, date.month, date.day, endParts[0], endParts[1]);
      if (!end.isAfter(start)) end = DateTime(date.year, date.month, date.day + 1, endParts[0], endParts[1]);
      timing = now.isBefore(start)
          ? night ? 'Vous êtes de garde cette nuit' : 'Votre garde commence à ${shift.start}'
          : now.isBefore(end) ? 'Votre garde est en cours' : 'Votre garde est terminée';
      if (end.day != start.day && now.isBefore(end)) {
        finish = AppState.dateKey(end) == AppState.dateKey(now)
            ? 'Fin aujourd’hui à ${shift.end}' : 'Fin demain à ${shift.end}';
      }
    }
    return Semantics(button: true, child: Material(color: bg, borderRadius: AppRadius.xlR,
      child: InkWell(onTap: onTap, borderRadius: AppRadius.xlR,
        child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(v?.icon ?? Icons.spa_outlined, color: fg, size: 28), const SizedBox(width: 12),
            Expanded(child: Text(shift == null ? 'Votre journée' : leave ? 'Congé' : full ? 'Garde de 24 heures' : night ? 'Garde de nuit' : 'Garde de jour', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: fg))),
            Icon(Icons.chevron_right_rounded, color: fg),
          ]),
          const SizedBox(height: 24),
          Text(shift == null ? 'Pas de garde\naujourd’hui' : leave ? 'Une pause prévue' : '${shift.start} → ${shift.end}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: fg)),
          if (timing != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(timing, style: TextStyle(color: fg, height: 1.5))),
          if (finish != null) Text(finish, style: TextStyle(color: fg, height: 1.5)),
          if (shift != null && !leave) ...[
            const SizedBox(height: 16),
            Text(entry!.shiftId.startsWith('urg-') ? 'Urgences' : user.service, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4), Text(hospitalDisplayName(user.hospital), style: TextStyle(color: fg)),
          ],
          if (entry != null && !approved) Padding(padding: const EdgeInsets.only(top: 14), child: Text('Planning provisoire', style: TextStyle(color: fg, fontWeight: FontWeight.w600))),
          if (entry?.isDisciplinary == true) Padding(padding: const EdgeInsets.only(top: 12), child: Row(children: [Icon(Icons.lock_outline, size: 16, color: fg), const SizedBox(width: 6), Expanded(child: Text('Garde disciplinaire', style: TextStyle(color: fg)))])),
        ])),
      ),
    ));
  }
}

class PersonalPlanningView extends StatefulWidget {
  const PersonalPlanningView({super.key});
  @override
  State<PersonalPlanningView> createState() => _PersonalPlanningViewState();
}
class _PersonalPlanningViewState extends State<PersonalPlanningView> {
  String? _selectedDate;
  bool _submitting = false;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final month = state.visibleMonth;
    final record = state.myPlanningMonth(month);
    final editable = state.canEditMyPlanningMonth(month);
    final now = DateTime.now();
    final past = month.isBefore(DateTime(now.year, now.month));
    final me = state.currentUser;
    final entries = {for(final e in state.planning.where((e) => e.ownerId == me?.id || e.ownerPhone == me?.phone)) e.dateStr: e};
    return ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
      MonthNavigation(label: DateFormat.yMMMM('fr_FR').format(month), onPrevious: state.previousMonth,
        onNext: state.canGoToNextMonth ? state.nextMonth : null),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Wrap(spacing: 12, runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (past) const Text('Consultation uniquement') else StatusBadge(status: record?.status ?? PlanningMonthStatus.draft, reopened: record?.rejectionReason?.trim().isNotEmpty ?? false),
          if (editable) TextButton.icon(onPressed: _submitting ? null : () => _validate(state, month), icon: const Icon(Icons.check_rounded), label: const Text('Valider le planning')),
        ])),
      if (record?.rejectionReason?.trim().isNotEmpty ?? false) Padding(padding: const EdgeInsets.all(8), child: Text('Motif de réouverture : ${record!.rejectionReason}')),
      PlanningCalendar(month: month, entries: entries, selectedDate: _selectedDate,
        onDayTap: (date) { setState(() => _selectedDate = AppState.dateKey(date)); AppBottomSheet.show<void>(context, builder: (_) => ShiftDetailsSheet(date: date)); },
        canDrop: (date, id) => planningEditReason(state, date, state.myEntryForDate(AppState.dateKey(date))) == null && !shiftHasStarted(date, ShiftCatalog.byId(id)),
        onDrop: (date, id) async {
          final error = await state.placeShift(AppState.dateKey(date), id);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Garde ajoutée au planning.')));
        }),
      const SizedBox(height: 12),
      const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('J · Jour     N · Nuit     24H · Garde complète     C · Congé', style: TextStyle(fontSize: 12))),
      const SizedBox(height: 16),
      if (editable) ...[
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('Touchez un jour pour choisir une garde, ou glissez une tuile sur le calendrier.')),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: ShiftPalette(onSelect: (id) => _choosePlacementDate(state, id))),
        const SizedBox(height: 16),
        if (state.backendEnabled) Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('Validation automatique : 7 jours après la publication ou le remplacement du planning officiel.', style: Theme.of(context).textTheme.bodySmall)),
      ] else if (!past) const ListTile(leading: Icon(Icons.lock_outline_rounded), title: Text('Planning verrouillé'), subtitle: Text('Les échanges et transferts restent accessibles depuis chaque garde disponible.')),
      const SizedBox(height: 16),
      AppMenuItem(title: 'Planning officiel', subtitle: 'Les PDF de vos établissements', icon: Icons.picture_as_pdf_outlined,
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const OfficialPlanningScreen()))),
    ]);
  }
  Future<void> _choosePlacementDate(AppState state, String id) async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final visible = state.visibleMonth;
    bool available(DateTime date) => planningEditReason(state, date, state.myEntryForDate(AppState.dateKey(date))) == null && !shiftHasStarted(date, ShiftCatalog.byId(id));
    var initial = visible.isBefore(first) ? first : visible;
    while (!available(initial) && !initial.isAfter(state.maxPlanningDate)) {
      initial = DateTime(initial.year, initial.month, initial.day + 1);
    }
    if (initial.isAfter(state.maxPlanningDate)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucune date disponible pour cette tuile.')));
      return;
    }
    final date = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: state.maxPlanningDate,
      selectableDayPredicate: available);
    if (date == null || !mounted) return;
    final error = await state.placeShift(AppState.dateKey(date), id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Garde ajoutée au planning.')));
  }
  Future<void> _validate(AppState state, DateTime month) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
     scrollable: true,
title: const Text('Valider définitivement ce planning ?'),
      content: const Text('Vos tuiles seront verrouillées. Les congés seront envoyés à l’administration pour approbation. Un administrateur pourra rouvrir le mois pour correction.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revenir')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Valider définitivement'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => _submitting = true);
    final error = await state.submitMyPlanningMonth(month);
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error ?? 'Planning validé.')));
  }
}
