import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

enum ScreenDecorScene {
  home,
  planning,
  onCall,
  practice,
  news,
  directory,
  admin,
  settings,
  profile,
  auth,
  notifications,
  announcements,
  audit,
  splash,
}

extension ScreenDecorSceneVisuals on ScreenDecorScene {
  Color get accent {
    switch (this) {
      case ScreenDecorScene.home:
      case ScreenDecorScene.profile:
      case ScreenDecorScene.settings:
      case ScreenDecorScene.splash:
        return AppColors.brand;
      case ScreenDecorScene.planning:
        return AppColors.info;
      case ScreenDecorScene.onCall:
        return AppColors.urg24h;
      case ScreenDecorScene.practice:
        return AppColors.cyan;
      case ScreenDecorScene.news:
        return AppColors.violet;
      case ScreenDecorScene.directory:
        return const Color(0xFF40C7B2);
      case ScreenDecorScene.admin:
        return AppColors.warning;
      case ScreenDecorScene.auth:
        return AppColors.brandBright;
      case ScreenDecorScene.notifications:
        return const Color(0xFFF5A84F);
      case ScreenDecorScene.announcements:
        return const Color(0xFF5AA8FF);
      case ScreenDecorScene.audit:
        return const Color(0xFF9A7BFF);
    }
  }

  IconData get primaryIcon {
    switch (this) {
      case ScreenDecorScene.home:
        return Icons.local_hospital_rounded;
      case ScreenDecorScene.planning:
        return Icons.calendar_month_rounded;
      case ScreenDecorScene.onCall:
        return Icons.emergency_rounded;
      case ScreenDecorScene.practice:
        return Icons.stethoscope_rounded;
      case ScreenDecorScene.news:
        return Icons.newspaper_rounded;
      case ScreenDecorScene.directory:
        return Icons.contact_phone_rounded;
      case ScreenDecorScene.admin:
        return Icons.admin_panel_settings_rounded;
      case ScreenDecorScene.settings:
        return Icons.tune_rounded;
      case ScreenDecorScene.profile:
        return Icons.badge_rounded;
      case ScreenDecorScene.auth:
        return Icons.health_and_safety_rounded;
      case ScreenDecorScene.notifications:
        return Icons.notifications_active_rounded;
      case ScreenDecorScene.announcements:
        return Icons.campaign_rounded;
      case ScreenDecorScene.audit:
        return Icons.fact_check_rounded;
      case ScreenDecorScene.splash:
        return Icons.medical_services_rounded;
    }
  }

  IconData get secondaryIcon {
    switch (this) {
      case ScreenDecorScene.home:
        return Icons.favorite_rounded;
      case ScreenDecorScene.planning:
        return Icons.schedule_rounded;
      case ScreenDecorScene.onCall:
        return Icons.monitor_heart_rounded;
      case ScreenDecorScene.practice:
        return Icons.medical_information_rounded;
      case ScreenDecorScene.news:
        return Icons.auto_awesome_rounded;
      case ScreenDecorScene.directory:
        return Icons.phone_in_talk_rounded;
      case ScreenDecorScene.admin:
        return Icons.shield_rounded;
      case ScreenDecorScene.settings:
        return Icons.settings_suggest_rounded;
      case ScreenDecorScene.profile:
        return Icons.person_rounded;
      case ScreenDecorScene.auth:
        return Icons.lock_rounded;
      case ScreenDecorScene.notifications:
        return Icons.notifications_rounded;
      case ScreenDecorScene.announcements:
        return Icons.forum_rounded;
      case ScreenDecorScene.audit:
        return Icons.history_rounded;
      case ScreenDecorScene.splash:
        return Icons.favorite_rounded;
    }
  }

  bool get showPhoto =>
      this == ScreenDecorScene.auth || this == ScreenDecorScene.splash;

  bool get showLogo =>
      this == ScreenDecorScene.home ||
      this == ScreenDecorScene.profile ||
      this == ScreenDecorScene.settings;
}

class ScreenDecorBackdrop extends StatelessWidget {
  final ScreenDecorScene scene;
  final Widget child;
  final Color? baseColor;

  const ScreenDecorBackdrop({
    super.key,
    required this.scene,
    required this.child,
    this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = scene.accent;
    final dark = AppColors.isDarkMode;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: baseColor ?? AppColors.paper),
        if (scene.showPhoto)
          IgnorePointer(
            child: Opacity(
              opacity: dark ? .12 : .065,
              child: Image.asset(
                'assets/branding/login_urgences.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withOpacity(dark ? .13 : .09),
                  Colors.transparent,
                  accent.withOpacity(dark ? .055 : .035),
                ],
                stops: const [0, .52, 1],
              ),
            ),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _ScreenDecorPatternPainter(
              color: accent.withOpacity(dark ? .075 : .055),
            ),
          ),
        ),
        IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                top: -50,
                right: -42,
                child: Transform.rotate(
                  angle: -.16,
                  child: Icon(
                    scene.primaryIcon,
                    size: 205,
                    color: accent.withOpacity(dark ? .07 : .055),
                  ),
                ),
              ),
              Positioned(
                bottom: 72,
                left: -30,
                child: Transform.rotate(
                  angle: .17,
                  child: Icon(
                    scene.secondaryIcon,
                    size: 130,
                    color: accent.withOpacity(dark ? .052 : .042),
                  ),
                ),
              ),
              Positioned(
                top: 104,
                left: -86,
                child: _GlowOrb(
                  size: 190,
                  color: accent.withOpacity(dark ? .09 : .065),
                ),
              ),
              Positioned(
                bottom: -72,
                right: -52,
                child: _GlowOrb(
                  size: 210,
                  color: accent.withOpacity(dark ? .08 : .055),
                ),
              ),
              if (scene.showLogo)
                Positioned(
                  right: 18,
                  bottom: 22,
                  child: Opacity(
                    opacity: dark ? .055 : .04,
                    child: Image.asset(
                      'assets/branding/gardeflow_logo.png',
                      width: 118,
                      height: 118,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0)],
          ),
        ),
      );
}

class _ScreenDecorPatternPainter extends CustomPainter {
  final Color color;

  const _ScreenDecorPatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.15
      ..strokeCap = StrokeCap.round;

    const step = 54.0;
    for (double y = 30; y < size.height; y += step) {
      final row = (y / step).floor();
      for (double x = row.isEven ? 24 : 50;
          x < size.width;
          x += step * 1.65) {
        canvas.drawCircle(Offset(x, y), 1.4, paint);
      }
    }

    final crossPaint = Paint()
      ..color = color.withOpacity(.72)
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round;
    final crosses = <Offset>[
      Offset(size.width * .14, size.height * .18),
      Offset(size.width * .84, size.height * .31),
      Offset(size.width * .22, size.height * .67),
      Offset(size.width * .76, size.height * .82),
    ];
    for (final c in crosses) {
      const d = 6.0;
      canvas.drawLine(
        Offset(c.dx - d, c.dy),
        Offset(c.dx + d, c.dy),
        crossPaint,
      );
      canvas.drawLine(
        Offset(c.dx, c.dy - d),
        Offset(c.dx, c.dy + d),
        crossPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScreenDecorPatternPainter oldDelegate) =>
      oldDelegate.color != color;
}

class DecorScaffold extends StatelessWidget {
  final ScreenDecorScene scene;
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final FloatingActionButtonAnimator? floatingActionButtonAnimator;
  final List<Widget>? persistentFooterButtons;
  final AlignmentDirectional persistentFooterAlignment;
  final Widget? drawer;
  final DrawerCallback? onDrawerChanged;
  final Widget? endDrawer;
  final DrawerCallback? onEndDrawerChanged;
  final Widget? bottomNavigationBar;
  final Widget? bottomSheet;
  final Color? backgroundColor;
  final bool? resizeToAvoidBottomInset;
  final bool primary;
  final DragStartBehavior drawerDragStartBehavior;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final Color? drawerScrimColor;
  final double? drawerEdgeDragWidth;
  final bool drawerEnableOpenDragGesture;
  final bool endDrawerEnableOpenDragGesture;
  final String? restorationId;

  const DecorScaffold({
    super.key,
    required this.scene,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.floatingActionButtonAnimator,
    this.persistentFooterButtons,
    this.persistentFooterAlignment = AlignmentDirectional.centerEnd,
    this.drawer,
    this.onDrawerChanged,
    this.endDrawer,
    this.onEndDrawerChanged,
    this.bottomNavigationBar,
    this.bottomSheet,
    this.backgroundColor,
    this.resizeToAvoidBottomInset,
    this.primary = true,
    this.drawerDragStartBehavior = DragStartBehavior.start,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.drawerScrimColor,
    this.drawerEdgeDragWidth,
    this.drawerEnableOpenDragGesture = true,
    this.endDrawerEnableOpenDragGesture = true,
    this.restorationId,
  });

  @override
  Widget build(BuildContext context) {
    return ScreenDecorBackdrop(
      scene: scene,
      baseColor: backgroundColor ?? AppColors.paper,
      child: Scaffold(
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
        floatingActionButtonAnimator: floatingActionButtonAnimator,
        persistentFooterButtons: persistentFooterButtons,
        persistentFooterAlignment: persistentFooterAlignment,
        drawer: drawer,
        onDrawerChanged: onDrawerChanged,
        endDrawer: endDrawer,
        onEndDrawerChanged: onEndDrawerChanged,
        bottomNavigationBar: bottomNavigationBar,
        bottomSheet: bottomSheet,
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        primary: primary,
        drawerDragStartBehavior: drawerDragStartBehavior,
        extendBody: extendBody,
        extendBodyBehindAppBar: extendBodyBehindAppBar,
        drawerScrimColor: drawerScrimColor,
        drawerEdgeDragWidth: drawerEdgeDragWidth,
        drawerEnableOpenDragGesture: drawerEnableOpenDragGesture,
        endDrawerEnableOpenDragGesture: endDrawerEnableOpenDragGesture,
        restorationId: restorationId,
      ),
    );
  }
}

class DecorSectionBanner extends StatelessWidget {
  final ScreenDecorScene scene;
  final String title;
  final String subtitle;
  final IconData? icon;
  final Widget? trailing;

  const DecorSectionBanner({
    super.key,
    required this.scene,
    required this.title,
    required this.subtitle,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final accent = scene.accent;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(15, 15, 11, 15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(AppColors.navy, accent, .18) ?? AppColors.navy,
              Color.lerp(AppColors.brandDark, accent, .48) ?? accent,
            ],
          ),
          border: Border.all(color: accent.withOpacity(.28)),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(.15),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              right: -20,
              top: -34,
              child: Transform.rotate(
                angle: -.18,
                child: Icon(
                  scene.primaryIcon,
                  size: 116,
                  color: Colors.white.withOpacity(.075),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.13),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(.18)),
                  ),
                  child: Icon(
                    icon ?? scene.primaryIcon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'SpaceGrotesk',
                          fontSize: 18.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(.78),
                          fontSize: 10.5,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DecorIconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  const DecorIconAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.12),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withOpacity(.16)),
          ),
          child: Icon(
            icon,
            color: Colors.white.withOpacity(onTap == null ? .45 : .95),
            size: 20,
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class DecorSheetLead extends StatelessWidget {
  final ScreenDecorScene scene;
  final String title;
  final String subtitle;
  final IconData? icon;

  const DecorSheetLead({
    super.key,
    required this.scene,
    required this.title,
    required this.subtitle,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final accent = scene.accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.withOpacity(.18), AppColors.card.withOpacity(.92)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withOpacity(.24)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withOpacity(.17),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon ?? scene.primaryIcon, color: accent, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.ink,
                    fontFamily: 'SpaceGrotesk',
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.inkSoft,
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
