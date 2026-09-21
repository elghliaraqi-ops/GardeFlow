import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_user.dart';
import '../state/app_state.dart';
import '../ui/components.dart';
import 'admin_screen.dart';
import 'admin_password_reset_screen.dart';
import 'astreinte_screen.dart';
import 'audit_screen.dart';
import 'directory_screen.dart';
import 'junior_oncall_screen.dart';
import 'notifications_screen.dart';
import 'official_planning_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

void _open(BuildContext context, Widget screen) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AppState>().currentUser?.role == UserRole.admin;
    return ListView(padding: const EdgeInsets.fromLTRB(12, 16, 12, 24), children: [
      AppSection(title: 'Au quotidien', child: Column(children: [
        AppMenuItem(title: 'Astreintes', subtitle: 'Juniors, seniors et documents', icon: Icons.medical_services_outlined, onTap: () => _open(context, const AstreintesHubScreen())),
        AppMenuItem(title: 'Annuaire', subtitle: 'Services, médecins et extensions', icon: Icons.contacts_outlined, onTap: () => _open(context, const DirectoryScreen())),
        AppMenuItem(title: 'Planning officiel', subtitle: 'Documents PDF des établissements', icon: Icons.picture_as_pdf_outlined, onTap: () => _open(context, const OfficialPlanningScreen())),
      ])),
      AppSection(title: 'Votre espace', child: Column(children: [
        AppMenuItem(title: 'Mon profil', subtitle: 'Identité et compte', icon: Icons.person_outline_rounded, onTap: () => _open(context, const ProfileScreen())),
        AppMenuItem(title: 'Notifications et rappels', subtitle: 'Alarmes, sonnerie et horaires', icon: Icons.alarm_outlined, onTap: () => _open(context, const SettingsScreen(reminderFocus: true))),
        AppMenuItem(title: 'Apparence', subtitle: 'Vert, rouge, clair ou sombre', icon: Icons.palette_outlined, onTap: () => _open(context, const ApplicationSettingsScreen())),
      ])),
      if (admin) AppSection(title: 'Administration', child: AppMenuItem(title: 'Espace administrateur', subtitle: 'Comptes, plannings et demandes', icon: Icons.admin_panel_settings_outlined, onTap: () => _open(context, const AdminHubScreen()))),
    ]);
  }
}
class AstreintesHubScreen extends StatefulWidget {
  const AstreintesHubScreen({super.key});
  @override
  State<AstreintesHubScreen> createState() => _AstreintesHubScreenState();
}
class _AstreintesHubScreenState extends State<AstreintesHubScreen> {
  int _mode = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Astreintes')),
    body: SafeArea(top: false, child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), child: SizedBox(width: double.infinity,
        child: SegmentedButton<int>(segments: const [ButtonSegment(value: 0, label: Text('Juniors')), ButtonSegment(value: 1, label: Text('Seniors'))],
          selected: {_mode}, onSelectionChanged: (s) => setState(() => _mode = s.first)))),
      Expanded(child: IndexedStack(index: _mode, children: const [JuniorOnCallScreen(embedded: true), AstreinteScreen(embedded: true)])),
    ])),
  );
}
class AdminHubScreen extends StatelessWidget {
  const AdminHubScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.currentUser?.role != UserRole.admin) return const Scaffold(body: SafeArea(child: EmptyState(icon: Icons.lock_outline, title: 'Accès réservé aux administrateurs')));
    return Scaffold(appBar: AppBar(title: const Text('Administration')), body: ListView(padding: const EdgeInsets.all(16), children: [
      Text('Que souhaitez-vous gérer ?', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8), Text('${state.totalBadgeCount} demande${state.totalBadgeCount > 1 ? 's' : ''} à traiter', style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 24),
      AppMenuItem(title: 'Comptes', subtitle: 'Inscriptions et récupération de compte', icon: Icons.manage_accounts_outlined, onTap: () => _open(context, const NotificationsScreen(initialIndex: 3))),
      AppMenuItem(title: 'Vérifier les inscriptions', subtitle: 'Établissement, service et grade', icon: Icons.fact_check_outlined, onTap: () => _open(context, const AdminScreen(showAccountsOnOpen: true))),
      AppMenuItem(title: 'Gérer les comptes existants', subtitle: 'Mots de passe et suppression de comptes', icon: Icons.person_search_outlined, onTap: () => _open(context, const AdminPasswordResetScreen())),
      const Divider(),
      AppMenuItem(title: 'Plannings', subtitle: 'Établissement → médecin → calendrier', icon: Icons.calendar_month_outlined, onTap: () => _open(context, const AdminScreen())),
      AppMenuItem(title: 'Demandes', subtitle: 'Échanges et transferts', icon: Icons.swap_horiz_rounded, onTap: () => _open(context, const NotificationsScreen(initialIndex: 1))),
      AppMenuItem(title: 'Congés', subtitle: 'Demandes regroupées par médecin', icon: Icons.beach_access_outlined, onTap: () => _open(context, const NotificationsScreen(initialIndex: 2))),
      const Divider(),
      AppMenuItem(title: 'Astreintes', subtitle: 'Consulter et publier les documents', icon: Icons.medical_services_outlined, onTap: () => _open(context, const AstreintesHubScreen())),
      AppMenuItem(title: 'Documents', subtitle: 'Plannings officiels et superposition', icon: Icons.folder_open_outlined, onTap: () => _open(context, const OfficialPlanningScreen())),
      AppMenuItem(title: 'Notifications', icon: Icons.notifications_outlined, onTap: () => _open(context, const NotificationsScreen())),
      AppMenuItem(title: 'Historique', subtitle: 'Journal des actions administratives', icon: Icons.history_rounded, onTap: () => _open(context, const AuditScreen())),
    ]));
  }
}
