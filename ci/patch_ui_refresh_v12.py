from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"Marker not found: {label}")
    return text.replace(old, new, 1)


DOCTOR_PREF = r'''import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférence purement visuelle pour l'avatar médecin affiché dans GardeFlow.
/// Elle ne modifie ni le profil métier, ni les rôles, ni les autorisations.
class DoctorVisualPreference {
  DoctorVisualPreference._();

  static const _storageKey = 'guardeflow_doctor_visual_gender';
  static final ValueNotifier<String> gender = ValueNotifier<String>('male');

  static bool _loaded = false;
  static Future<void>? _loading;

  static Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored == 'female' || stored == 'male') {
      gender.value = stored!;
    }
    _loaded = true;
  }

  static Future<void> setGender(String value) async {
    final next = value == 'female' ? 'female' : 'male';
    await ensureLoaded();
    if (gender.value != next) gender.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, next);
  }
}
'''

DOCTOR_VISUALS = r'''import 'dart:math' as math;

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
          child: CustomPaint(
            painter: _DoctorPortraitPainter(gender: gender),
          ),
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
    final hair = Paint()..color = female
        ? const Color(0xFF4B2D24)
        : const Color(0xFF2E241F);
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
      ..color = isNight
          ? const Color(0xFFFFF4C2)
          : const Color(0xFFFFD66B);
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
        ..color = isNight
            ? const Color(0xFF173A52)
            : const Color(0xFFE8F3EE),
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.52, h * 0.24, w * 0.25, h * 0.10),
      Paint()
        ..color = isNight
            ? const Color(0xFF224D69)
            : const Color(0xFFF7FBF9),
    );

    final windowPaint = Paint()
      ..color = isNight
          ? const Color(0xFFFFD46A)
          : const Color(0xFF7DCFB1);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 5; col++) {
        final x = w * 0.47 + col * w * 0.085;
        final y = h * 0.40 + row * h * 0.11;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w * 0.050, h * 0.055),
            Radius.circular(h * 0.009),
          ),
          windowPaint..color = windowPaint.color.withOpacity(
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
      ..quadraticBezierTo(personX + h * 0.10, h * 0.62, personX + h * 0.12, h * 0.78)
      ..close();
    canvas.drawPath(coat, Paint()..color = Colors.white.withOpacity(0.88));
  }

  @override
  bool shouldRepaint(covariant _HospitalScenePainter oldDelegate) =>
      oldDelegate.isNight != isNight || oldDelegate.gender != gender;
}
'''


def patch_widgets() -> None:
    path = 'source/lib/theme/widgets.dart'
    text = read(path)
    text = text.replace(
        "border: Border.all(color: Color(0xFFD7E7F8)),",
        "border: Border.all(color: AppColors.line),",
    )

    start = text.index('class SectionLabel extends StatelessWidget {')
    end = text.index('PreferredSizeWidget appBarOf', start)
    new_section = r'''class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.25,
                      ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 7),
          Container(
            width: 34,
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.brandBright,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}

'''
    text = text[:start] + new_section + text[end:]

    hero_start = text.index('class BlueHero extends StatelessWidget {')
    new_hero = r'''class BlueHero extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const BlueHero({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0E7B68),
              AppColors.brandDark,
              const Color(0xFF0E633B),
            ],
          ),
          borderRadius: AppRadius.xlR,
          border: Border.all(color: AppColors.brandBright.withOpacity(0.36)),
          boxShadow: AppShadow.mid,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -20,
              child: Icon(
                Icons.medical_services_rounded,
                size: 150,
                color: Colors.white.withOpacity(0.045),
              ),
            ),
            Positioned(
              right: 18,
              bottom: -26,
              child: Icon(
                Icons.monitor_heart_outlined,
                size: 116,
                color: Colors.white.withOpacity(0.055),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      );
}
'''
    text = text[:hero_start] + new_hero
    write(path, text)


def patch_settings() -> None:
    path = 'source/lib/screens/application_settings_screen.dart'
    text = read(path)
    if "doctor_visual_preference.dart" not in text:
        text = text.replace(
            "import '../state/app_state.dart';\n",
            "import '../state/app_state.dart';\nimport '../services/doctor_visual_preference.dart';\n",
            1,
        )
    if "doctor_visuals.dart" not in text:
        text = text.replace(
            "import '../theme/widgets.dart';\n",
            "import '../theme/widgets.dart';\nimport '../theme/doctor_visuals.dart';\n",
            1,
        )

    if "SectionLabel('Médecin affiché')" not in text:
        marker = "          const SizedBox(height: 34),\n          Center("
        block = r'''          const SizedBox(height: 24),
          SectionLabel('Médecin affiché'),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.person_rounded,
                        color: AppColors.brandBright,
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Choisissez le médecin illustré qui vous représentera dans l’application.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.inkSoft,
                              height: 1.4,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FutureBuilder<void>(
                  future: DoctorVisualPreference.ensureLoaded(),
                  builder: (context, _) => ValueListenableBuilder<String>(
                    valueListenable: DoctorVisualPreference.gender,
                    builder: (context, selectedGender, __) {
                      return Row(
                        children: [
                          Expanded(
                            child: _DoctorVisualChoice(
                              label: 'Femme',
                              gender: 'female',
                              selected: selectedGender == 'female',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _DoctorVisualChoice(
                              label: 'Homme',
                              gender: 'male',
                              selected: selectedGender == 'male',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 34),
          Center('''
        if marker not in text:
            raise RuntimeError('Application settings insertion marker not found')
        text = text.replace(marker, block, 1)

    if 'class _DoctorVisualChoice extends StatelessWidget {' not in text:
        marker = 'class _AppearanceChoice extends StatelessWidget {'
        widget = r'''class _DoctorVisualChoice extends StatelessWidget {
  final String label;
  final String gender;
  final bool selected;

  const _DoctorVisualChoice({
    required this.label,
    required this.gender,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brand.withOpacity(0.13) : AppColors.paperAlt,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => DoctorVisualPreference.setGender(gender),
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.brandBright : AppColors.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              DoctorAvatar(gender: gender, size: 72),
              const SizedBox(height: 9),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? AppColors.brandBright : AppColors.inkFaint,
                    size: 21,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

'''
        if marker not in text:
            raise RuntimeError('Appearance choice marker not found')
        text = text.replace(marker, widget + marker, 1)

    write(path, text)


def patch_profile() -> None:
    path = 'source/lib/screens/profile_screen.dart'
    text = read(path)
    if "doctor_visuals.dart" not in text:
        text = text.replace(
            "import '../theme/widgets.dart';\n",
            "import '../theme/widgets.dart';\nimport '../theme/doctor_visuals.dart';\n",
            1,
        )

    initials = """    final initials = [user.prenom, user.nom]\n        .where((part) => part.trim().isNotEmpty)\n        .map((part) => part.trim()[0].toUpperCase())\n        .take(2)\n        .join();\n\n"""
    text = text.replace(initials, '')

    old_avatar = r'''                  Container(
                    width: 68,
                    height: 68,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.white.withOpacity(0.22)),
                    ),
                    child: Text(
                      initials.isEmpty ? '?' : initials,
                      style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w900),
                    ),
                  ),'''
    new_avatar = r'''                  const DoctorAvatar(
                    size: 72,
                    shape: DoctorAvatarShape.roundedSquare,
                    showOnlineDot: true,
                  ),'''
    text = replace_once(text, old_avatar, new_avatar, 'profile doctor avatar')

    old_admin = r'''                              Pill(
                                text: 'Admin',
                                background: Colors.white,
                                foreground: AppColors.brandDark,
                                fontSize: 10,
                              ),'''
    new_admin = r'''                              Pill(
                                text: 'Admin',
                                icon: Icons.workspace_premium_rounded,
                                background: Colors.white,
                                foreground: AppColors.brandDark,
                                fontSize: 10,
                              ),'''
    text = text.replace(old_admin, new_admin, 1)

    write(path, text)


def patch_home() -> None:
    path = 'source/lib/screens/home_screen.dart'
    text = read(path)
    if "doctor_visuals.dart" not in text:
        text = text.replace(
            "import '../theme/widgets.dart';\n",
            "import '../theme/widgets.dart';\nimport '../theme/doctor_visuals.dart';\n",
            1,
        )

    initials = r'''    final badge = appState.totalBadgeCount;
    final rawInitial = user.nom.trim();
    final initial = rawInitial.isEmpty
        ? 'D'
        : rawInitial.substring(0, 1).toUpperCase();
'''
    text = replace_once(
        text,
        initials,
        "    final badge = appState.totalBadgeCount;\n",
        'global topbar initials',
    )

    old_initial_child = r'''                  child: Text(
                    initial,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),'''
    new_initial_child = r'''                  child: const DoctorAvatar(
                    size: 34,
                    showBorder: false,
                    showOnlineDot: true,
                  ),'''
    text = replace_once(
        text,
        old_initial_child,
        new_initial_child,
        'global topbar doctor avatar',
    )

    old_colors = r'''    final heroColors = isNight
        ? const [Color(0xFF071426), Color(0xFF123D70)]
        : const [Color(0xFF55C2FF), Color(0xFF087FE8)];'''
    new_colors = r'''    final heroColors = isNight
        ? const [Color(0xFF061A29), Color(0xFF0B6047)]
        : const [Color(0xFF0A6846), Color(0xFF20B878)];'''
    text = replace_once(text, old_colors, new_colors, 'home hero colors')

    old_stack = r'''          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: -8,
                top: -14,'''
    new_stack = r'''          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Opacity(
                    opacity: isNight ? 0.72 : 0.62,
                    child: HospitalScene(isNight: isNight),
                  ),
                ),
              ),
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          Colors.black.withOpacity(isNight ? 0.58 : 0.36),
                          Colors.black.withOpacity(0.16),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -8,
                top: -14,'''
    text = replace_once(text, old_stack, new_stack, 'home hospital scene')

    # The first 30px greeting belongs to the dashboard hero.
    dashboard = text.index('class _DashboardView extends StatelessWidget {')
    font_pos = text.find('fontSize: 30,', dashboard)
    if font_pos < 0:
        raise RuntimeError('Dashboard greeting font marker not found')
    text = text[:font_pos] + 'fontSize: 27,' + text[font_pos + len('fontSize: 30,'):]

    write(path, text)


write('source/lib/services/doctor_visual_preference.dart', DOCTOR_PREF)
write('source/lib/theme/doctor_visuals.dart', DOCTOR_VISUALS)
patch_widgets()
patch_settings()
patch_profile()
patch_home()
print('GardeFlow UI refresh patch applied successfully')
