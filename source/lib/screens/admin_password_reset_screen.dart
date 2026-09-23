import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../services/supabase_backend_service.dart';
import '../theme/app_theme.dart';
import '../theme/widgets.dart';

class AdminPasswordResetScreen extends StatefulWidget {
  final String? initialUserId;
  const AdminPasswordResetScreen({super.key, this.initialUserId});

  @override
  State<AdminPasswordResetScreen> createState() =>
      _AdminPasswordResetScreenState();
}

class _AdminPasswordResetScreenState extends State<AdminPasswordResetScreen> {
  final _backend = SupabaseBackendService.instance;
  final _searchCtrl = TextEditingController();
  List<AppUser> _profiles = const <AppUser>[];
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _openedInitialUser = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_backend.enabled || _backend.client.auth.currentUser == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Connexion Supabase requise.';
        });
      }
      return;
    }

    try {
      final rows = await _backend.fetchVisibleProfiles();
      final doctors = rows.where((p) => p.role != UserRole.admin).toList()
        ..sort(
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );
      if (!mounted) return;
      setState(() {
        _profiles = doctors;
        _loading = false;
        _error = null;
      });
      final initialUserId = widget.initialUserId;
      if (!_openedInitialUser && initialUserId != null) {
        final initialProfile = doctors
            .where((p) => p.id == initialUserId)
            .firstOrNull;
        if (initialProfile != null) {
          _openedInitialUser = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _resetFor(initialProfile);
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les comptes : $e';
      });
    }
  }

  List<AppUser> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _profiles;
    return _profiles
        .where((p) {
          return p.fullName.toLowerCase().contains(q) ||
              p.phone.toLowerCase().contains(q) ||
              p.service.toLowerCase().contains(q) ||
              p.hospital.toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  Widget _profileSummary(BuildContext context, AppUser profile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.paperAlt,
        borderRadius: AppRadius.smR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(profile.fullName, style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 3),
          Text(profile.phone, style: Theme.of(context).textTheme.bodySmall),
          SizedBox(height: 2),
          Text(profile.service, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Future<void> _resetFor(AppUser profile) async {
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var obscurePassword = true;
    var obscureConfirm = true;
    var saving = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> submit() async {
            if (saving) return;
            final password = passwordCtrl.text;
            final confirmation = confirmCtrl.text;
            if (password.length < 8) {
              setDialogState(
                () => dialogError =
                    'Le mot de passe doit contenir au moins 8 caractères.',
              );
              return;
            }
            if (password != confirmation) {
              setDialogState(
                () => dialogError =
                    'Les deux mots de passe ne correspondent pas.',
              );
              return;
            }

            setDialogState(() {
              saving = true;
              dialogError = null;
            });
            try {
              await _backend.adminResetUserPassword(
                userId: profile.id,
                newPassword: password,
              );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              if (!mounted) return;
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Mot de passe de ${profile.fullName} réinitialisé avec succès.',
                  ),
                  backgroundColor: AppColors.success,
                ),
              );
            } catch (e) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                saving = false;
                dialogError = e
                    .toString()
                    .replaceFirst('Bad state: ', '')
                    .replaceFirst('Invalid argument(s): ', '');
              });
            }
          }

          return AlertDialog(
            title: Text('Réinitialiser le mot de passe'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _profileSummary(context, profile),
                  SizedBox(height: 16),
                  TextField(
                    controller: passwordCtrl,
                    autofocus: true,
                    obscureText: obscurePassword,
                    enabled: !saving,
                    decoration: InputDecoration(
                      labelText: 'Nouveau mot de passe',
                      helperText: '8 caractères minimum',
                      suffixIcon: IconButton(
                        onPressed: saving
                            ? null
                            : () => setDialogState(
                                () => obscurePassword = !obscurePassword,
                              ),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: obscureConfirm,
                    enabled: !saving,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                      labelText: 'Confirmer le mot de passe',
                      suffixIcon: IconButton(
                        onPressed: saving
                            ? null
                            : () => setDialogState(
                                () => obscureConfirm = !obscureConfirm,
                              ),
                        icon: Icon(
                          obscureConfirm
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ),
                    ),
                  ),
                  if (dialogError != null) ...[
                    SizedBox(height: 12),
                    Text(
                      dialogError!,
                      style: TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  SizedBox(height: 10),
                  Text(
                    'L’ancien mot de passe ne sera pas affiché. Cette action remplace immédiatement le mot de passe du compte Supabase.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.inkSoft, height: 1.4),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: saving ? null : submit,
                icon: saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.lock_reset_rounded),
                label: Text(saving ? 'Modification…' : 'Réinitialiser'),
              ),
            ],
          );
        },
      ),
    );

    passwordCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _deleteFor(AppUser profile) async {
    final confirmCtrl = TextEditingController();
    var deleting = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      barrierDismissible: !deleting,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final confirmationOk =
              confirmCtrl.text.trim().toUpperCase() == 'SUPPRIMER';

          Future<void> submit() async {
            if (deleting) return;
            if (!confirmationOk) {
              setDialogState(
                () => dialogError =
                    'Tapez SUPPRIMER pour confirmer la suppression définitive.',
              );
              return;
            }

            setDialogState(() {
              deleting = true;
              dialogError = null;
            });

            try {
              await _backend.adminDeleteUserAccount(userId: profile.id);
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              if (!mounted) return;
              setState(() {
                _profiles = _profiles
                    .where((p) => p.id != profile.id)
                    .toList(growable: false);
              });
              ScaffoldMessenger.of(this.context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Compte de ${profile.fullName} supprimé avec ses gardes et ses données.',
                  ),
                  backgroundColor: AppColors.success,
                ),
              );
            } catch (e) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                deleting = false;
                dialogError = e
                    .toString()
                    .replaceFirst('Bad state: ', '')
                    .replaceFirst('Invalid argument(s): ', '');
              });
            }
          }

          return AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                SizedBox(width: 10),
                Expanded(child: Text('Supprimer définitivement le compte')),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _profileSummary(context, profile),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.08),
                      borderRadius: AppRadius.smR,
                      border: Border.all(
                        color: AppColors.danger.withOpacity(0.35),
                      ),
                    ),
                    child: Text(
                      'Cette action est irréversible. Le compte, ses gardes, congés, demandes d’échange, notifications et autres données personnelles seront supprimés.',
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmCtrl,
                    autofocus: true,
                    enabled: !deleting,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) {
                      if (dialogError != null)
                        setDialogState(() => dialogError = null);
                      else
                        setDialogState(() {});
                    },
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(
                      labelText: 'Tapez SUPPRIMER',
                      hintText: 'SUPPRIMER',
                    ),
                  ),
                  if (dialogError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      dialogError!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: deleting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: deleting || !confirmationOk ? null : submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                icon: deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_forever_rounded),
                label: Text(deleting ? 'Suppression…' : 'Supprimer le compte'),
              ),
            ],
          );
        },
      ),
    );

    confirmCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: GardeFlowTitle('Gestion des comptes')),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                0,
              ),
              child: AppCard(
                padding: EdgeInsets.all(AppSpace.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.admin_panel_settings_rounded,
                      color: AppColors.brand,
                    ),
                    SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        'Touchez le cadenas pour changer un mot de passe. La corbeille supprime définitivement le compte et ses données.',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: AppColors.inkSoft, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.sm,
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Rechercher un médecin…',
                  prefixIcon: Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          icon: Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpace.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_off_rounded,
                              size: 38,
                              color: AppColors.inkSoft,
                            ),
                            SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center),
                            SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                });
                                _load();
                              },
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Réessayer'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : rows.isEmpty
                  ? const Center(child: Text('Aucun médecin trouvé.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.lg,
                          AppSpace.sm,
                          AppSpace.lg,
                          AppSpace.xl,
                        ),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final profile = rows[index];
                          return AppCard(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: AppColors.paperAlt,
                                child: Text(
                                  profile.fullName.isEmpty
                                      ? '?'
                                      : profile.fullName
                                            .trim()[0]
                                            .toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              title: Text(
                                profile.fullName,
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(
                                '${profile.phone}\n${profile.service}',
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Réinitialiser le mot de passe',
                                    onPressed: () => _resetFor(profile),
                                    icon: Icon(
                                      Icons.lock_reset_rounded,
                                      color: AppColors.brand,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Supprimer le compte',
                                    onPressed: () => _deleteFor(profile),
                                    icon: Icon(
                                      Icons.delete_forever_rounded,
                                      color: AppColors.danger,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _resetFor(profile),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
