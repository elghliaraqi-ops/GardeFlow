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
  static const _appVersion = '12.0.0';

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
                    offset: Offset(0, 12 * (1 - value)),
                    child: child,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 650;
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            22,
                            compact ? 12 : 22,
                            22,
                            compact ? 12 : 18,
                          ),
                          child: Column(
                            children: [
                              const _GardeFlowBanner(),
                              SizedBox(height: compact ? 8 : 12),
                              const Text(
                                'Le planning pour garder le flow',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF24394E),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.25,
                                ),
                              ),
                              const Spacer(flex: 5),
                              const _SplashBrandImage(
                                asset: 'assets/branding/splash_practice.webp',
                                semanticLabel: 'Practice',
                                aspectRatio: 600 / 270,
                                width: 300,
                              ),
                              SizedBox(height: compact ? 14 : 22),
                              _PremiumLoadingBar(
                                animation: _progressAnimation,
                              ),
                              const Spacer(flex: 3),
                              const _SplashBrandImage(
                                asset: 'assets/branding/splash_flowsuite.webp',
                                semanticLabel: 'FlowSuite',
                                aspectRatio: 600 / 257,
                                width: 205,
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'Version $_appVersion',
                                style: TextStyle(
                                  color: Color(0xFF7890A6),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ],
                          ),
                        ),
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

class _GardeFlowBanner extends StatelessWidget {
  const _GardeFlowBanner();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'GardeFlow',
      image: true,
      child: SizedBox(
        width: double.infinity,
        height: 150,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.94),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFE5EEF5)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x170B365D),
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Positioned(
                  left: -50,
                  bottom: -105,
                  child: _GlowCircle(
                    size: 220,
                    color: Color(0x2A17CBA1),
                  ),
                ),
                const Positioned(
                  right: -52,
                  bottom: -108,
                  child: _GlowCircle(
                    size: 220,
                    color: Color(0x29EF425B),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 122,
                        height: 122,
                        child: Image.asset(
                          'assets/branding/gardeflow_logo.png',
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          isAntiAlias: true,
                          gaplessPlayback: true,
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text.rich(
                            const TextSpan(
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 78,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                letterSpacing: -3.4,
                              ),
                              children: [
                                TextSpan(
                                  text: 'Garde',
                                  style: TextStyle(
                                    color: Color(0xFF007A4C),
                                  ),
                                ),
                                TextSpan(
                                  text: 'Flow',
                                  style: TextStyle(
                                    color: Color(0xFFE51B28),
                                  ),
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
      ),
    );
  }
}

class _SplashBrandImage extends StatelessWidget {
  final String asset;
  final String semanticLabel;
  final double aspectRatio;
  final double width;

  const _SplashBrandImage({
    required this.asset,
    required this.semanticLabel,
    required this.aspectRatio,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: SizedBox(
        width: width,
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
            Color(0xFFF8FCFF),
            Color(0xFFF2F8FC),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            left: -130,
            bottom: -155,
            child: _GlowCircle(
              size: 350,
              color: Color(0x2319B8E8),
            ),
          ),
          const Positioned(
            right: -145,
            bottom: -165,
            child: _GlowCircle(
              size: 370,
              color: Color(0x22F23AAE),
            ),
          ),
          Positioned(
            top: 180,
            left: 30,
            right: 30,
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0x0017CBA1),
                    Color(0x4017CBA1),
                    Color(0x40119DDF),
                    Color(0x00E92892),
                  ],
                ),
              ),
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
          width: 270,
          height: 7,
          decoration: BoxDecoration(
            color: const Color(0xFFE3EBF3),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: const Color(0xFFD9E4ED)),
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
