import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/hospitals.dart';
import '../state/app_state.dart';
import '../ui/components.dart';
import 'auth_screen.dart';
import 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  final bool embedded;
  const ProfileScreen({super.key, this.embedded = false});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final user = state.currentUser;
    if (user == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final content = ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 32), children: [
      DoctorTile(name: 'Dr ${user.fullName}', subtitle: '${user.gradeLabel} · ${user.roleLabel}'),
      const SizedBox(height: 32),
      AppSection(title: 'Votre identité', child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _ProfileInfo(label: 'Établissement', value: hospitalDisplayName(user.hospital), icon: Icons.local_hospital_outlined),
        _ProfileInfo(label: 'Service', value: user.service, icon: Icons.medical_services_outlined),
        _ProfileInfo(label: 'Téléphone du compte', value: user.phone, icon: Icons.phone_outlined),
      ])),
      Text('Ces informations permettent de vous retrouver dans les plannings. Contactez un administrateur pour toute correction.', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 24),
      AppMenuItem(title: 'Notifications et rappels', icon: Icons.alarm_outlined, onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen(reminderFocus: true)))),
      AppMenuItem(title: 'Apparence', icon: Icons.palette_outlined, onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ApplicationSettingsScreen()))),
      const SizedBox(height: 32),
      SecondaryButton(label: 'Se déconnecter', onPressed: () async {
        await state.logout();
        if (!context.mounted) return;
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const AuthScreen()), (_) => false);
      }),
    ]);
    return embedded ? content : Scaffold(appBar: AppBar(title: const Text('Mon profil')), body: SafeArea(top: false, child: content));
  }
}
class _ProfileInfo extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _ProfileInfo({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => ListTile(contentPadding: const EdgeInsets.symmetric(vertical: 8),
    leading: Icon(icon), title: Text(label, style: Theme.of(context).textTheme.bodySmall),
    subtitle: Text(value, style: Theme.of(context).textTheme.titleMedium));
}
