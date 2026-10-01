import 'package:flutter/material.dart';

import '../data/profile_avatars.dart';
import '../services/profile_avatar_service.dart';

class ProfileAvatarArtwork extends StatelessWidget {
  final ProfileAvatarOption option;
  final BoxFit fit;

  const ProfileAvatarArtwork({
    super.key,
    required this.option,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      option.assetPath,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }
}

class ProfileAvatar extends StatefulWidget {
  final String profileId;
  final String initials;
  final bool isJunior;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;
  final BoxFit fit;

  const ProfileAvatar({
    super.key,
    required this.profileId,
    required this.initials,
    required this.isJunior,
    this.radius = 20,
    this.backgroundColor = const Color(0xFFE8EEF6),
    this.foregroundColor = const Color(0xFF17324D),
    this.fit = BoxFit.cover,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId ||
        oldWidget.isJunior != widget.isJunior) {
      _loadIfNeeded();
    }
  }

  void _loadIfNeeded() {
    if (!widget.isJunior || widget.profileId.trim().isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ProfileAvatarService.instance.ensureLoaded().catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isJunior || widget.profileId.trim().isEmpty) {
      return _initialsAvatar();
    }

    return AnimatedBuilder(
      animation: ProfileAvatarService.instance,
      builder: (context, _) {
        final key = ProfileAvatarService.instance.avatarKeyFor(widget.profileId);
        final option = profileAvatarByKey(key);
        if (option == null) return _initialsAvatar();

        final size = widget.radius * 2;
        return SizedBox.square(
          dimension: size,
          child: ClipOval(
            child: ColoredBox(
              color: widget.backgroundColor,
              child: Transform.translate(
                offset: Offset(
                  widget.radius * option.circleOffsetX,
                  widget.radius * option.circleOffsetY,
                ),
                child: Transform.scale(
                  scale: option.circleScale,
                  alignment: Alignment.center,
                  child: ProfileAvatarArtwork(option: option, fit: widget.fit),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _initialsAvatar() {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor,
      child: Text(
        widget.initials.trim().isEmpty ? 'Dr' : widget.initials.trim(),
        maxLines: 1,
        style: TextStyle(
          color: widget.foregroundColor,
          fontSize: widget.radius * 0.62,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
