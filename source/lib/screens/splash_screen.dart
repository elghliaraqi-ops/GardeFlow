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
        backgroundColor: const Color(0xFFF4F7F6),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _ModernSplashBackdrop(),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 700;
                  final veryCompact = constraints.maxHeight < 610;
                  final horizontalPadding = constraints.maxWidth < 370 ? 20.0 : 28.0;

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          compact ? 8 : 18,
                          horizontalPadding,
                          compact ? 10 : 18,
                        ),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(milliseconds: 720),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, 16 * (1 - value)),
                                child: Transform.scale(
                                  scale: 0.985 + (0.015 * value),
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: Column(
                            children: [
                              Expanded(
                                flex: veryCompact ? 5 : 6,
                                child: Center(
                                  child: _HeroBrand(compact: compact),
                                ),
                              ),
                              _PracticeModule(compact: compact),
                              SizedBox(height: compact ? 16 : 24),
                              _LoadingCluster(animation: _progressAnimation),
                              SizedBox(height: compact ? 15 : 22),
                              const _FlowSuiteFooter(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBrand extends StatelessWidget {
  final bool compact;

  const _HeroBrand({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'GardeFlow. Avec vous, à chaque garde.',
      image: true,
      child: SizedBox(
        width: double.infinity,
        height: compact ? 185 : 225,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 22,
              right: 22,
              top: compact ? 22 : 28,
              bottom: compact ? 8 : 12,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.8,
                    colors: [
                      Color(0x3DFFFFFF),
                      Color(0x12FFFFFF),
                      Color(0x00FFFFFF),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/branding/splash_gardeflow_exact.webp',
                  width: compact ? 315 : 360,
                  height: compact ? 112 : 138,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  isAntiAlias: true,
                  gaplessPlayback: true,
                ),
                SizedBox(height: compact ? 8 : 12),
                const Text(
                  'AVEC VOUS, À CHAQUE GARDE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: Color(0xFF273A42),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.85,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 11),
                Container(
                  width: 48,
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF00985F),
                        Color(0xFF55B997),
                        Color(0xFFE33A45),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PracticeModule extends StatelessWidget {
  final bool compact;

  const _PracticeModule({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Practice, éducation médicale',
      image: true,
      child: Container(
        width: compact ? 245 : 270,
        padding: EdgeInsets.fromLTRB(
          20,
          compact ? 10 : 13,
          20,
          compact ? 10 : 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.72),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withOpacity(0.92),
            width: 1.2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x100B2A36),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/branding/splash_practice.webp',
              width: compact ? 182 : 205,
              height: compact ? 62 : 72,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              gaplessPlayback: true,
            ),
            const SizedBox(height: 3),
            const Text(
              'ÉDUCATION MÉDICALE',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Inter',
                color: Color(0xFF6E7F87),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCluster extends StatelessWidget {
  final Animation<double> animation;

  const _LoadingCluster({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'PRÉPARATION DE VOTRE ESPACE',
          style: TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFF7C8B91),
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            return Container(
              width: 238,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFDDE5E3),
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
                        Color(0xFF008E59),
                        Color(0xFF20A77A),
                        Color(0xFFE13743),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FlowSuiteFooter extends StatelessWidget {
  const _FlowSuiteFooter();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FlowSuite. Cette application fait partie de l’écosystème FlowSuite.',
      image: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/splash_flowsuite.webp',
            width: 138,
            height: 52,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            gaplessPlayback: true,
          ),
          const SizedBox(height: 2),
          const Text(
            'Cette application fait partie de l’écosystème FlowSuite.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFF798A91),
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'VERSION ${_SplashScreenState._appVersion}',
            style: TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFFA0ADB2),
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModernSplashBackdrop extends StatelessWidget {
  const _ModernSplashBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF9FBFA),
            Color(0xFFF1F6F4),
            Color(0xFFF6F4F5),
          ],
          stops: [0.0, 0.54, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: const [
          Positioned(
            top: -140,
            left: -150,
            child: _SoftOrb(
              size: 360,
              inner: Color(0x2B31C38B),
            ),
          ),
          Positioned(
            right: -170,
            bottom: -145,
            child: _SoftOrb(
              size: 390,
              inner: Color(0x27E85762),
            ),
          ),
          Positioned(
            right: -95,
            top: 180,
            child: _SoftOrb(
              size: 230,
              inner: Color(0x171F9DD3),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftOrb extends StatelessWidget {
  final double size;
  final Color inner;

  const _SoftOrb({required this.size, required this.inner});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              inner,
              inner.withOpacity(0.38),
              inner.withOpacity(0),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}
