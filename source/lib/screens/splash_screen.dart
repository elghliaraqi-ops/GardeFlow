import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
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
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _SplashBackdrop(),
            SafeArea(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - value)),
                    child: child,
                  ),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: 520,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _GardeFlowBanner(),
                            const SizedBox(height: 12),
                            const _SplashBrandImage(
                              asset: 'assets/branding/splash_practice.webp',
                              semanticLabel: 'Practice',
                              aspectRatio: 600 / 270,
                            ),
                            const SizedBox(height: 12),
                            const _SplashBrandImage(
                              asset: 'assets/branding/splash_flowsuite.webp',
                              semanticLabel: 'FlowSuite',
                              aspectRatio: 600 / 257,
                            ),
                            const SizedBox(height: 20),
                            _PremiumLoadingBar(animation: _progressAnimation),
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

class _GardeFlowBanner extends StatelessWidget {
  const _GardeFlowBanner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'GardeFlow',
      image: true,
      child: SizedBox(
        width: 520,
        height: 173,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFFFFFFFF),
                      Color(0xFFFEFFFF),
                      Color(0xFFF7FCFF),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: -56,
                bottom: -105,
                child: _GlowCircle(
                  size: 210,
                  color: Color(0x2517CBA1),
                ),
              ),
              const Positioned(
                right: -58,
                bottom: -106,
                child: _GlowCircle(
                  size: 214,
                  color: Color(0x25EF425B),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
                child: Row(
                  children: [
                    SizedBox(
                      width: 139,
                      height: 139,
                      child: Image.asset(
                        'assets/branding/gardeflow_logo.png',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        isAntiAlias: true,
                        gaplessPlayback: true,
                      ),
                    ),
                    const SizedBox(width: 17),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          const TextSpan(
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 72,
                              fontWeight: FontWeight.w800,
                              height: 1,
                              letterSpacing: -3.2,
                            ),
                            children: [
                              TextSpan(
                                text: 'Garde',
                                style: TextStyle(color: Color(0xFF007A4C)),
                              ),
                              TextSpan(
                                text: 'Flow',
                                style: TextStyle(color: Color(0xFFE51B28)),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          softWrap: false,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashBrandImage extends StatelessWidget {
  final String asset;
  final String semanticLabel;
  final double aspectRatio;

  const _SplashBrandImage({
    required this.asset,
    required this.semanticLabel,
    required this.aspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
        width: 520,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}

class _SplashBackdrop extends StatelessWidget {
  const _SplashBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFFDFEFF),
            Color(0xFFF7FBFF),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: -120,
            bottom: -135,
            child: _GlowCircle(
              size: 320,
              color: Color(0x2219B8E8),
            ),
          ),
          Positioned(
            right: -130,
            bottom: -145,
            child: _GlowCircle(
              size: 340,
              color: Color(0x22F23AAE),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
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
}

class _PremiumLoadingBar extends StatelessWidget {
  final Animation<double> animation;

  const _PremiumLoadingBar({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Container(
          width: 250,
          height: 6,
          decoration: BoxDecoration(
            color: const Color(0xFFE9EEF5),
            borderRadius: BorderRadius.circular(99),
          ),
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: animation.value,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF009F69),
                    Color(0xFF119DDF),
                    Color(0xFF6C42F4),
                    Color(0xFFE92892),
                    Color(0xFFF0443D),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
