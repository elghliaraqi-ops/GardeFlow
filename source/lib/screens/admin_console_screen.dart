import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_user.dart';
import '../models/exchange_request.dart';
import '../models/leave_request.dart';
import '../models/planning_month.dart';
import '../services/official_roster_import_service.dart';
import '../services/supabase_backend_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/screen_decor.dart';
import '../theme/widgets.dart';
import 'admin_disciplinary_assignment_screen.dart';
import 'admin_official_roster_review_screen.dart';
import 'admin_password_reset_screen.dart';
import 'admin_roster_recalculation_screen.dart';
import 'admin_screen.dart';
import 'application_settings_screen.dart';
import 'audit_screen.dart';
import 'notifications_screen.dart';
import 'official_planning_screen.dart';

class AdminConsoleScreen extends StatefulWidget {
  const AdminConsoleScreen({super.key});

  @override
  State<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

class _AdminConsoleScreenState extends State<AdminConsoleScreen> {
  final _backend = SupabaseBackendService.instance;
  List<Map<String, dynamic>> _reports = const [];
  bool _loadingReports = false;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    if (!_backend.enabled) return;
    setState(() => _loadingReports = true);
    try {
      final reports =
          await _backend.fetchOfficialRosterImportReports(limit: 30);
      if (mounted) setState(() => _reports = reports);
    } catch (_) {
      // La console historique reste utilisable même si les tables R6
      // ne sont pas encore disponibles sur un environnement.
    } finally {
      if (mounted) setState(() => _loadingReports = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final me = appState.currentUser;
    if (me == null || me.role != UserRole.admin) {
      return DecorScaffold(
        scene: ScreenDecorScene.admin,
        appBar: AppBar(title: const GardeFlowTitle('Console administrateur')),
        body: const Center(
          child: Text('Accès réservé aux administrateurs.'),
        ),
      );
    }

    final activeDoctors = appState.users
        .where((user) => user.accountStatus == AccountStatus.active)
        .length;
    final pendingAccounts = appState.pendingUsers.length;
    final pendingExchanges = appState.exchanges
        .where((request) => request.status == ExchangeStatus.pendingAdmin)
        .length;
    final pendingLeaves = appState.leaveRequests
        .where((request) => request.status == LeaveRequestStatus.pendingAdmin)
        .length;
    final pendingPlanningMonths = appState.planningMonths
        .where((month) => month.status == PlanningMonthStatus.submitted)
        .length;
    final anomalyCount = _reports.fold<int>(
      0,
      (sum, report) =>
          sum + ((report['anomaly_count'] as num?)?.toInt() ?? 0),
    );
    final orangeCount =
        _reports.where((report) => report['status'] == 'orange').length;

    return DecorScaffold(
      scene: ScreenDecorScene.admin,
      appBar: AppBar(
        title: const GardeFlowTitle('Console administrateur'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () async {
              try {
                await appState.refreshBackend();
              } catch (_) {}
              await _loadReports();
            },
            icon: _loadingReports
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          const DecorSectionBanner(
            scene: ScreenDecorScene.admin,
            title: 'Centre de contrôle GardeFlow',
            subtitle:
                'Comptes, plannings officiels, imports, validations, '
                'superpositions et traçabilité dans une architecture unique.',
            icon: Icons.admin_panel_settings_rounded,
          ),
          const SizedBox(height: 16),
          _DashboardMetrics(
            metrics: [
              _Metric(
                'Médecins actifs',
                activeDoctors,
                Icons.groups_rounded,
                AppColors.info,
              ),
              _Metric(
                'Comptes à valider',
                pendingAccounts,
                Icons.person_add_alt_1_rounded,
                AppColors.warning,
              ),
              _Metric(
                'Imports R6',
                _reports.length,
                Icons.picture_as_pdf_rounded,
                AppColors.success,
              ),
              _Metric(
                'Arbitrages ORANGE',
                orangeCount,
                Icons.rule_rounded,
                AppColors.warning,
              ),
              _Metric(
                'Anomalies tracées',
                anomalyCount,
                Icons.report_problem_rounded,
                AppColors.violet,
              ),
              _Metric(
                'Validations planning',
                pendingPlanningMonths,
                Icons.fact_check_rounded,
                AppColors.info,
              ),
              _Metric(
                'Échanges admin',
                pendingExchanges,
                Icons.swap_horiz_rounded,
                AppColors.urg24h,
              ),
              _Metric(
                'Congés en attente',
                pendingLeaves,
                Icons.event_busy_rounded,
                AppColors.warning,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _AdminSection(
            title: 'Médecins et utilisateurs',
            subtitle:
                'Comptes, profils, rôles, statuts et correspondances officielles.',
            icon: Icons.badge_rounded,
            actions: [
              _ConsoleAction(
                title: 'Gestion des comptes',
                subtitle: 'Validation, recherche et administration',
                icon: Icons.manage_accounts_rounded,
                color: AppColors.info,
                onTap: () => _open(context, const AdminScreen()),
              ),
              _ConsoleAction(
                title: 'Mots de passe / suppression',
                subtitle: 'Outils sensibles de gestion des comptes',
                icon: Icons.admin_panel_settings_rounded,
                color: AppColors.danger,
                onTap: () =>
                    _open(context, const AdminPasswordResetScreen()),
              ),
              _ConsoleAction(
                title: 'Identités du planning',
                subtitle: 'Non inscrits, homonymes et liaisons persistantes',
                icon: Icons.link_rounded,
                color: AppColors.violet,
                onTap: () => _open(
                  context,
                  const AdminOfficialRosterReviewScreen(),
                ),
              ),
            ],
          ),
          _AdminSection(
            title: 'Plannings officiels',
            subtitle:
                'Consultation, import, versions, contrôles et source de vérité.',
            icon: Icons.picture_as_pdf_rounded,
            actions: [
              _ConsoleAction(
                title: 'Plannings officiels',
                subtitle: 'Consulter, importer et gérer les PDF officiels',
                icon: Icons.library_books_rounded,
                color: AppColors.info,
                onTap: () => _open(context, const OfficialPlanningScreen()),
              ),
              _ConsoleAction(
                title: 'Lecture PDF / Import',
                subtitle: 'Statuts VERT / ORANGE, conflits et scores',
                icon: Icons.document_scanner_rounded,
                color: AppColors.success,
                onTap: () => _open(
                  context,
                  const AdminOfficialRosterReviewScreen(),
                ),
              ),
            ],
          ),
          _AdminSection(
            title: 'Calendriers et superpositions',
            subtitle:
                'Reconstruire la couche personnelle sans altérer le planning officiel.',
            icon: Icons.layers_rounded,
            actions: [
              _ConsoleAction(
                title: 'Recalcul individuel / global',
                subtitle: 'Aperçu ajout, retrait, modification et conflits',
                icon: Icons.layers_clear_rounded,
                color: AppColors.violet,
                onTap: () => _open(
                  context,
                  const AdminRosterRecalculationScreen(),
                ),
              ),
              _ConsoleAction(
                title: 'Calendriers historiques',
                subtitle: 'Vue admin complète conservée sans régression',
                icon: Icons.calendar_month_rounded,
                color: AppColors.info,
                onTap: () => _open(context, const AdminScreen()),
              ),
            ],
          ),
          _AdminSection(
            title: 'Échanges, transferts et demandes',
            subtitle:
                'Les règles métier existantes restent inchangées.',
            icon: Icons.swap_horiz_rounded,
            actions: [
              _ConsoleAction(
                title: 'Transferts / Échanges',
                subtitle: 'Demandes et validations administrateur',
                icon: Icons.swap_calls_rounded,
                color: AppColors.urg24h,
                onTap: () =>
                    _open(context, const NotificationsScreen(initialIndex: 1)),
              ),
              _ConsoleAction(
                title: 'Congés',
                subtitle: 'Demandes en attente et historique',
                icon: Icons.event_available_rounded,
                color: AppColors.warning,
                onTap: () =>
                    _open(context, const NotificationsScreen(initialIndex: 2)),
              ),
            ],
          ),
          _AdminSection(
            title: 'Validations et notifications',
            subtitle:
                'Validations médecins/admin et alertes existantes conservées.',
            icon: Icons.verified_user_rounded,
            actions: [
              _ConsoleAction(
                title: 'Validations de planning',
                subtitle: 'Valider, refuser ou rouvrir un mois',
                icon: Icons.fact_check_rounded,
                color: AppColors.success,
                onTap: () => _open(context, const AdminScreen()),
              ),
              _ConsoleAction(
                title: 'Notifications',
                subtitle: 'Alertes, demandes et comptes',
                icon: Icons.notifications_active_rounded,
                color: AppColors.warning,
                onTap: () => _open(context, const NotificationsScreen()),
              ),
            ],
          ),
          _AdminSection(
            title: 'Gardes disciplinaires',
            subtitle:
                'Attribution et protections historiques maintenues.',
            icon: Icons.gavel_rounded,
            actions: [
              _ConsoleAction(
                title: 'Attribution disciplinaire',
                subtitle: 'Créer et administrer une garde protégée',
                icon: Icons.assignment_turned_in_rounded,
                color: AppColors.danger,
                onTap: () => _open(
                  context,
                  const AdminDisciplinaryAssignmentScreen(),
                ),
              ),
            ],
          ),
          _AdminSection(
            title: 'Logs et traçabilité',
            subtitle:
                'Actions sensibles, imports, associations et recalculs.',
            icon: Icons.history_rounded,
            actions: [
              _ConsoleAction(
                title: 'Journal administratif',
                subtitle: 'Historique des actions et diagnostics',
                icon: Icons.receipt_long_rounded,
                color: AppColors.violet,
                onTap: () => _open(context, const AuditScreen()),
              ),
              _ConsoleAction(
                title: 'Rapports d’import',
                subtitle: 'Conflits A/B/C et corrections ciblées',
                icon: Icons.rule_folder_rounded,
                color: AppColors.warning,
                onTap: () => _open(
                  context,
                  const AdminOfficialRosterReviewScreen(),
                ),
              ),
            ],
          ),
          _AdminSection(
            title: 'Paramètres et maintenance',
            subtitle:
                'Outils techniques sans modification implicite des règles métier.',
            icon: Icons.build_circle_rounded,
            actions: [
              _ConsoleAction(
                title: 'Réglages de l’application',
                subtitle: 'Apparence et paramètres généraux',
                icon: Icons.tune_rounded,
                color: AppColors.info,
                onTap: () =>
                    _open(context, const ApplicationSettingsScreen()),
              ),
              _ConsoleAction(
                title: 'Moteur de lecture',
                subtitle:
                    'Révision ${OfficialRosterImportService.parserRevision} • R4 conservé + A/B/C R6',
                icon: Icons.memory_rounded,
                color: AppColors.success,
                onTap: () => _showEngineInfo(context),
              ),
              _ConsoleAction(
                title: 'Vue Admin historique complète',
                subtitle:
                    'Accès de compatibilité à toutes les fonctions antérieures',
                icon: Icons.inventory_2_rounded,
                color: AppColors.warning,
                onTap: () => _open(context, const AdminScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Future<void> _showEngineInfo(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Moteur de lecture officiel'),
        content: const Text(
          'R6 conserve les sécurités R4/R5.\n\n'
          '• Lecture A indépendante : géométrique locale, ou secours visuel.\n'
          '• Lecture B : analyse visuelle indépendante sans liste de comptes.\n'
          '• Lecture C : uniquement en cas de désaccord ou contrôle incomplet.\n'
          '• VERT : A/B concordants + structure complète.\n'
          '• ORANGE : C arbitre avec contrôles finaux valides.\n'
          '• ROUGE : publication automatique bloquée.\n\n'
          'Une garde officielle est conservée même si le médecin n’a pas de compte.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }
}

class _Metric {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _Metric(this.label, this.value, this.icon, this.color);
}

class _DashboardMetrics extends StatelessWidget {
  final List<_Metric> metrics;
  const _DashboardMetrics({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        final width =
            (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: metric.color.withOpacity(.12),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(metric.icon, color: metric.color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${metric.value}',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                metric.label,
                                style: TextStyle(
                                  color: AppColors.inkSoft,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _AdminSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<_ConsoleAction> actions;

  const _AdminSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: AppCard(
        padding: const EdgeInsets.all(16),
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
                    color: AppColors.warning.withOpacity(.11),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: AppColors.warning),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final itemWidth =
                    wide ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: actions
                      .map(
                        (action) => SizedBox(
                          width: itemWidth,
                          child: _ActionTile(action: action),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsoleAction {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ConsoleAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _ActionTile extends StatelessWidget {
  final _ConsoleAction action;
  const _ActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paperAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(action.icon, color: action.color),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.inkFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
