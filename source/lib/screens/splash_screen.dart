import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/screen_decor.dart';
import '../theme/widgets.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _splashDuration = Duration(milliseconds: 3200);
  static const _progressDuration = Duration(milliseconds: 2900);

  bool _navigated = false;
  late final AnimationController _progressController;
  late final Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: _progressDuration,
    );
    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOutCubic,
    );
    _progressController.forward();
    Future.delayed(_splashDuration, _goNext);
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final signedIn = context.read<AppState>().currentUser != null;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        pageBuilder: (_, animation, __) =>
            signedIn ? const HomeScreen() : const AuthScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _goNext,
      child: DecorScaffold(
        scene: ScreenDecorScene.splash,
        backgroundColor: const Color(0xFFF9FCFF),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _SplashBackdrop(),
            SafeArea(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 850),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 16 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 22,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: 430,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _GardeFlowHero(),
                            const SizedBox(height: 16),
                            _PremiumLoadingBar(
                              animation: _progressAnimation,
                            ),
                            const SizedBox(height: 36),
                            const _BrandBanner(
                              asset: 'assets/branding/practice_banner.webp',
                              width: 320,
                              height: 108,
                              semanticLabel: 'Practice',
                            ),
                            const SizedBox(height: 24),
                            Container(
                              width: 128,
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Color(0x332D6FD4),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            const _BrandBanner(
                              asset: 'assets/branding/flowsuite_banner.webp',
                              width: 320,
                              height: 100,
                              semanticLabel: 'FlowSuite',
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'UN ÉCOSYSTÈME. UN MÊME FLOW.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'SpaceGrotesk',
                                fontSize: 10,
                                height: 1.2,
                                letterSpacing: 2.15,
                                color: Color(0xFF6A7893),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GardeFlowHero extends StatelessWidget {
  const _GardeFlowHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.78),
            borderRadius: BorderRadius.circular(34),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F4AA7E8),
                blurRadius: 28,
                spreadRadius: 2,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const GardeFlowLogo(size: 132),
        ),
        const SizedBox(height: 20),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: 49,
              height: 0.98,
              fontWeight: FontWeight.w900,
              letterSpacing: -2.1,
            ),
            children: [
              TextSpan(
                text: 'Garde',
                style: TextStyle(color: Color(0xFF087044)),
              ),
              TextSpan(
                text: 'Flow',
                style: TextStyle(color: Color(0xFFE11D2E)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'LE PLANNING DE GARDE POUR GARDER LE FLOW',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontSize: 9.8,
            height: 1.25,
            letterSpacing: 1.75,
            color: Color(0xFF607268),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PremiumLoadingBar extends StatelessWidget {
  final Animation<double> animation;

  const _PremiumLoadingBar({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement de GardeFlow',
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          return SizedBox(
            width: 196,
            height: 6,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EFF4).withOpacity(0.82),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: animation.value,
                    heightFactor: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        gradient: const LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color(0xFF08A861),
                            Color(0xFF18B9C8),
                            Color(0xFF7A57F5),
                            Color(0xFFE83B58),
                          ],
                          stops: [0.0, 0.36, 0.68, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BrandBanner extends StatelessWidget {
  final String asset;
  final double width;
  final double height;
  final String semanticLabel;

  const _BrandBanner({
    required this.asset,
    required this.width,
    required this.height,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

class _SplashBackdrop extends StatelessWidget {
  const _SplashBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFFFFF),
                Color(0xFFF9FCFF),
                Color(0xFFFFFBFD),
              ],
              stops: [0.0, 0.52, 1.0],
            ),
          ),
        ),
        Positioned(
          top: -180,
          left: -220,
          child: _GlowOrb(
            size: 440,
            colors: [
              Color(0x3D61E6D2),
              Color(0x1261E6D2),
              Colors.transparent,
            ],
          ),
        ),
        Positioned(
          bottom: -220,
          right: -230,
          child: _GlowOrb(
            size: 500,
            colors: [
              Color(0x34F58AB1),
              Color(0x1A9B77FF),
              Colors.transparent,
            ],
          ),
        ),
        Positioned(
          top: -150,
          right: -120,
          child: Container(
            width: 390,
            height: 390,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF70BFEA).withOpacity(0.08),
                width: 34,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 80,
          left: -170,
          child: Container(
            width: 360,
            height: 360,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF48CBB7).withOpacity(0.08),
                width: 28,
              ),
            ),
          ),
        ),
        const Positioned(
          top: 44,
          right: 18,
          child: Opacity(
            opacity: 0.038,
            child: _MedicalCrossMark(size: 172),
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final List<Color> colors;

  const _GlowOrb({required this.size, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
      ),
    );
  }
}

class _MedicalCrossMark extends StatelessWidget {
  final double size;

  const _MedicalCrossMark({required this.size});

  @override
  Widget build(BuildContext context) {
    final thickness = size * 0.38;
    final radius = BorderRadius.circular(size * 0.13);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: thickness,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFF2A83D9),
              borderRadius: radius,
            ),
          ),
          Container(
            width: size,
            height: thickness,
            decoration: BoxDecoration(
              color: const Color(0xFF2A83D9),
              borderRadius: radius,
            ),
          ),
        ],
      ),
    );
  }
}
