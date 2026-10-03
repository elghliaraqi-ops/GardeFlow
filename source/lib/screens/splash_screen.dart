import 'dart:math' as math;

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
            const _ApprovedSplashBackdrop(),
            SafeArea(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(
                            width: 430,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const _GardeFlowBrandBlock(),
                                const SizedBox(height: 46),
                                const _PracticeBrandBlock(),
                                const SizedBox(height: 38),
                                const _FlowSuiteBrandBlock(),
                                const SizedBox(height: 28),
                                _PremiumLoadingBar(
                                  animation: _progressAnimation,
                                ),
                              ],
                            ),
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

class _GardeFlowBrandBlock extends StatelessWidget {
  const _GardeFlowBrandBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BrandIconCard(
          size: 154,
          semanticLabel: 'GardeFlow',
          painter: _GardeFlowIconPainter(),
        ),
        SizedBox(height: 19),
        _GardeFlowWordmark(),
      ],
    );
  }
}

class _PracticeBrandBlock extends StatelessWidget {
  const _PracticeBrandBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BrandIconCard(
          size: 116,
          semanticLabel: 'Practice',
          painter: _PracticeIconPainter(),
        ),
        SizedBox(height: 12),
        _GradientWordmark(
          text: 'Practice',
          fontSize: 47,
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0xFF0A2B8A),
              Color(0xFF0B65D8),
              Color(0xFF18BCE7),
              Color(0xFF6E35EE),
            ],
            stops: [0.0, 0.34, 0.67, 1.0],
          ),
        ),
      ],
    );
  }
}

class _FlowSuiteBrandBlock extends StatelessWidget {
  const _FlowSuiteBrandBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BrandIconCard(
          size: 116,
          semanticLabel: 'FlowSuite',
          painter: _FlowSuiteIconPainter(),
        ),
        SizedBox(height: 12),
        _GradientWordmark(
          text: 'FlowSuite',
          fontSize: 45,
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color(0xFF073C83),
              Color(0xFF0A73D5),
              Color(0xFF642CF1),
              Color(0xFFF20B9C),
              Color(0xFFFF8700),
            ],
            stops: [0.0, 0.27, 0.53, 0.76, 1.0],
          ),
        ),
      ],
    );
  }
}

class _GardeFlowWordmark extends StatelessWidget {
  const _GardeFlowWordmark();

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: const TextSpan(
        style: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: 51,
          height: 0.98,
          fontWeight: FontWeight.w900,
          letterSpacing: -2.4,
        ),
        children: [
          TextSpan(
            text: 'Garde',
            style: TextStyle(color: Color(0xFF087343)),
          ),
          TextSpan(
            text: 'Flow',
            style: TextStyle(color: Color(0xFFEF202B)),
          ),
        ],
      ),
    );
  }
}

class _GradientWordmark extends StatelessWidget {
  final String text;
  final double fontSize;
  final Gradient gradient;

  const _GradientWordmark({
    required this.text,
    required this.fontSize,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(bounds),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: fontSize,
          height: 0.98,
          fontWeight: FontWeight.w900,
          letterSpacing: -2.2,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _BrandIconCard extends StatelessWidget {
  final double size;
  final String semanticLabel;
  final CustomPainter painter;

  const _BrandIconCard({
    required this.size,
    required this.semanticLabel,
    required this.painter,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.085),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(size * 0.22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF83C8F4).withOpacity(0.26),
              blurRadius: size * 0.22,
              spreadRadius: size * 0.02,
              offset: Offset(0, size * 0.055),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.92),
              blurRadius: size * 0.08,
              spreadRadius: size * 0.01,
            ),
          ],
        ),
        child: CustomPaint(
          painter: painter,
          size: Size.square(size),
        ),
      ),
    );
  }
}

class _GardeFlowIconPainter extends CustomPainter {
  const _GardeFlowIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final arm = w * 0.36;
    final overlap = w * 0.045;
    final center = Offset(w / 2, h / 2);
    final corner = Radius.circular(w * 0.115);

    final greenRectTop = RRect.fromRectAndRadius(
      Rect.fromLTWH((w - arm) / 2, 0, arm, h * 0.51 + overlap),
      corner,
    );
    final greenRectLeft = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, (h - arm) / 2, w * 0.51 + overlap, arm),
      corner,
    );
    final redRectRight = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.49 - overlap, (h - arm) / 2,
          w * 0.51 + overlap, arm),
      corner,
    );
    final redRectBottom = RRect.fromRectAndRadius(
      Rect.fromLTWH((w - arm) / 2, h * 0.49 - overlap, arm,
          h * 0.51 + overlap),
      corner,
    );

    canvas.drawRRect(
      greenRectTop,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF13C76A), Color(0xFF00663D)],
        ).createShader(greenRectTop.outerRect),
    );
    canvas.drawRRect(
      greenRectLeft,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF18C972), Color(0xFF00683F)],
        ).createShader(greenRectLeft.outerRect),
    );
    canvas.drawRRect(
      redRectRight,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF2B35), Color(0xFFD30012)],
        ).createShader(redRectRight.outerRect),
    );
    canvas.drawRRect(
      redRectBottom,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF31623), Color(0xFFD40012)],
        ).createShader(redRectBottom.outerRect),
    );

    final clockRadius = w * 0.315;
    canvas.drawCircle(
      center,
      clockRadius,
      Paint()..color = Colors.white,
    );

    final sweepPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.047
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: clockRadius + w * 0.045),
      math.pi * 0.20,
      math.pi * 1.45,
      false,
      sweepPaint,
    );

    final greenSweepPaint = Paint()
      ..color = const Color(0xFF07844D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.027
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: clockRadius + w * 0.005),
      math.pi * 0.84,
      math.pi * 0.92,
      false,
      greenSweepPaint,
    );

    final clockPaint = Paint()
      ..color = const Color(0xFF07864E)
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center,
      Offset(center.dx, center.dy - h * 0.19),
      clockPaint,
    );
    canvas.drawLine(
      center,
      Offset(center.dx + w * 0.16, center.dy + h * 0.105),
      clockPaint,
    );
    canvas.drawCircle(center, w * 0.072, Paint()..color = const Color(0xFF07864E));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PracticeIconPainter extends CustomPainter {
  const _PracticeIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final arm = w * 0.37;
    final radius = Radius.circular(w * 0.12);

    final top = RRect.fromRectAndRadius(
      Rect.fromLTWH((w - arm) / 2, 0, arm, h * 0.54),
      radius,
    );
    final left = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, (h - arm) / 2, w * 0.55, arm),
      radius,
    );
    final right = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.45, (h - arm) / 2, w * 0.55, arm),
      radius,
    );
    final bottom = RRect.fromRectAndRadius(
      Rect.fromLTWH((w - arm) / 2, h * 0.46, arm, h * 0.54),
      radius,
    );

    canvas.drawRRect(
      top,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF02E5E8), Color(0xFF006BE9)],
        ).createShader(top.outerRect),
    );
    canvas.drawRRect(
      left,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF05D5E6), Color(0xFF024AC4)],
        ).createShader(left.outerRect),
    );
    canvas.drawRRect(
      right,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0C6CE7), Color(0xFF9B31F3)],
        ).createShader(right.outerRect),
    );
    canvas.drawRRect(
      bottom,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0345CB), Color(0xFF3812A8)],
        ).createShader(bottom.outerRect),
    );

    final sheetRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.48, h * 0.50),
        width: w * 0.46,
        height: h * 0.49,
      ),
      Radius.circular(w * 0.07),
    );
    canvas.drawRRect(sheetRect, Paint()..color = Colors.white.withOpacity(0.97));
    canvas.drawRRect(
      sheetRect,
      Paint()
        ..color = const Color(0xFF1252B4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.035,
    );

    final clipRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(w * 0.48, h * 0.31),
        width: w * 0.21,
        height: h * 0.075,
      ),
      Radius.circular(w * 0.03),
    );
    canvas.drawRRect(clipRect, Paint()..color = const Color(0xFF1B58B8));

    final linePaint = Paint()
      ..color = const Color(0xFF2257A5)
      ..strokeWidth = w * 0.025
      ..strokeCap = StrokeCap.round;
    for (final dy in [0.43, 0.53, 0.63]) {
      canvas.drawCircle(
        Offset(w * 0.36, h * dy),
        w * 0.014,
        Paint()..color = const Color(0xFF0B69D8),
      );
      canvas.drawLine(
        Offset(w * 0.42, h * dy),
        Offset(w * 0.58, h * dy),
        linePaint,
      );
    }

    final checkCenter = Offset(w * 0.70, h * 0.68);
    canvas.drawCircle(
      checkCenter,
      w * 0.19,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF18D3E6), Color(0xFF0788E8)],
        ).createShader(Rect.fromCircle(center: checkCenter, radius: w * 0.20)),
    );
    canvas.drawCircle(
      checkCenter,
      w * 0.19,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.03,
    );
    final checkPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.045
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final checkPath = Path()
      ..moveTo(w * 0.62, h * 0.68)
      ..lineTo(w * 0.68, h * 0.74)
      ..lineTo(w * 0.79, h * 0.61);
    canvas.drawPath(checkPath, checkPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlowSuiteIconPainter extends CustomPainter {
  const _FlowSuiteIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final arm = w * 0.37;
    final radius = Radius.circular(w * 0.12);

    final top = RRect.fromRectAndRadius(
      Rect.fromLTWH((w - arm) / 2, 0, arm, h * 0.54),
      radius,
    );
    final left = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, (h - arm) / 2, w * 0.55, arm),
      radius,
    );
    final right = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.45, (h - arm) / 2, w * 0.55, arm),
      radius,
    );
    final bottom = RRect.fromRectAndRadius(
      Rect.fromLTWH((w - arm) / 2, h * 0.46, arm, h * 0.54),
      radius,
    );

    canvas.drawRRect(
      top,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF02DDE7), Color(0xFF0B4DD9)],
        ).createShader(top.outerRect),
    );
    canvas.drawRRect(
      left,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0ECFE5), Color(0xFF3142ED), Color(0xFF9D16E7)],
        ).createShader(left.outerRect),
    );
    canvas.drawRRect(
      right,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B23F0), Color(0xFFFF0A86), Color(0xFFFF9500)],
        ).createShader(right.outerRect),
    );
    canvas.drawRRect(
      bottom,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6D21EE), Color(0xFFE90A91), Color(0xFFCB0D5F)],
        ).createShader(bottom.outerRect),
    );

    final center = Offset(w / 2, h / 2);
    final swirlPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.037
      ..strokeCap = StrokeCap.round;

    final radii = [w * 0.30, w * 0.24, w * 0.18];
    final starts = [-0.18, 0.48, 1.12];
    for (var i = 0; i < radii.length; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radii[i]),
        math.pi * starts[i],
        math.pi * 1.30,
        false,
        swirlPaint,
      );
    }

    canvas.drawCircle(
      center,
      w * 0.085,
      Paint()..color = Colors.white.withOpacity(0.17),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
            width: 164,
            height: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF1F6).withOpacity(0.76),
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
                            Color(0xFF0EA85D),
                            Color(0xFF12BCE1),
                            Color(0xFF6A42F4),
                            Color(0xFFF31A68),
                          ],
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

class _ApprovedSplashBackdrop extends StatelessWidget {
  const _ApprovedSplashBackdrop();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: CustomPaint(
        painter: _ApprovedBackdropPainter(),
        size: Size.infinite,
      ),
    );
  }
}

class _ApprovedBackdropPainter extends CustomPainter {
  const _ApprovedBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    canvas.drawRect(
      fullRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0xFFFDFCFF),
          ],
          stops: [0.0, 0.55, 1.0],
        ).createShader(fullRect),
    );

    final leftGlowRect = Rect.fromLTWH(
      -size.width * 0.42,
      size.height * 0.57,
      size.width * 1.15,
      size.height * 0.50,
    );
    canvas.drawOval(
      leftGlowRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x2526D6F1), Color(0x0C37A8FF), Colors.transparent],
        ).createShader(leftGlowRect),
    );

    final rightGlowRect = Rect.fromLTWH(
      size.width * 0.42,
      size.height * 0.60,
      size.width * 1.05,
      size.height * 0.46,
    );
    canvas.drawOval(
      rightGlowRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x22FF7AAE), Color(0x0A905AFF), Colors.transparent],
        ).createShader(rightGlowRect),
    );

    _drawRibbon(
      canvas,
      size,
      startY: 0.63,
      controlY1: 0.78,
      controlY2: 0.89,
      endY: 0.90,
      thickness: 0.055,
      color: const Color(0x2436C7F0),
      fromLeft: true,
    );
    _drawRibbon(
      canvas,
      size,
      startY: 0.69,
      controlY1: 0.83,
      controlY2: 0.90,
      endY: 0.88,
      thickness: 0.040,
      color: const Color(0x252685FF),
      fromLeft: true,
    );
    _drawRibbon(
      canvas,
      size,
      startY: 0.76,
      controlY1: 0.87,
      controlY2: 0.91,
      endY: 0.86,
      thickness: 0.030,
      color: const Color(0x1B26C4E9),
      fromLeft: true,
    );

    _drawRibbon(
      canvas,
      size,
      startY: 0.64,
      controlY1: 0.80,
      controlY2: 0.91,
      endY: 0.90,
      thickness: 0.055,
      color: const Color(0x20FF668A),
      fromLeft: false,
    );
    _drawRibbon(
      canvas,
      size,
      startY: 0.71,
      controlY1: 0.84,
      controlY2: 0.90,
      endY: 0.88,
      thickness: 0.041,
      color: const Color(0x1CEF3D92),
      fromLeft: false,
    );
    _drawRibbon(
      canvas,
      size,
      startY: 0.78,
      controlY1: 0.88,
      controlY2: 0.90,
      endY: 0.86,
      thickness: 0.028,
      color: const Color(0x168E59F5),
      fromLeft: false,
    );
  }

  void _drawRibbon(
    Canvas canvas,
    Size size, {
    required double startY,
    required double controlY1,
    required double controlY2,
    required double endY,
    required double thickness,
    required Color color,
    required bool fromLeft,
  }) {
    final startX = fromLeft ? -size.width * 0.10 : size.width * 1.10;
    final endX = size.width * 0.50;
    final c1X = fromLeft ? size.width * 0.12 : size.width * 0.88;
    final c2X = fromLeft ? size.width * 0.31 : size.width * 0.69;

    final path = Path()
      ..moveTo(startX, size.height * startY)
      ..cubicTo(
        c1X,
        size.height * controlY1,
        c2X,
        size.height * controlY2,
        endX,
        size.height * endY,
      )
      ..cubicTo(
        c2X,
        size.height * (controlY2 + thickness),
        c1X,
        size.height * (controlY1 + thickness),
        startX,
        size.height * (startY + thickness),
      )
      ..close();

    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
