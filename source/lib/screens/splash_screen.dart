import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        transitionDuration: const Duration(milliseconds: 360),
        pageBuilder: (_, animation, __) =>
            signedIn ? const HomeScreen() : const AuthScreen(),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFFFBFCFE),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _goNext,
        child: Scaffold(
          backgroundColor: const Color(0xFFFBFCFE),
          body: MediaQuery.withNoTextScaling(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const _ReferenceBackdrop(),
                SafeArea(
                  minimum: EdgeInsets.zero,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 10 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: _ReferenceComposition(
                      progress: _progressAnimation,
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

class _ReferenceComposition extends StatelessWidget {
  static const double _referenceWidth = 941;
  static const double _referenceHeight = 1672;

  final Animation<double> progress;

  const _ReferenceComposition({required this.progress});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final widthScale = width / _referenceWidth;
        final heightScale = height / _referenceHeight;
        final scale = math.min(widthScale, heightScale * 1.18);

        double sy(double y) => y * heightScale;
        double ss(double value) => value * scale;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Ces trois assets sont régénérés directement depuis les logos
              // originaux fournis, sous de nouveaux noms pour éviter tout
              // reliquat de cache Web des fichiers précédemment corrompus.
              Positioned(
                top: sy(112),
                left: 0,
                right: 0,
                child: Center(
                  child: Image.asset(
                    'assets/branding/splash_gardeflow_mark_clean.webp',
                    width: ss(435),
                    height: ss(435),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    isAntiAlias: true,
                    gaplessPlayback: true,
                  ),
                ),
              ),

              Positioned(
                top: sy(524),
                left: ss(30),
                right: ss(30),
                child: _GardeFlowWordmark(scale: scale),
              ),
              Positioned(
                top: sy(670),
                left: ss(20),
                right: ss(20),
                child: Text(
                  'Le planning pour garder le flow',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: const Color(0xFF315570),
                    fontSize: ss(40),
                    fontWeight: FontWeight.w500,
                    letterSpacing: ss(-0.7),
                    height: 1,
                  ),
                ),
              ),
              Positioned(
                top: sy(739),
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: ss(129),
                    height: ss(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(ss(99)),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF008B58),
                          Color(0xFF35B77A),
                          Color(0xFFFF1F38),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                top: sy(807),
                left: ss(20),
                right: ss(20),
                child: Text(
                  'PRÉPARATION DE VOTRE ESPACE',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: const Color(0xFF7890B1),
                    fontSize: ss(23.5),
                    fontWeight: FontWeight.w700,
                    letterSpacing: ss(4.2),
                    height: 1,
                  ),
                ),
              ),
              Positioned(
                top: sy(853),
                left: 0,
                right: 0,
                child: Center(
                  child: _ReferenceProgressBar(
                    animation: progress,
                    scale: scale,
                  ),
                ),
              ),

              Positioned(
                top: sy(948),
                left: 0,
                right: 0,
                child: Center(
                  child: Image.asset(
                    'assets/branding/splash_practice_mark_clean.webp',
                    width: ss(232),
                    height: ss(232),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    isAntiAlias: true,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Positioned(
                top: sy(1171),
                left: ss(80),
                right: ss(80),
                child: _PracticeWordmark(scale: scale),
              ),
              Positioned(
                top: sy(1266),
                left: ss(20),
                right: ss(20),
                child: Text(
                  'ÉDUCATION MÉDICALE',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: const Color(0xFF748AA8),
                    fontSize: ss(25),
                    fontWeight: FontWeight.w700,
                    letterSpacing: ss(6),
                    height: 1,
                  ),
                ),
              ),

              Positioned(
                top: sy(1348),
                left: 0,
                right: 0,
                child: _FlowSuiteLockup(scale: scale),
              ),
              Positioned(
                top: sy(1508),
                left: ss(35),
                right: ss(35),
                child: Text(
                  'Cette application fait partie de l’écosystème FlowSuite.',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: const Color(0xFF8396B0),
                    fontSize: ss(24.5),
                    fontWeight: FontWeight.w500,
                    height: 1,
                  ),
                ),
              ),
              Positioned(
                top: sy(1570),
                left: ss(20),
                right: ss(20),
                child: Text(
                  'VERSION ${_SplashScreenState._appVersion}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: const Color(0xFF8EA1BC),
                    fontSize: ss(20),
                    fontWeight: FontWeight.w700,
                    letterSpacing: ss(7.2),
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GardeFlowWordmark extends StatelessWidget {
  final double scale;

  const _GardeFlowWordmark({required this.scale});

  @override
  Widget build(BuildContext context) {
    final fontSize = 128 * scale;
    final spacing = -6.2 * scale;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: spacing,
            height: 0.92,
          ),
          children: const [
            TextSpan(
              text: 'Garde',
              style: TextStyle(color: Color(0xFF087C4B)),
            ),
            TextSpan(
              text: 'Flow',
              style: TextStyle(color: Color(0xFFF01826)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReferenceProgressBar extends StatelessWidget {
  final Animation<double> animation;
  final double scale;

  const _ReferenceProgressBar({
    required this.animation,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final radius = 999 * scale;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final value =
            (0.035 + animation.value * 0.965).clamp(0.0, 1.0).toDouble();
        return Container(
          width: 706 * scale,
          height: 50 * scale,
          padding: EdgeInsets.all(4 * scale),
          decoration: BoxDecoration(
            color: const Color(0x5EC9DBE9),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withOpacity(0.94),
              width: 3.2 * scale,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF21D29A).withOpacity(0.20),
                blurRadius: 20 * scale,
                spreadRadius: 1 * scale,
                offset: Offset(-4 * scale, 2 * scale),
              ),
              BoxShadow(
                color: const Color(0xFFFF4568).withOpacity(0.09),
                blurRadius: 16 * scale,
                offset: Offset(5 * scale, 1 * scale),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFF00C879),
                      Color(0xFF02A96C),
                      Color(0xFF92B8A7),
                      Color(0xFFFF5771),
                    ],
                    stops: [0.0, 0.42, 0.68, 1.0],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PracticeWordmark extends StatelessWidget {
  final double scale;

  const _PracticeWordmark({required this.scale});

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF1736B8),
            Color(0xFF087FEB),
            Color(0xFF8C25F3),
          ],
          stops: [0.0, 0.58, 1.0],
        ).createShader(bounds),
        child: Text(
          'Practice',
          style: TextStyle(
            fontFamily: 'Inter',
            color: Colors.white,
            fontSize: 80 * scale,
            fontWeight: FontWeight.w800,
            letterSpacing: -4 * scale,
            height: 0.95,
          ),
        ),
      ),
    );
  }
}

class _FlowSuiteLockup extends StatelessWidget {
  final double scale;

  const _FlowSuiteLockup({required this.scale});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            'assets/branding/splash_flowsuite_mark_clean.webp',
            width: 157 * scale,
            height: 157 * scale,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            gaplessPlayback: true,
          ),
          SizedBox(width: 2 * scale),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFF0750AE),
                Color(0xFF078DE9),
                Color(0xFF8B28EC),
                Color(0xFFFF1668),
                Color(0xFFFFA10A),
              ],
              stops: [0.0, 0.30, 0.55, 0.78, 1.0],
            ).createShader(bounds),
            child: Text(
              'FlowSuite',
              style: TextStyle(
                fontFamily: 'Inter',
                color: Colors.white,
                fontSize: 77 * scale,
                fontWeight: FontWeight.w800,
                letterSpacing: -4 * scale,
                height: 0.94,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceBackdrop extends StatelessWidget {
  const _ReferenceBackdrop();

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: CustomPaint(
        painter: _ReferenceBackdropPainter(),
      ),
    );
  }
}

class _ReferenceBackdropPainter extends CustomPainter {
  const _ReferenceBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFBFCFE),
    );

    void orb({
      required Offset center,
      required double radius,
      required Color color,
    }) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color,
            color.withOpacity(color.opacity * 0.55),
            color.withOpacity(0),
          ],
          stops: const [0.0, 0.54, 1.0],
        ).createShader(rect);
      canvas.drawCircle(center, radius, paint);
    }

    final w = size.width;
    final h = size.height;

    // Courbes pastel très légères de la maquette, volontairement derrière
    // tout le contenu pour conserver le fond blanc premium.
    orb(
      center: Offset(-0.06 * w, 0.04 * h),
      radius: 0.55 * w,
      color: const Color(0x2639E1AF),
    );
    orb(
      center: Offset(1.04 * w, 0.20 * h),
      radius: 0.55 * w,
      color: const Color(0x252BAAF3),
    );
    orb(
      center: Offset(-0.14 * w, 0.66 * h),
      radius: 0.58 * w,
      color: const Color(0x1B3FD7FF),
    );
    orb(
      center: Offset(-0.08 * w, 0.82 * h),
      radius: 0.50 * w,
      color: const Color(0x20FF70A8),
    );
    orb(
      center: Offset(1.08 * w, 0.72 * h),
      radius: 0.60 * w,
      color: const Color(0x1B76BFFF),
    );
    orb(
      center: Offset(1.03 * w, 1.01 * h),
      radius: 0.56 * w,
      color: const Color(0x18FF7B9C),
    );
  }

  @override
  bool shouldRepaint(covariant _ReferenceBackdropPainter oldDelegate) => false;
}
