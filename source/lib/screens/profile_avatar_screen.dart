import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/profile_avatars.dart';
import '../models/app_user.dart';
import '../services/profile_avatar_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/screen_decor.dart';
import '../theme/widgets.dart';
import '../widgets/profile_avatar.dart';

class ProfileAvatarScreen extends StatefulWidget {
  const ProfileAvatarScreen({super.key});

  @override
  State<ProfileAvatarScreen> createState() => _ProfileAvatarScreenState();
}

class _ProfileAvatarScreenState extends State<ProfileAvatarScreen> {
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ProfileAvatarService.instance.ensureLoaded(force: true);
      } catch (_) {
        // Le choix reste accessible ; une nouvelle tentative aura lieu au clic.
      }
    });
  }

  Future<void> _select(String? key) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ProfileAvatarService.instance.setMyAvatar(key);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            key == null
                ? 'Avatar retiré : vos initiales seront utilisées.'
                : 'Avatar mis à jour dans GardeFlow.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;

    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final junior = user.grade == MedicalGrade.junior;
    return DecorScaffold(
      scene: ScreenDecorScene.profile,
      appBar: AppBar(title: const GardeFlowTitle('Profil')),
      body: junior
          ? AnimatedBuilder(
              animation: ProfileAvatarService.instance,
              builder: (context, _) {
                final selected = ProfileAvatarService.instance.avatarKeyFor(user.id);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
                  children: [
                    Text(
                      'Choisir mon avatar',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Votre avatar remplace vos initiales partout où votre profil Junior apparaît dans GardeFlow, notamment dans l’annuaire. Vous pouvez choisir « Aucun » à tout moment.',
                      style: TextStyle(
                        color: AppColors.inkSoft,
                        fontSize: 13.5,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.danger.withOpacity(0.22)),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 650 ? 4 : 3;
                        return GridView.count(
                          crossAxisCount: columns,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.83,
                          children: [
                            _AvatarChoiceCard(
                              label: 'Aucun',
                              selected: selected == null || selected.trim().isEmpty,
                              disabled: _saving,
                              onTap: () => _select(null),
                              child: Container(
                                color: AppColors.paperAlt,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 31,
                                      backgroundColor: AppColors.brand.withOpacity(0.12),
                                      child: Text(
                                        user.initials,
                                        style: TextStyle(
                                          color: AppColors.brandDark,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Initiales',
                                      style: TextStyle(
                                        color: AppColors.inkSoft,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            for (final option in kProfileAvatarOptions)
                              _AvatarChoiceCard(
                                label: option.label,
                                selected: selected == option.key,
                                disabled: _saving,
                                onTap: () => _select(option.key),
                                child: ColoredBox(
                                  color: AppColors.paperAlt,
                                  child: ProfileAvatarArtwork(option: option),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    if (_saving) ...[
                      const SizedBox(height: 18),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ],
                );
              },
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 46,
                      color: AppColors.inkFaint,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Les avatars GardeFlow sont réservés aux médecins Juniors.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _AvatarChoiceCard extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;
  final Widget child;

  const _AvatarChoiceCard({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.brand : AppColors.line,
              width: selected ? 2.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.brand.withOpacity(0.16),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      child,
                      if (selected)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            width: 25,
                            height: 25,
                            decoration: BoxDecoration(
                              color: AppColors.brand,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 17,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? AppColors.brandDark : AppColors.ink,
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
    );
  }
}
