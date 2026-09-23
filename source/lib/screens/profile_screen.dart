import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/hospitals.dart';
import '../models/app_user.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';
import 'admin_disciplinary_assignment_screen.dart';
import 'admin_password_reset_screen.dart';
import 'admin_screen.dart';
import 'astreinte_screen.dart';
import 'auth_screen.dart';
import 'junior_oncall_screen.dart';
import 'notifications_screen.dart';
import 'official_planning_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  final bool embedded;

  const ProfileScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    final content = user == null
        ? const Center(child: CircularProgressIndicator())
        : _ProfileContent(user: user, appState: appState);

    if (embedded) {
      return ColoredBox(
        color: AppColors.paper,
        child: SafeArea(bottom: false, child: content),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: GardeFlowTitle('Mon profil'),
        actions: [
          IconButton(
            tooltip: 'Réglages de l’application',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ApplicationSettingsScreen(),
              ),
            ),
            icon: Icon(Icons.settings_outlined),
          ),
          SizedBox(width: 6),
        ],
      ),
      body: content,
    );
  }
}

class _ProfileContent extends StatelessWidget {
  final AppUser user;
  final AppState appState;

  const _ProfileContent({required this.user, required this.appState});

  @override
  Widget build(BuildContext context) {
    final initials = [user.prenom, user.nom]
        .where((part) => part.trim().isNotEmpty)
        .map((part) => part.trim()[0].toUpperCase())
        .take(2)
        .join();

    return ListView(
      physics: BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [

        BlueHero(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withOpacity(0.22)),
                    ),
                    child: Text(
                      initials.isEmpty ? '?' : initials,
                      style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900),
                    ),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                user.fullName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'SpaceGrotesk',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  height: 1.05,
                                ),
                              ),
                            ),
                            if (user.role == UserRole.admin)
                              Pill(
                                text: 'Admin',
                                background: Colors.white,
                                foreground: AppColors.brandDark,
                                fontSize: 10,
                              ),
                          ],
                        ),
                        SizedBox(height: 7),
                        Text(
                          '${user.gradeLabel} · ${user.service}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(0.90), fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        SizedBox(height: 3),
                        Text(
                          hospitalDisplayName(user.hospital),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(0.72), fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.16)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.phone_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        user.phone,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      user.roleLabel,
                      style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 24),
        SectionLabel('Mon espace'),
        _ProfileMenuCard(
          children: [
            _ProfileMenuItem(
              icon: Icons.settings_suggest_rounded,
              title: 'Réglages de l’application',
              subtitle: 'Thème, apparence et informations',
              color: AppColors.brand,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ApplicationSettingsScreen(),
                ),
              ),
            ),
            _ProfileMenuItem(
              icon: Icons.alarm_rounded,
              title: 'Rappels de garde',
              subtitle: 'Horaires, alarme longue et notifications Android',
              color: AppColors.cyan,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(reminderFocus: true),
                ),
              ),
            ),
            _ProfileMenuItem(
              icon: Icons.notifications_none_rounded,
              title: 'Notifications',
              subtitle: 'Demandes, échanges et alertes',
              color: AppColors.warning,
              badge: appState.totalBadgeCount,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen())),
            ),
            _ProfileMenuItem(
              icon: Icons.picture_as_pdf_rounded,
              title: 'Plannings officiels',
              subtitle: 'Consulter les PDF de garde des établissements',
              color: AppColors.urg24h,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => OfficialPlanningScreen())),
            ),
            _ProfileMenuItem(
              icon: Icons.medical_services_outlined,
              title: 'Astreintes',
              subtitle: 'Séniors et juniors',
              color: Color(0xFF7557D8),
              onTap: () => _openAstreinteChooser(context),
            ),
          ],
        ),
        if (user.role == UserRole.admin) ...[
          SizedBox(height: 24),
          SectionLabel('Administration'),
          _ProfileMenuCard(
            children: [
              _ProfileMenuItem(
                icon: Icons.admin_panel_settings_rounded,
                title: 'Console administrateur',
                subtitle: 'Comptes, plannings et validations',
                color: AppColors.navy,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminScreen())),
              ),
              _ProfileMenuItem(
                icon: Icons.gavel_rounded,
                title: 'Gardes disciplinaires',
                subtitle: 'Attribuer une ou plusieurs gardes à un médecin',
                color: AppColors.danger,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminDisciplinaryAssignmentScreen(),
                  ),
                ),
              ),
              _ProfileMenuItem(
                icon: Icons.manage_accounts_rounded,
                title: 'Gestion des comptes',
                subtitle: 'Réinitialiser un mot de passe ou supprimer un compte',
                color: AppColors.cyan,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPasswordResetScreen())),
              ),
            ],
          ),
        ],
        SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: Icon(Icons.logout_rounded, color: AppColors.danger),
            label: Text('Se déconnecter', style: TextStyle(color: AppColors.danger)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.danger.withOpacity(0.28)),
              backgroundColor: AppColors.card,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _logout(BuildContext context) async {
    await appState.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  Future<void> _openAstreinteChooser(BuildContext context) async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.medical_services_outlined, color: Color(0xFF7557D8)),
                title: const Text('Astreintes séniors'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(ctx, 1),
              ),
              ListTile(
                leading: const Icon(Icons.groups_2_outlined, color: Color(0xFFEF8D32)),
                title: const Text('Astreintes juniors'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(ctx, 2),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 1) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AstreinteScreen()));
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const JuniorOnCallScreen()));
    }
  }
}

class _ProfileMenuCard extends StatelessWidget {
  final List<Widget> children;
  const _ProfileMenuCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Padding(
                padding: EdgeInsets.only(left: 66),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final int badge;

  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.lgR,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withOpacity(0.11), borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: color, size: 21),
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
            if (badge > 0)
              Container(
                margin: EdgeInsets.only(right: 7),
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.danger, borderRadius: AppRadius.pillR),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
            Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}
