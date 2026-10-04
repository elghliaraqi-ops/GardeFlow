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
        backgroundColor: const Color(0xFFF7FAF9),
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _SplashBackdrop(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 680),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 14 * (1 - value)),
                          child: child,
                        ),
                      ),
                      child: SizedBox(
                        width: 420,
                        height: 720,
                        child: Column(
                          children: [
                            const _GardeFlowHero(),
                            const SizedBox(height: 22),
                            _LoadingCluster(animation: _progressAnimation),
                            const Spacer(),
                            const _PracticeBrand(),
                            const SizedBox(height: 24),
                            const _FlowSuiteBrand(),
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
    return Semantics(
      label: 'GardeFlow. Le planning pour garder le flow.',
      image: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/splash_gardeflow_mark.png',
            width: 164,
            height: 164,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            gaplessPlayback: true,
          ),
          const SizedBox(height: 4),
          const _GardeFlowWordmark(),
          const SizedBox(height: 8),
          const Text(
            'Le planning pour garder le flow',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFF314858),
              fontSize: 19,
              fontWeight: FontWeight.w500,
              letterSpacing: -0.35,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: 58,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF008D55),
                  Color(0xFF39B778),
                  Color(0xFFFF3348),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GardeFlowWordmark extends StatelessWidget {
  const _GardeFlowWordmark();

  @override
  Widget build(BuildContext context) {
    return const FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Garde',
            style: TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFF087844),
              fontSize: 58,
              fontWeight: FontWeight.w800,
              height: 0.95,
              letterSpacing: -3.0,
            ),
          ),
          Text(
            'Flow',
            style: TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFFEF1823),
              fontSize: 58,
              fontWeight: FontWeight.w800,
              height: 0.95,
              letterSpacing: -3.0,
            ),
          ),
        ],
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
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            color: Color(0xFF7189A8),
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.15,
          ),
        ),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            return Container(
              width: 286,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7EB),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: Colors.white.withOpacity(0.90),
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x160B3E51),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: animation.value,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFF00A768),
                        Color(0xFF36B980),
                        Color(0xFFFF3048),
                      ],
                      stops: [0.0, 0.54, 1.0],
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

class _PracticeBrand extends StatelessWidget {
  const _PracticeBrand();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Practice, éducation médicale',
      image: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/splash_practice_mark.png',
            width: 78,
            height: 78,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
          ),
          const SizedBox(height: 3),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                Color(0xFF1238B7),
                Color(0xFF09A9E8),
                Color(0xFF7D29F3),
              ],
            ).createShader(bounds),
            child: const Text(
              'Practice',
              style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.8,
                height: 1.0,
              ),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'ÉDUCATION MÉDICALE',
            style: TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFF7587A5),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowSuiteBrand extends StatelessWidget {
  const _FlowSuiteBrand();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'FlowSuite. Cette application fait partie de l’écosystème FlowSuite.',
      image: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/branding/splash_flowsuite_mark.png',
                width: 50,
                height: 50,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                isAntiAlias: true,
              ),
              const SizedBox(width: 9),
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    Color(0xFF07549D),
                    Color(0xFF0089E8),
                    Color(0xFFA51CF3),
                    Color(0xFFFF1769),
                    Color(0xFFFFA600),
                  ],
                ).createShader(bounds),
                child: const Text(
                  'FlowSuite',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: Colors.white,
                    fontSize: 31,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.6,
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          const Text(
            'Cette application fait partie de l’écosystème FlowSuite.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFF8292A6),
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'VERSION ${_SplashScreenState._appVersion}',
            style: TextStyle(
              fontFamily: 'Inter',
              color: Color(0xFF97A6B7),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
        ],
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
            Color(0xFFFBFCFC),
            Color(0xFFF5F9F8),
            Color(0xFFF8F6F7),
          ],
          stops: [0.0, 0.52, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: const [
          Positioned(
            top: -155,
            left: -165,
            child: _GlowOrb(
              size: 400,
              color: Color(0x3439D58F),
            ),
          ),
          Positioned(
            top: 160,
            right: -165,
            child: _GlowOrb(
              size: 390,
              color: Color(0x252CA7E3),
            ),
          ),
          Positioned(
            bottom: -170,
            right: -145,
            child: _GlowOrb(
              size: 410,
              color: Color(0x2EFF5465),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -170,
            child: _GlowOrb(
              size: 360,
              color: Color(0x1821C9AF),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

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
              color,
              color.withOpacity(0.34),
              color.withOpacity(0),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
      ),
    );
  }
}
