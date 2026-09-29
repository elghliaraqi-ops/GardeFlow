import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/doctor_visual_preference.dart';
import 'app_theme.dart';

enum DoctorAvatarShape { circle, roundedSquare }

/// Illustration locale et légère du médecin sélectionné.
/// Aucun portrait externe n'est téléchargé et aucune donnée de santé n'est utilisée.
class DoctorAvatar extends StatefulWidget {
  final double size;
  final String? gender;
  final DoctorAvatarShape shape;
  final bool showBorder;
  final bool showOnlineDot;

  const DoctorAvatar({
    super.key,
    this.size = 44,
    this.gender,
    this.shape = DoctorAvatarShape.circle,
    this.showBorder = true,
    this.showOnlineDot = false,
  });

  @override
  State<DoctorAvatar> createState() => _DoctorAvatarState();
}

class _DoctorAvatarState extends State<DoctorAvatar> {
  @override
  void initState() {
    super.initState();
    DoctorVisualPreference.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.gender != null) return _avatar(widget.gender!);
    return ValueListenableBuilder<String>(
      valueListenable: DoctorVisualPreference.gender,
      builder: (_, gender, __) => _avatar(gender),
    );
  }

  Widget _avatar(String gender) {
    final radius = widget.shape == DoctorAvatarShape.circle
        ? BorderRadius.circular(widget.size)
        : BorderRadius.circular(widget.size * 0.27);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFEAF9F1), Color(0xFF8AD7B1)],
            ),
            border: widget.showBorder
                ? Border.all(color: Colors.white.withOpacity(0.92), width: 2)
                : null,
            boxShadow: widget.showBorder
                ? [
                    BoxShadow(
                      color: AppColors.brandDark.withOpacity(0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(painter: _DoctorPortraitPainter(gender: gender)),
        ),
        if (widget.showOnlineDot)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: widget.size * 0.24,
              height: widget.size * 0.24,
              decoration: BoxDecoration(
                color: AppColors.brandBright,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.paper, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _DoctorPortraitPainter extends CustomPainter {
  final String gender;
  const _DoctorPortraitPainter({required this.gender});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final female = gender == 'female';

    final shadow = Paint()..color = const Color(0x22002B1C);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.93),
        width: w * 0.86,
        height: h * 0.28,
      ),
      shadow,
    );

    final coat = Paint()..color = const Color(0xFFF8FBFA);
    final scrub = Paint()..color = const Color(0xFF0B7D59);
    final skin = Paint()..color = const Color(0xFFF0B58F);
    final skinShade = Paint()..color = const Color(0xFFD88E69);
    final hair = Paint()
      ..color = female ? const Color(0xFF4B2D24) : const Color(0xFF2E241F);
    final dark = Paint()..color = const Color(0xFF17332A);

    // Épaules / blouse.
    final body = Path()
      ..moveTo(w * 0.16, h)
      ..quadraticBezierTo(w * 0.20, h * 0.72, w * 0.42, h * 0.68)
      ..lineTo(w * 0.58, h * 0.68)
      ..quadraticBezierTo(w * 0.80, h * 0.72, w * 0.84, h)
      ..close();
    canvas.drawPath(body, coat);

    final v = Path()
      ..moveTo(w * 0.39, h * 0.70)
      ..lineTo(w * 0.50, h * 0.91)
      ..lineTo(w * 0.61, h * 0.70)
      ..close();
    canvas.drawPath(v, scrub);

    // Cou.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.43, h * 0.57, w * 0.14, h * 0.17),
        Radius.circular(w * 0.05),
      ),
      skinShade,
    );

    // Cheveux arrière pour le profil féminin.
    if (female) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.42),
          width: w * 0.55,
          height: h * 0.64,
        ),
        hair,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * 0.30, h * 0.58),
          width: w * 0.22,
          height: h * 0.42,
        ),
        hair,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * 0.70, h * 0.58),
          width: w * 0.22,
          height: h * 0.42,
        ),
        hair,
      );
    }

    // Visage.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.43),
        width: w * 0.38,
        height: h * 0.46,
      ),
      skin,
    );

    // Cheveux avant.
    if (female) {
      final fringe = Path()
        ..moveTo(w * 0.31, h * 0.35)
        ..quadraticBezierTo(w * 0.39, h * 0.14, w * 0.64, h * 0.23)
        ..quadraticBezierTo(w * 0.72, h * 0.28, w * 0.68, h * 0.37)
        ..quadraticBezierTo(w * 0.56, h * 0.25, w * 0.31, h * 0.35)
        ..close();
      canvas.drawPath(fringe, hair);
    } else {
      final topHair = Path()
        ..moveTo(w * 0.31, h * 0.34)
        ..quadraticBezierTo(w * 0.32, h * 0.16, w * 0.48, h * 0.16)
        ..quadraticBezierTo(w * 0.67, h * 0.13, w * 0.70, h * 0.34)
        ..quadraticBezierTo(w * 0.55, h * 0.26, w * 0.31, h * 0.34)
        ..close();
      canvas.drawPath(topHair, hair);
    }

    // Yeux.
    canvas.drawCircle(Offset(w * 0.43, h * 0.43), w * 0.022, dark);
    canvas.drawCircle(Offset(w * 0.57, h * 0.43), w * 0.022, dark);
    final eyeLight = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(w * 0.437, h * 0.424), w * 0.007, eyeLight);
    canvas.drawCircle(Offset(w * 0.577, h * 0.424), w * 0.007, eyeLight);

    // Nez discret.
    final nose = Paint()
      ..color = const Color(0xFFC77F61)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, w * 0.011)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.505, h * 0.45),
      Offset(w * 0.49, h * 0.51),
      nose,
    );

    // Sourire.
    final smile = Paint()
      ..color = const Color(0xFF9E4F4C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, w * 0.013)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.52),
        width: w * 0.13,
        height: h * 0.08,
      ),
      0.20,
      math.pi - 0.40,
      false,
      smile,
    );

    if (!female) {
      // Barbe légère.
      final beard = Paint()
        ..color = const Color(0xAA382A24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.8, w * 0.018)
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCenter(
          center: Offset(w * 0.50, h * 0.49),
          width: w * 0.31,
          height: h * 0.30,
        ),
        0.20,
        math.pi - 0.40,
        false,
        beard,
      );
    }

    // Stéthoscope.
    final scope = Paint()
      ..color = const Color(0xFF275A4B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, w * 0.014)
      ..strokeCap = StrokeCap.round;
    final scopePath = Path()
      ..moveTo(w * 0.35, h * 0.74)
      ..quadraticBezierTo(w * 0.37, h * 0.90, w * 0.49, h * 0.91)
      ..quadraticBezierTo(w * 0.63, h * 0.90, w * 0.65, h * 0.74);
    canvas.drawPath(scopePath, scope);
    canvas.drawCircle(Offset(w * 0.50, h * 0.91), w * 0.035, scope);
  }

  @override
  bool shouldRepaint(covariant _DoctorPortraitPainter oldDelegate) =>
      oldDelegate.gender != gender;
}

/// Illustration jour/nuit destinée au hero d'accueil.
class HospitalScene extends StatefulWidget {
  final bool isNight;
  final double? height;

  const HospitalScene({super.key, required this.isNight, this.height});

  @override
  State<HospitalScene> createState() => _HospitalSceneState();
}

class _HospitalSceneState extends State<HospitalScene> {
  @override
  void initState() {
    super.initState();
    DoctorVisualPreference.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: DoctorVisualPreference.gender,
      builder: (_, gender, __) => SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _HospitalScenePainter(
            isNight: widget.isNight,
            gender: gender,
          ),
        ),
      ),
    );
  }
}

class _HospitalScenePainter extends CustomPainter {
  final bool isNight;
  final String gender;

  const _HospitalScenePainter({required this.isNight, required this.gender});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isNight
            ? const [Color(0xFF061B2E), Color(0xFF0A5C48)]
            : const [Color(0xFF60C6A1), Color(0xFF0A8053)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);

    // Soleil / lune.
    final orb = Paint()
      ..color = isNight ? const Color(0xFFFFF4C2) : const Color(0xFFFFD66B);
    final orbCenter = Offset(w * 0.82, h * 0.18);
    canvas.drawCircle(orbCenter, h * 0.105, orb);
    if (isNight) {
      final cut = Paint()..color = const Color(0xFF0A5C48);
      canvas.drawCircle(
        Offset(orbCenter.dx + h * 0.045, orbCenter.dy - h * 0.022),
        h * 0.098,
        cut,
      );
    }

    // Sol.
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.76, w, h * 0.24),
      Paint()..color = const Color(0xFF073E2C).withOpacity(0.78),
    );

    // Hôpital.
    final building = Rect.fromLTWH(w * 0.43, h * 0.32, w * 0.50, h * 0.48);
    canvas.drawRRect(
      RRect.fromRectAndRadius(building, Radius.circular(h * 0.025)),
      Paint()
        ..color = isNight ? const Color(0xFF173A52) : const Color(0xFFE8F3EE),
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.52, h * 0.24, w * 0.25, h * 0.10),
      Paint()
        ..color = isNight ? const Color(0xFF224D69) : const Color(0xFFF7FBF9),
    );

    final windowPaint = Paint()
      ..color = isNight ? const Color(0xFFFFD46A) : const Color(0xFF7DCFB1);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 5; col++) {
        final x = w * 0.47 + col * w * 0.085;
        final y = h * 0.40 + row * h * 0.11;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w * 0.050, h * 0.055),
            Radius.circular(h * 0.009),
          ),
          windowPaint
            ..color = windowPaint.color.withOpacity(
              isNight && (row + col).isOdd ? 0.30 : 0.92,
            ),
        );
      }
    }

    // Croix hospitalière.
    final cross = Paint()..color = const Color(0xFFF7FFFB).withOpacity(0.92);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.625, h * 0.255, w * 0.018, h * 0.070),
        Radius.circular(h * 0.004),
      ),
      cross,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.60, h * 0.278, w * 0.068, h * 0.022),
        Radius.circular(h * 0.004),
      ),
      cross,
    );

    // Médecin au premier plan, volontairement discret afin de préserver le texte.
    final skin = Paint()..color = const Color(0xFFF0B58F);
    final hair = Paint()
      ..color = gender == 'female'
          ? const Color(0xFF4B2D24)
          : const Color(0xFF2E241F);
    final personX = w * 0.87;
    canvas.drawCircle(Offset(personX, h * 0.54), h * 0.085, skin);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(personX, h * 0.515),
        width: h * 0.17,
        height: h * (gender == 'female' ? 0.19 : 0.13),
      ),
      math.pi,
      math.pi,
      true,
      hair,
    );
    final coat = Path()
      ..moveTo(personX - h * 0.12, h * 0.78)
      ..quadraticBezierTo(personX - h * 0.10, h * 0.62, personX, h * 0.62)
      ..quadraticBezierTo(
        personX + h * 0.10,
        h * 0.62,
        personX + h * 0.12,
        h * 0.78,
      )
      ..close();
    canvas.drawPath(coat, Paint()..color = Colors.white.withOpacity(0.88));
  }

  @override
  bool shouldRepaint(covariant _HospitalScenePainter oldDelegate) =>
      oldDelegate.isNight != isNight || oldDelegate.gender != gender;
}
